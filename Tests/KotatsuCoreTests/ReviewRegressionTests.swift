import Foundation
import Security
import XCTest

@testable import KotatsuCore

final class ReviewRegressionTests: XCTestCase {
    func testEncodedTraversalDoesNotBelongToCredentialScope() throws {
        let serverURL = try XCTUnwrap(URL(string: "https://example.invalid/jf"))
        let scope = try XCTUnwrap(ServerScope(url: serverURL))
        for path in [
            "/jf/%2e%2e%2fother/image", "/jf/%252e%252e%252fother/image", "/jf/%5c..%5cother/image",
        ] {
            XCTAssertFalse(scope.contains(URL(string: "https://example.invalid" + path)))
        }
    }

    func testUnownedLegacyTokenStaysUnownedAfterRemovingOneEndpoint() async throws {
        let f = try Fixture.make()
        defer { f.cleanup() }
        f.defaults.set(
            try JSONEncoder().encode([f.a, f.b]), forKey: JellyfinAuthService.storedUsersKey)
        XCTAssertTrue(f.keychain.setString("unowned-fixture-credential", forKey: "token:shared-id"))
        let before = await f.auth.accessToken(for: f.b)
        XCTAssertTrue(before == nil)
        try await f.auth.signOut(f.a)
        let after = await f.auth.accessToken(for: f.b)
        XCTAssertTrue(
            after == nil, "Removing a row must not establish ownership of an ambiguous credential")
    }

    func testLegacyAdapterDoesNotReturnAnotherEndpointCredential() async throws {
        let f = try Fixture.make()
        defer { f.cleanup() }
        try await f.auth.addUser(
            f.a.profile, server: f.a.server, accessToken: "endpoint-a-fixture-credential")
        let adapter = LegacyAdapter(base: f.auth)
        let token = await adapter.accessToken(for: f.b)
        XCTAssertTrue(token == nil, "A scoped default must not discard the supplied endpoint")
    }

    func testLegacyAdapterCannotRemoveAnotherEndpointAccount() async throws {
        let f = try Fixture.make()
        defer { f.cleanup() }
        try await f.auth.addUser(
            f.a.profile, server: f.a.server, accessToken: "endpoint-a-fixture-credential")
        let adapter = LegacyAdapter(base: f.auth)
        try? await adapter.signOut(f.b)
        let users = await f.auth.storedUsers()
        XCTAssertEqual(users.map(\.accountKey), [f.a.accountKey])
    }

    private struct Fixture {
        let suite: String
        let defaults: UserDefaults
        let keychain: KeychainStore
        let auth: JellyfinAuthService
        let a: StoredUser
        let b: StoredUser

        static func make() throws -> Fixture {
            let suite = "kotatsu.review-tests." + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            let keychain = KeychainStore(service: "kotatsu.review-tests." + UUID().uuidString)
            let serverA = Server(
                id: "a", name: "A", url: try XCTUnwrap(URL(string: "http://127.0.0.1:1/a")))
            let serverB = Server(
                id: "b", name: "B", url: try XCTUnwrap(URL(string: "http://127.0.0.1:1/b")))
            let a = StoredUser(
                profile: UserProfile(id: "shared-id", name: "Shared", serverId: "a"),
                server: serverA)
            let b = StoredUser(
                profile: UserProfile(id: "shared-id", name: "Shared", serverId: "b"),
                server: serverB)
            let auth = JellyfinAuthService(
                http: JellyfinHTTPClient(server: serverA), keychain: keychain,
                defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
            return Fixture(
                suite: suite, defaults: defaults, keychain: keychain, auth: auth, a: a, b: b)
        }

        func cleanup() {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychain.service,
            ]
            SecItemDelete(query as CFDictionary)
            defaults.removePersistentDomain(forName: suite)
        }
    }

    /// An existing conformer deliberately implements only the original surface.
    /// The scoped methods exercise the SDK's compatibility defaults.
    private struct LegacyAdapter: AuthService {
        let base: any AuthService
        func discoverServer(url: URL) async throws -> Server {
            try await base.discoverServer(url: url)
        }
        func authenticate(
            server: Server, username: String, password: String
        ) async throws -> (
            user: UserProfile, accessToken: String
        ) {
            try await base.authenticate(server: server, username: username, password: password)
        }
        func initiateQuickConnect(server: Server) async throws -> QuickConnectSession {
            try await base.initiateQuickConnect(server: server)
        }
        func pollQuickConnect(
            server: Server, session: QuickConnectSession
        ) async throws
            -> QuickConnectStatus
        { try await base.pollQuickConnect(server: server, session: session) }
        func storedUsers() async -> [StoredUser] { await base.storedUsers() }
        func currentUser() async -> StoredUser? { await base.currentUser() }
        func switchUser(id: String) async throws { try await base.switchUser(id: id) }
        func signOut(userId: String) async throws { try await base.signOut(userId: userId) }
        func addUser(_ user: UserProfile, server: Server, accessToken: String) async throws {
            try await base.addUser(user, server: server, accessToken: accessToken)
        }
        func accessToken(for userId: String) async -> String? {
            await base.accessToken(for: userId)
        }
        func listServerUsers() async throws -> [UserProfile] { try await base.listServerUsers() }
    }
}
