import XCTest

@testable import KotatsuCore

/// Real `UserDefaults` + Keychain fixtures (isolated per test) exercising the
/// same raw Jellyfin user id appearing on two different servers.
final class ServerAccountIsolationTests: XCTestCase {

    private struct Fixture {
        let suiteName: String
        let defaults: UserDefaults
        let keychain: KeychainStore
        let service: JellyfinAuthService
        let serverA: Server
        let serverB: Server
        let tokenKeys: [String]

        func cleanUp() {
            for key in tokenKeys { keychain.removeValue(forKey: key) }
            keychain.removeEntireService()
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    private let sharedUserId = "shared-raw-user-id"
    private let tokenA = "synthetic-token-server-a"
    private let tokenB = "synthetic-token-server-b"

    /// `extraUserIds` are raw ids whose legacy `token:<id>` Keychain entries
    /// must be removed on cleanup.
    private func makeFixture(extraUserIds: [String] = []) throws -> Fixture {
        let suiteName = "app.jellyfin.tvos.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let keychain = KeychainStore(service: "app.jellyfin.tvos.tests.\(UUID().uuidString)")
        let serverA = Server(
            id: "server-a",
            name: "Server A",
            url: try XCTUnwrap(URL(string: "https://a.example.invalid"))
        )
        let serverB = Server(
            id: "server-b",
            name: "Server B",
            url: try XCTUnwrap(URL(string: "https://b.example.invalid"))
        )
        let service = JellyfinAuthService(
            http: JellyfinHTTPClient(server: serverA),
            keychain: keychain,
            defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName))
        )
        let keys = ([sharedUserId] + extraUserIds).map { "token:\($0)" }
        return Fixture(
            suiteName: suiteName,
            defaults: defaults,
            keychain: keychain,
            service: service,
            serverA: serverA,
            serverB: serverB,
            tokenKeys: keys
        )
    }

    private func profile(_ id: String, name: String, server: Server) -> UserProfile {
        UserProfile(id: id, name: name, serverId: server.id)
    }

    /// Adds the same raw user id on both servers.
    private func addCollidingAccounts(_ f: Fixture) async throws {
        try await f.service.addUser(
            profile(sharedUserId, name: "Alice on A", server: f.serverA),
            server: f.serverA,
            accessToken: tokenA
        )
        try await f.service.addUser(
            profile(sharedUserId, name: "Alice on B", server: f.serverB),
            server: f.serverB,
            accessToken: tokenB
        )
    }

    // MARK: - Same raw user id on different servers

    func testSameUserIdOnDifferentServersBothRemainStored() async throws {
        let f = try makeFixture()
        defer { f.cleanUp() }

        try await addCollidingAccounts(f)

        let stored = await f.service.storedUsers()
        XCTAssertEqual(
            stored.count, 2, "Accounts on different servers must not overwrite each other")
        XCTAssertEqual(Set(stored.map(\.server.url)), [f.serverA.url, f.serverB.url])
        XCTAssertEqual(Set(stored.map(\.profile.name)), ["Alice on A", "Alice on B"])
    }

    func testReAddingSameServerAndUserIdDoesNotDuplicate() async throws {
        let f = try makeFixture()
        defer { f.cleanUp() }

        try await addCollidingAccounts(f)
        try await f.service.addUser(
            profile(sharedUserId, name: "Alice on A (renamed)", server: f.serverA),
            server: f.serverA,
            accessToken: "synthetic-token-server-a-rotated"
        )

        let stored = await f.service.storedUsers()
        XCTAssertEqual(
            stored.count, 2,
            "Re-adding an existing server account must replace it, not duplicate it")
        XCTAssertEqual(
            stored.filter { $0.server.url == f.serverB.url }.map(\.profile.name), ["Alice on B"])
        XCTAssertEqual(
            stored.filter { $0.server.url == f.serverA.url }.map(\.profile.name),
            ["Alice on A (renamed)"]
        )
    }

    // MARK: - Ambiguous legacy raw-id operations

    func testLegacyAccessTokenIsNilWhenRawIdIsAmbiguous() async throws {
        let f = try makeFixture()
        defer { f.cleanUp() }
        try await addCollidingAccounts(f)

        let token = await f.service.accessToken(for: sharedUserId)

        XCTAssertNil(
            token, "A raw id present on two servers must not resolve to an arbitrary token")
    }

    func testLegacySwitchUserThrowsAndKeepsStateWhenRawIdIsAmbiguous() async throws {
        let f = try makeFixture()
        defer { f.cleanUp() }
        try await addCollidingAccounts(f)
        let storedBefore = await f.service.storedUsers()
        let currentBefore = await f.service.currentUser()
        let defaultsBefore = f.defaults.data(forKey: JellyfinAuthService.storedUsersKey)

        do {
            try await f.service.switchUser(id: sharedUserId)
            XCTFail("switchUser(id:) must throw when the raw id matches accounts on two servers")
        } catch {
            // expected
        }

        let storedAfter = await f.service.storedUsers()
        let currentAfter = await f.service.currentUser()
        XCTAssertEqual(storedAfter, storedBefore)
        XCTAssertEqual(storedAfter.count, 2)
        XCTAssertEqual(currentAfter, currentBefore)
        XCTAssertEqual(f.defaults.data(forKey: JellyfinAuthService.storedUsersKey), defaultsBefore)
    }

