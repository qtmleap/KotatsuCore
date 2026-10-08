import Foundation

public protocol AuthService: Sendable {
    func discoverServer(url: URL) async throws -> Server
    func authenticate(
        server: Server, username: String, password: String
    ) async throws -> (user: UserProfile, accessToken: String)
    func initiateQuickConnect(server: Server) async throws -> QuickConnectSession
    func pollQuickConnect(
        server: Server, session: QuickConnectSession
    ) async throws
        -> QuickConnectStatus
    func storedUsers() async -> [StoredUser]
    func currentUser() async -> StoredUser?
    /// Raw-id overload: resolves only a unique stored match, throws otherwise.
    func switchUser(id: String) async throws
    /// Raw-id overload: acts only on a unique stored match, throws if ambiguous.
    func signOut(userId: String) async throws
    func addUser(_ user: UserProfile, server: Server, accessToken: String) async throws
    /// Returns the stored access token for a previously-added user, or `nil`
    /// if we don't have credentials for them (signed out, corrupted keychain,
    /// or the raw id is ambiguous across endpoints).
    func accessToken(for userId: String) async -> String?
    /// Fetch every user visible on the current server. Used by SyncPlay to
    /// map participant usernames back to `UserProfile` (needed for avatars,
    /// since `/SyncPlay/List` only sends usernames).
    func listServerUsers() async throws -> [UserProfile]

    // MARK: Scoped accounts

    /// Select exactly this account (by `accountKey`).
    func switchUser(_ account: StoredUser) async throws
    /// Remove exactly this account and its token.
    func signOut(_ account: StoredUser) async throws
    func accessToken(for account: StoredUser) async -> String?
    /// Anonymous `GET /Users/Public`; carries no credentials and never
    /// retargets the active client.
    func listPublicUsers(server: Server) async throws -> [UserProfile]
    /// Short, uncached check of the account's stored token.
    func validateStoredSession(for account: StoredUser) async -> StoredSessionStatus
    /// Best-effort, transient logout of a token that was never persisted.
    func discardSession(server: Server, accessToken: String) async
}

extension AuthService {
    /// Compatibility defaults for conformers that only implement the raw-id
    /// API. They fail closed: the supplied account is forwarded as a raw id
    /// only when it is the unique stored account with that `accountKey` and
    /// raw id, so a different endpoint's account is never touched.
    public func switchUser(_ account: StoredUser) async throws {
        guard await uniqueStoredMatch(account) != nil else { throw JellyfinAPIError.notFound }
        try await switchUser(id: account.id)
    }
    public func signOut(_ account: StoredUser) async throws {
        guard await uniqueStoredMatch(account) != nil else { throw JellyfinAPIError.notFound }
        try await signOut(userId: account.id)
    }
    public func accessToken(for account: StoredUser) async -> String? {
        guard await uniqueStoredMatch(account) != nil else { return nil }
        return await accessToken(for: account.id)
    }
    public func listPublicUsers(server: Server) async throws -> [UserProfile] {
        throw JellyfinAPIError.invalidResponse
    }
    /// Cannot be verified without a scoped implementation: `.unauthorized`
    /// without a token, otherwise `.unreachable` (never a false `.valid`).
    public func validateStoredSession(for account: StoredUser) async -> StoredSessionStatus {
        await accessToken(for: account) == nil ? .unauthorized : .unreachable
    }
    public func discardSession(server: Server, accessToken: String) async {}

    private func uniqueStoredMatch(_ account: StoredUser) async -> StoredUser? {
        let all = await storedUsers()
        guard all.filter({ $0.id == account.id }).count == 1 else { return nil }
        return all.first { $0.accountKey == account.accountKey }
    }
}

public struct StoredUser: Sendable, Codable, Identifiable, Hashable {
    public let profile: UserProfile
    public let server: Server

    /// Raw Jellyfin user id (kept for network compatibility). Use
    /// `accountKey` for local selection, deletion and SwiftUI identity.
    public var id: String { profile.id }

    public init(profile: UserProfile, server: Server) {
        self.profile = profile
        self.server = server
    }
}
