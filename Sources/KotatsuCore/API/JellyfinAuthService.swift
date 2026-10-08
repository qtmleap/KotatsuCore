import Alamofire
import Foundation
import os

/// Real `AuthService` implementation backed by a `JellyfinHTTPClient` for
/// the active session, plus a Keychain-backed store of previously
/// signed-in users so we can present a Netflix-style profile picker.
public actor JellyfinAuthService: AuthService {
    private struct AuthenticateByNameBody: Encodable, Sendable {
        let username: String
        let password: String

        private enum CodingKeys: String, CodingKey {
            case username = "Username"
            case password = "Pw"
        }
    }

    private let http: JellyfinHTTPClient
    private let store: JellyfinAccountStore
    private let logger = Logger(subsystem: "app.jellyfin.tvos", category: "auth")

    /// Called when the underlying HTTP client detects a 401. Consumers of
    /// the service can wire this to sign out or prompt for re-auth.
    public var onUnauthorized: (@Sendable () -> Void)?

    // Storage keys — kept as constants for reuse in tests.
    static let currentUserKey = JellyfinAccountStore.currentUserKey
    static let currentAccountKey = JellyfinAccountStore.currentAccountKey
    static let storedUsersKey = JellyfinAccountStore.storedUsersKey

    /// Bumped on every selection change; background profile refreshes capture
    /// it and drop their result when it no longer matches.
    private var selectionGeneration = 0
    private var refreshTask: Task<Void, Never>?

    public init(
        http: JellyfinHTTPClient,
        keychain: KeychainStore = KeychainStore(),
        defaults: UserDefaults = .standard
    ) {
        self.http = http
        self.store = JellyfinAccountStore(keychain: keychain, defaults: defaults)
    }

    /// Storage-injecting initializer for fault-injection tests.
    init(http: JellyfinHTTPClient, storage: any CredentialStorage, defaults: sending UserDefaults) {
        self.http = http
        self.store = JellyfinAccountStore(keychain: storage, defaults: defaults)
    }

    /// The in-flight profile refresh, so tests can await it instead of sleeping.
    var pendingProfileRefresh: Task<Void, Never>? { refreshTask }

    // MARK: - Anonymous requests

    /// Auth, Quick Connect and discovery never touch the shared client: each
    /// call uses a fresh anonymous snapshot, so a token left on the client by
    /// the previous session can neither be sent to the target server nor race
    /// with media requests while the client is retargeted.
    private func anonymous<T: Decodable & Sendable>(
        _ method: String, server: Server, path: String,
        query: [URLQueryItem] = [], body: Data? = nil, as type: T.Type
    ) async throws -> T {
        let snapshot = JellyfinSnapshotRequest(
            server: server, accessToken: nil, deviceId: http.deviceId)
        let data = try await snapshot.perform(method, path: path, query: query, body: body)
        do {
            return try JellyfinJSON.decoder.decode(T.self, from: data)
        } catch {
            throw JellyfinAPIError.decoding(underlying: String(describing: error))
        }
    }

    // MARK: - Discovery

    /// Probes the typed URL within its own scope. A redirect that leaves the
    /// scheme/host/port/base path (for example http -> https) is refused with
    /// a clear failure rather than followed, because credentials would later
    /// be refused for that endpoint anyway; the caller should enter the
    /// canonical URL.
    public func discoverServer(url: URL) async throws -> Server {
        let probe = Server(id: "", name: "", url: url)
        let info: SystemInfoPublicDTO = try await anonymous(
            "GET", server: probe, path: "/System/Info/Public", as: SystemInfoPublicDTO.self)
        return info.toDomain(serverURL: url)
    }

    // MARK: - Authentication

    public func authenticate(
        server: Server, username: String, password: String
    ) async throws -> (user: UserProfile, accessToken: String) {
        let body = try JellyfinJSON.encoder.encode(
            AuthenticateByNameBody(username: username, password: password))
        let result: AuthenticationResultDTO = try await anonymous(
            "POST", server: server, path: "/Users/AuthenticateByName", body: body,
            as: AuthenticationResultDTO.self)
        guard let user = result.user else {
            throw JellyfinAPIError.missingField("User")
        }
        return (user.toDomain(server: server), result.accessToken)
    }

    // MARK: - Quick Connect

    public func initiateQuickConnect(server: Server) async throws -> QuickConnectSession {
        let result: QuickConnectResultDTO = try await anonymous(
            "POST", server: server, path: "/QuickConnect/Initiate", as: QuickConnectResultDTO.self)
        return result.toDomain()
    }

    public func pollQuickConnect(
        server: Server, session: QuickConnectSession
    ) async throws
        -> QuickConnectStatus
    {
        let poll: QuickConnectResultDTO = try await anonymous(
            "GET", server: server, path: "/QuickConnect/Connect",
            query: [URLQueryItem(name: "Secret", value: session.secret)],
            as: QuickConnectResultDTO.self)
        if session.expiresAt < Date() {
            return .expired
        }
        guard poll.authenticated == true else { return .pending }
        // Exchange the secret for a real access token.
        let body = try JellyfinJSON.encoder.encode(
            AuthenticateWithQuickConnectRequest.Body(secret: session.secret))
        let auth: AuthenticationResultDTO = try await anonymous(
            "POST", server: server, path: "/Users/AuthenticateWithQuickConnect", body: body,
            as: AuthenticationResultDTO.self)
        guard let userDTO = auth.user else {
            throw JellyfinAPIError.missingField("User")
        }
        let profile = userDTO.toDomain(server: server)
        // The caller commits the account after validating its active sign-in flow,
        // just as with username/password authentication.
        try Task.checkCancellation()
        return .authenticated(profile, accessToken: auth.accessToken)
    }

    // MARK: - User store

    public func storedUsers() async -> [StoredUser] {
        store.users()
    }

    public func currentUser() async -> StoredUser? {
        store.currentAccount()
    }

    public func switchUser(id: String) async throws {
        guard let account = try store.uniqueAccount(rawId: id) else {
            throw JellyfinAPIError.notFound
        }
        try await switchUser(account)
    }

    public func switchUser(_ account: StoredUser) async throws {
        try Task.checkCancellation()
        guard let user = store.storedAccount(account) else {
            throw JellyfinAPIError.notFound
        }
        guard let token = store.token(for: user) else {
            throw JellyfinAPIError.unauthorized
        }
        try Task.checkCancellation()
        select(user, token: token)
        startProfileRefresh(for: user, token: token)
    }

    /// Applies an account to the shared client and the current pointers.
    private func select(_ user: StoredUser, token: String) {
        selectionGeneration += 1
        refreshTask?.cancel()
        refreshTask = nil
        store.setCurrent(user)
        http.updateServer(user.server)
        http.updateCredentials(accessToken: token, userId: user.profile.id)
    }

    /// Refresh `/Users/{id}` from an immutable snapshot so a changed avatar /
    /// display name propagates into the stored user list. The write is dropped
    /// when the selection, account or token changed in the meantime.
    private func startProfileRefresh(for user: StoredUser, token: String) {
        let generation = selectionGeneration
        let snapshot = JellyfinSnapshotRequest(
            server: user.server, accessToken: token, deviceId: http.deviceId)
        refreshTask = Task { [weak self] in
            do {
                let data = try await snapshot.perform(
                    "GET", path: "/Users/" + JellyfinSnapshotRequest.pathSegment(user.profile.id))
                let dto = try JellyfinJSON.decoder.decode(UserDTO.self, from: data)
                try Task.checkCancellation()
                await self?.applyRefreshedProfile(
                    dto, for: user, token: token, generation: generation)
            } catch {
                AppLogger.warning("Failed to refresh user profile: \(error)")
            }
        }
    }

    private func applyRefreshedProfile(
        _ dto: UserDTO, for user: StoredUser, token: String, generation: Int
    ) {
        guard !Task.isCancelled,
            generation == selectionGeneration,
            store.currentAccountKeyValue == user.accountKey,
            http.accessToken == token
        else { return }
        store.replaceProfile(dto.toDomain(server: user.server), forKey: user.accountKey)
    }

    public func signOut(userId: String) async throws {
        guard let account = try store.uniqueAccount(rawId: userId) else {
            // Unknown id: only drop a stray legacy token that no stored
            // account could own.
            store.keychain.removeValue(forKey: JellyfinAccountStore.legacyTokenKey(rawId: userId))
            return
        }
        try await signOut(account)
    }

    public func signOut(_ account: StoredUser) async throws {
        // Remove exactly this local account and token first, synchronously,
        // so a same-account sign-in added while the remote logout is in
        // flight can never be deleted by this call.
        let removed = store.removeAccount(account)
        if store.currentAccountKeyValue == account.accountKey {
            store.clearCurrent()
            selectionGeneration += 1
            refreshTask?.cancel()
            refreshTask = nil
            http.updateCredentials(accessToken: nil, userId: nil)
        }
        // Best effort: revoke exactly the captured token on its own server.
        // Transport errors are ignored — signing out locally always succeeds.
        if let removed, let token = removed.token {
            await discardSession(server: removed.account.server, accessToken: token)
        }
    }

    public func accessToken(for userId: String) async -> String? {
        guard let account = try? store.uniqueAccount(rawId: userId) else { return nil }
        return store.token(for: account)
    }

    public func accessToken(for account: StoredUser) async -> String? {
        guard let stored = store.storedAccount(account) else { return nil }
        return store.token(for: stored)
    }

    public func listServerUsers() async throws -> [UserProfile] {
        let dtos = try await http.send(GetUsersRequest())
        let server = http.server
        return dtos.map { $0.toDomain(server: server) }
    }

    // MARK: - Anonymous directory & session checks

    public func listPublicUsers(server: Server) async throws -> [UserProfile] {
        let snapshot = JellyfinSnapshotRequest(
            server: server, accessToken: nil, deviceId: http.deviceId)
        let data = try await snapshot.perform("GET", path: "/Users/Public")
        let dtos: [UserDTO]
        do {
            dtos = try JellyfinJSON.decoder.decode([UserDTO].self, from: data)
        } catch {
            throw JellyfinAPIError.decoding(underlying: String(describing: error))
        }
        return dtos.map { $0.toDomain(server: server) }
    }

    /// Validates the stored token against `/Users/{id}` and requires the
    /// response to be that exact user. A cancelled caller MUST discard the
    /// result: cancellation is reported as `.unreachable`, never as a verdict
    /// on the token (callers should check `Task.isCancelled` afterwards).
    public func validateStoredSession(for account: StoredUser) async -> StoredSessionStatus {
        guard let stored = store.storedAccount(account),
            let token = store.token(for: stored)
        else { return .unauthorized }
        let snapshot = JellyfinSnapshotRequest(
            server: stored.server, accessToken: token, deviceId: http.deviceId)
        do {
            let data = try await snapshot.perform(
                "GET", path: "/Users/" + JellyfinSnapshotRequest.pathSegment(stored.profile.id))
            guard let dto = try? JellyfinJSON.decoder.decode(UserDTO.self, from: data) else {
                return .unreachable
            }
            return dto.id.caseInsensitiveCompare(stored.profile.id) == .orderedSame
                ? .valid : .unauthorized
        } catch JellyfinAPIError.unauthorized, JellyfinAPIError.forbidden, JellyfinAPIError.notFound
        {
            return .unauthorized
        } catch {
            return .unreachable
        }
    }

    public func discardSession(server: Server, accessToken: String) async {
        let snapshot = JellyfinSnapshotRequest(
            server: server, accessToken: accessToken, deviceId: http.deviceId)
        _ = try? await snapshot.perform("POST", path: "/Sessions/Logout")
    }

    public func addUser(_ user: UserProfile, server: Server, accessToken: String) async throws {
        try Task.checkCancellation()
        let account = StoredUser(profile: user, server: server)
        // Throws, changing nothing, when the scoped write fails or when the
        // insertion could strand an unresolved legacy token.
        try store.addAccount(account, token: accessToken)
        select(account, token: accessToken)
    }
}