    func testLegacySignOutDoesNotRemoveAnyAccountWhenRawIdIsAmbiguous() async throws {
        let f = try makeFixture()
        defer { f.cleanUp() }
        try await addCollidingAccounts(f)
        let storedBefore = await f.service.storedUsers()
        let currentBefore = await f.service.currentUser()

        // Either throwing or no-op is acceptable; removing a row is not.
        try? await f.service.signOut(userId: sharedUserId)

        let storedAfter = await f.service.storedUsers()
        let currentAfter = await f.service.currentUser()
        XCTAssertEqual(storedAfter.count, 2, "Ambiguous signOut(userId:) must preserve both rows")
        XCTAssertEqual(Set(storedAfter), Set(storedBefore))
        XCTAssertEqual(
            currentAfter, currentBefore,
            "Ambiguous signOut(userId:) must not clear the current user")
    }

    // MARK: - Unique legacy raw-id operations remain supported

    func testLegacyOperationsStillWorkForUniqueRawIds() async throws {
        let uniqueA = "unique-user-on-a-\(UUID().uuidString)"
        let uniqueB = "unique-user-on-b-\(UUID().uuidString)"
        let f = try makeFixture(extraUserIds: [uniqueA, uniqueB])
        defer { f.cleanUp() }

        try await f.service.addUser(
            profile(uniqueA, name: "Unique A", server: f.serverA),
            server: f.serverA,
            accessToken: tokenA
        )
        try await f.service.addUser(
            profile(uniqueB, name: "Unique B", server: f.serverB),
            server: f.serverB,
            accessToken: tokenB
        )

        let tokenForA = await f.service.accessToken(for: uniqueA)
        let tokenForB = await f.service.accessToken(for: uniqueB)
        XCTAssertEqual(tokenForA, tokenA)
        XCTAssertEqual(tokenForB, tokenB)

        try await f.service.switchUser(id: uniqueA)
        let current = await f.service.currentUser()
        XCTAssertEqual(current?.id, uniqueA)
        XCTAssertEqual(current?.server.url, f.serverA.url)

        // Sign out the non-current account (avoids a network logout call).
        try await f.service.signOut(userId: uniqueB)
        let stored = await f.service.storedUsers()
        XCTAssertEqual(stored.map(\.id), [uniqueA])
        let removedToken = await f.service.accessToken(for: uniqueB)
        let keptToken = await f.service.accessToken(for: uniqueA)
        XCTAssertNil(removedToken)
        XCTAssertEqual(keptToken, tokenA)
    }

    // MARK: - Cancellation

    func testCancelledAddUserLeavesExistingStoresUnchanged() async throws {
        let f = try makeFixture()
        defer { f.cleanUp() }
        // Seed a real account on server A, then cancel adding the same raw id on server B.
        try await f.service.addUser(
            profile(sharedUserId, name: "Alice on A", server: f.serverA),
            server: f.serverA,
            accessToken: tokenA
        )
        let storedBefore = await f.service.storedUsers()
        let currentBefore = await f.service.currentUser()
        let defaultsBefore = f.defaults.data(forKey: JellyfinAuthService.storedUsersKey)
        let currentKeyBefore = f.defaults.string(forKey: JellyfinAuthService.currentUserKey)
        let scopedKey = "token:\(storedBefore[0].accountKey)"
        let keychainBefore = f.keychain.string(forKey: scopedKey)
        XCTAssertEqual(storedBefore.count, 1)
        XCTAssertEqual(keychainBefore, tokenA)

        let service = f.service
        let serverB = f.serverB
        let cancelledProfile = profile(sharedUserId, name: "Alice on B", server: serverB)
        let token = tokenB
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await service.addUser(cancelledProfile, server: serverB, accessToken: token)
        }

        do {
            try await task.value
            XCTFail("addUser should throw CancellationError when the task is cancelled")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        let storedAfter = await f.service.storedUsers()
        let currentAfter = await f.service.currentUser()
        XCTAssertEqual(storedAfter, storedBefore)
        XCTAssertEqual(currentAfter, currentBefore)
        XCTAssertEqual(f.defaults.data(forKey: JellyfinAuthService.storedUsersKey), defaultsBefore)
        XCTAssertEqual(
            f.defaults.string(forKey: JellyfinAuthService.currentUserKey), currentKeyBefore)
        XCTAssertEqual(f.keychain.string(forKey: scopedKey), keychainBefore)
    }
}
