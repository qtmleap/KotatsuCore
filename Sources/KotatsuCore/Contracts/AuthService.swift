import Foundation

public protocol AuthService: Sendable {
    func discoverServer(url: URL) async throws -> Server
    func initiateQuickConnect(server: Server) async throws -> QuickConnectSession
    func pollQuickConnect(server: Server, session: QuickConnectSession) async throws -> QuickConnectStatus
    func storedUsers() async -> [StoredUser]
    func currentUser() async -> StoredUser?
    func switchUser(id: String) async throws
    func signOut(userId: String) async throws
    func addUser(_ user: UserProfile, server: Server, accessToken: String) async throws
    /// Returns the stored access token for a previously-added user, or `nil`
    /// if we don't have credentials for them (signed out, corrupted keychain).
    /// Callers use this to rebuild `ServiceContainer.real(...)` when switching
    /// profiles or re-hydrating after launch.
    func accessToken(for userId: String) async -> String?
    /// Fetch every user visible on the current server. Used by SyncPlay to
    /// map participant usernames back to `UserProfile` (needed for avatars,
    /// since `/SyncPlay/List` only sends usernames).
    func listServerUsers() async throws -> [UserProfile]
}

public struct StoredUser: Sendable, Codable, Identifiable, Hashable {
    public let profile: UserProfile
    public let server: Server

    public var id: String { profile.id }

    public init(profile: UserProfile, server: Server) {
        self.profile = profile
        self.server = server
    }
}
