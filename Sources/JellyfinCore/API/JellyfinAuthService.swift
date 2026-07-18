import Foundation
import Alamofire
import os

/// Real `AuthService` implementation backed by a `JellyfinHTTPClient` for
/// the active session, plus a Keychain-backed store of previously
/// signed-in users so we can present a Netflix-style profile picker.
public actor JellyfinAuthService: AuthService {
    private let http: JellyfinHTTPClient
    private let keychain: KeychainStore
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "app.jellyfin.tvos", category: "auth")

    /// Called when the underlying HTTP client detects a 401. Consumers of
    /// the service can wire this to sign out or prompt for re-auth.
    public var onUnauthorized: (@Sendable () -> Void)?

    // Storage keys — kept as constants for reuse in tests.
    static let currentUserKey = "app.jellyfin.tvos.currentUserId"
    static let storedUsersKey = "app.jellyfin.tvos.storedUsers"

    public init(
        http: JellyfinHTTPClient,
        keychain: KeychainStore = KeychainStore(),
        defaults: UserDefaults = .standard
    ) {
        self.http = http
        self.keychain = keychain
        self.defaults = defaults
    }

    // MARK: - Discovery

    public func discoverServer(url: URL) async throws -> Server {
        let info = try await JellyfinHTTPClient.discover(url: url)
        return info.toDomain(serverURL: url)
    }

    // MARK: - Quick Connect

    public func initiateQuickConnect(server: Server) async throws -> QuickConnectSession {
        // Quick Connect requires the client to hit the target server, not
        // whatever the constructor was pointed at, so we swap the server on
        // the shared client for the duration of the Quick Connect flow.
        http.updateServer(server)
        let result: QuickConnectResultDTO = try await http.request(
            .post,
            path: "/QuickConnect/Initiate"
        )
        return result.toDomain()
    }

    public func pollQuickConnect(server: Server, session: QuickConnectSession) async throws -> QuickConnectStatus {
        http.updateServer(server)
        let poll: QuickConnectResultDTO = try await http.request(
            .get,
            path: "/QuickConnect/Connect",
            query: ["Secret": session.secret]
        )
        if session.expiresAt < Date() {
            return .expired
        }
        guard poll.authenticated == true else { return .pending }
        // Exchange the secret for a real access token.
        let auth: AuthenticationResultDTO = try await http.request(
            .post,
            path: "/Users/AuthenticateWithQuickConnect",
            body: AuthenticateWithQuickConnectBody(secret: session.secret)
        )
        guard let userDTO = auth.user else {
            throw JellyfinAPIError.missingField("User")
        }
        let profile = userDTO.toDomain(server: server)
        try await addUser(profile, server: server, accessToken: auth.accessToken)
        return .authenticated(profile, accessToken: auth.accessToken)
    }

    private struct AuthenticateWithQuickConnectBody: Encodable, Sendable {
        let secret: String
        enum CodingKeys: String, CodingKey { case secret = "Secret" }
    }

    // MARK: - User store

    public func storedUsers() async -> [StoredUser] {
        loadStoredUsers()
    }

    public func currentUser() async -> StoredUser? {
        guard let id = defaults.string(forKey: Self.currentUserKey) else { return nil }
        return loadStoredUsers().first { $0.id == id }
    }

    public func switchUser(id: String) async throws {
        let users = loadStoredUsers()
        guard let user = users.first(where: { $0.id == id }) else {
            throw JellyfinAPIError.notFound
        }
        guard let token = keychain.string(forKey: tokenKey(userId: id)) else {
            throw JellyfinAPIError.unauthorized
        }
        defaults.set(id, forKey: Self.currentUserKey)
        http.updateServer(user.server)
        http.updateCredentials(accessToken: token, userId: id)
    }

    public func signOut(userId: String) async throws {
        // Best effort: tell the server we're going away. Ignore transport
        // errors — signing out locally always succeeds regardless.
        if defaults.string(forKey: Self.currentUserKey) == userId {
            try? await http.send(.post, path: "/Sessions/Logout")
            defaults.removeObject(forKey: Self.currentUserKey)
            http.updateCredentials(accessToken: nil, userId: nil)
        }
        keychain.removeValue(forKey: tokenKey(userId: userId))
        var users = loadStoredUsers()
        users.removeAll { $0.id == userId }
        saveStoredUsers(users)
    }

    public func addUser(_ user: UserProfile, server: Server, accessToken: String) async throws {
        keychain.setString(accessToken, forKey: tokenKey(userId: user.id))
        var users = loadStoredUsers()
        users.removeAll { $0.id == user.id }
        users.append(StoredUser(profile: user, server: server))
        saveStoredUsers(users)
        defaults.set(user.id, forKey: Self.currentUserKey)
        http.updateServer(server)
        http.updateCredentials(accessToken: accessToken, userId: user.id)
    }

    // MARK: - Persistence helpers

    private func tokenKey(userId: String) -> String { "token:\(userId)" }

    private func loadStoredUsers() -> [StoredUser] {
        guard let data = defaults.data(forKey: Self.storedUsersKey) else { return [] }
        return (try? JSONDecoder().decode([StoredUser].self, from: data)) ?? []
    }

    private func saveStoredUsers(_ users: [StoredUser]) {
        if let data = try? JSONEncoder().encode(users) {
            defaults.set(data, forKey: Self.storedUsersKey)
        }
    }
}
