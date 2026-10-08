import Foundation

public actor MockAuthService: AuthService {
    private var users: [StoredUser]
    private var currentAccountKey: String?

    public init(
        users: [StoredUser] = SampleData.users, currentUserId: String? = SampleData.users.first?.id
    ) {
        self.users = users
        self.currentAccountKey = users.first { $0.id == currentUserId }?.accountKey
    }

    public func discoverServer(url: URL) async throws -> Server {
        try await Task.sleep(for: .milliseconds(400))
        return Server(id: "discovered", name: "Mock Jellyfin", url: url, version: "10.10.0-mock")
    }

    public func authenticate(
        server: Server, username: String, password: String
    ) async throws -> (user: UserProfile, accessToken: String) {
        let user = UserProfile(id: username, name: username, serverId: server.id)
        let token = "mock-token-\(username)"
        try await addUser(user, server: server, accessToken: token)
        return (user, token)
    }

    public func initiateQuickConnect(server: Server) async throws -> QuickConnectSession {
        try await Task.sleep(for: .milliseconds(400))
        return QuickConnectSession(
            code: "482913",
            secret: UUID().uuidString,
            expiresAt: Date().addingTimeInterval(600)
        )
    }

    public func pollQuickConnect(
        server: Server, session: QuickConnectSession
    ) async throws
        -> QuickConnectStatus
    {
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
        users.first { $0.accountKey == currentAccountKey }
    }

    public func switchUser(id: String) async throws {
        let matches = users.filter { $0.id == id }
        guard matches.count == 1 else { throw MockError.userNotFound }
        currentAccountKey = matches[0].accountKey
    }

    public func signOut(userId: String) async throws {
        let matches = users.filter { $0.id == userId }
        guard matches.count <= 1 else { throw MockError.userNotFound }
        if let account = matches.first { try await signOut(account) }
    }

    public func addUser(_ user: UserProfile, server: Server, accessToken: String) async throws {
        let stored = StoredUser(profile: user, server: server)
        users.removeAll { $0.accountKey == stored.accountKey }
        users.append(stored)
        currentAccountKey = stored.accountKey
    }

    public func accessToken(for userId: String) async -> String? {
        let matches = users.filter { $0.id == userId }
        return matches.count == 1 ? "mock-token-\(userId)" : nil
    }

    public func listServerUsers() async throws -> [UserProfile] {
        try await Task.sleep(for: .milliseconds(200))
        return users.map(\.profile)
    }

    public func switchUser(_ account: StoredUser) async throws {
        guard let match = users.first(where: { $0.accountKey == account.accountKey }) else {
            throw MockError.userNotFound
        }
        currentAccountKey = match.accountKey
    }

    public func signOut(_ account: StoredUser) async throws {
        users.removeAll { $0.accountKey == account.accountKey }
        if currentAccountKey == account.accountKey { currentAccountKey = users.first?.accountKey }
    }

    public func accessToken(for account: StoredUser) async -> String? {
        users.contains(where: { $0.accountKey == account.accountKey })
            ? "mock-token-\(account.id)" : nil
    }

    public func listPublicUsers(server: Server) async throws -> [UserProfile] {
        users.filter { $0.server.connectionKey == server.connectionKey }.map(\.profile)
    }

    public func validateStoredSession(for account: StoredUser) async -> StoredSessionStatus {
        users.contains(where: { $0.accountKey == account.accountKey }) ? .valid : .unauthorized
    }

    public func discardSession(server: Server, accessToken: String) async {}

    enum MockError: Error { case userNotFound }
}
