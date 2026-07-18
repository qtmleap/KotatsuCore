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
