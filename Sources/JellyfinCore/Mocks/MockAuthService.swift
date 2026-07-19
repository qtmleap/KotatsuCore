import Foundation

public actor MockAuthService: AuthService {
    private var users: [StoredUser]
    private var currentUserId: String?

    public init(users: [StoredUser] = SampleData.users, currentUserId: String? = SampleData.users.first?.id) {
        self.users = users
        self.currentUserId = currentUserId
    }

    public func discoverServer(url: URL) async throws -> Server {
        try await Task.sleep(for: .milliseconds(400))
        return Server(id: "discovered", name: "Mock Jellyfin", url: url, version: "10.10.0-mock")
    }

    public func initiateQuickConnect(server: Server) async throws -> QuickConnectSession {
        try await Task.sleep(for: .milliseconds(400))
        return QuickConnectSession(
            code: "482913",
            secret: UUID().uuidString,
            expiresAt: Date().addingTimeInterval(600)
        )
    }

    public func pollQuickConnect(server: Server, session: QuickConnectSession) async throws -> QuickConnectStatus {
        try await Task.sleep(for: .seconds(2))
        let mockUser = UserProfile(
            id: "quick-\(UUID().uuidString.prefix(8))",
            name: "新規ユーザー",
            serverId: server.id,
            primaryImageURL: URL(string: "https://picsum.photos/seed/newuser/400/400")
        )
        return .authenticated(mockUser, accessToken: "mock-token-\(UUID().uuidString)")
    }

    public func storedUsers() async -> [StoredUser] { users }

    public func currentUser() async -> StoredUser? {
        users.first { $0.id == currentUserId }
    }

    public func switchUser(id: String) async throws {
        guard users.contains(where: { $0.id == id }) else {
            throw MockError.userNotFound
        }
        currentUserId = id
    }

    public func signOut(userId: String) async throws {
        users.removeAll { $0.id == userId }
        if currentUserId == userId { currentUserId = users.first?.id }
    }

    public func addUser(_ user: UserProfile, server: Server, accessToken: String) async throws {
        let stored = StoredUser(profile: user, server: server)
        users.append(stored)
        currentUserId = stored.id
    }

    public func accessToken(for userId: String) async -> String? {
        users.contains(where: { $0.id == userId }) ? "mock-token-\(userId)" : nil
    }

    enum MockError: Error { case userNotFound }
}
