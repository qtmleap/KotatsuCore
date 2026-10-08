import XCTest

@testable import KotatsuCore

/// Keychain fault injection through the internal `CredentialStorage` seam.
private final class FaultyStorage: CredentialStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: String] = [:]
    var failWrites: Set<String> = []
    var failNextWrites: [String: Int] = [:]
    var failReadsAfterWrite: Set<String> = []
    private var unreadable: Set<String> = []

    func string(forKey key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return unreadable.contains(key) ? nil : items[key]
    }
    func setString(_ value: String, forKey key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if failWrites.contains(key) { return false }
        if let count = failNextWrites[key], count > 0 {
            failNextWrites[key] = count - 1
            return false
        }
        items[key] = value
        if failReadsAfterWrite.contains(key) { unreadable.insert(key) }
        return true
    }
    var failRemovals: Set<String> = []
    func removeValue(forKey key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if failRemovals.contains(key) { return false }
        items.removeValue(forKey: key)
        return true
    }
    func raw(_ key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return items[key]
    }
    func seed(_ value: String, _ key: String) {
        lock.lock()
        defer { lock.unlock() }
        items[key] = value
    }
}

final class StorageFaultTests: XCTestCase {
    private struct Fixture {
        let suite = "app.jellyfin.tvos.tests.\(UUID().uuidString)"
        let defaults: UserDefaults
        let storage = FaultyStorage()
        let service: JellyfinAuthService
        let a: StoredUser
        let b: StoredUser

        init() throws {
            defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            let sa = Server(id: "a", name: "A", url: URL(string: "http://127.0.0.1:1/a")!)
            let sb = Server(id: "b", name: "B", url: URL(string: "http://127.0.0.1:1/b")!)
            a = StoredUser(profile: UserProfile(id: "shared", name: "A", serverId: "a"), server: sa)
            b = StoredUser(profile: UserProfile(id: "shared", name: "B", serverId: "b"), server: sb)
            let actorSuite = suite
            let actorDefaults = try XCTUnwrap(UserDefaults(suiteName: actorSuite))
            let actorStorage = storage
            service = JellyfinAuthService(
                http: JellyfinHTTPClient(server: sa, deviceId: "fault-test"), storage: actorStorage,
                defaults: actorDefaults)
        }
        func seed(_ users: [StoredUser]) throws {
            defaults.set(
                try JSONEncoder().encode(users), forKey: JellyfinAuthService.storedUsersKey)
        }
        func cleanUp() { defaults.removePersistentDomain(forName: suite) }
    }

    func testSuccessfulWriteWithFailingReadBackStillCountsAsWritten() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        f.storage.failReadsAfterWrite = ["token:\(f.a.accountKey)"]
        try await f.service.addUser(f.a.profile, server: f.a.server, accessToken: "tok")
        let stored = await f.service.storedUsers()
        XCTAssertEqual(stored.map(\.accountKey), [f.a.accountKey])
        XCTAssertEqual(f.storage.raw("token:\(f.a.accountKey)"), "tok", "OS write is authoritative")
    }

    func testFailedMigrationBlocksCollidingInsertionUntilResolved() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        try f.seed([f.a])
        f.storage.seed("legacy-a", "token:shared")
        f.storage.failWrites = ["token:\(f.a.accountKey)"]

        do {
            try await f.service.addUser(f.b.profile, server: f.b.server, accessToken: "tb")
            XCTFail("colliding insertion must be blocked while A's legacy token is unmigrated")
        } catch {
            XCTAssertEqual(error as? AccountStorageError, .keychainWriteFailed)
        }
        XCTAssertEqual(f.storage.raw("token:shared"), "legacy-a", "A's token is not stranded")
        let blocked = await f.service.storedUsers()
        XCTAssertEqual(blocked.map(\.accountKey), [f.a.accountKey])
        let legacyStillUsable = await f.service.accessToken(for: f.a)
        XCTAssertEqual(
            legacyStillUsable, "legacy-a", "failed migration falls back to the legacy token")

        f.storage.failWrites = []
        try await f.service.addUser(f.b.profile, server: f.b.server, accessToken: "tb")
        let tokenA = await f.service.accessToken(for: f.a)
        XCTAssertEqual(tokenA, "legacy-a")
        XCTAssertNil(f.storage.raw("token:shared"))
    }

    func testQuarantinedTokenIsDiscardedButFreshLegacyTokenIsKept() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        try f.seed([f.a, f.b])
        f.storage.seed("ambiguous", "token:shared")
        _ = await f.service.storedUsers()  // quarantines the ambiguous token

        try f.seed([f.b])  // ambiguity ends
        _ = await f.service.storedUsers()
        XCTAssertNil(
            f.storage.raw("token:shared"), "quarantined token is discarded, never promoted")
        let none = await f.service.accessToken(for: f.b)
        XCTAssertNil(none)

        // Re-quarantine, then a downgraded build writes a different, fresh token.
        try f.seed([f.a, f.b])
        f.storage.seed("ambiguous-2", "token:shared")
        _ = await f.service.storedUsers()
        f.storage.seed("fresh-after-downgrade", "token:shared")
        try f.seed([f.b])
        _ = await f.service.storedUsers()
        let fresh = await f.service.accessToken(for: f.b)
        XCTAssertEqual(
            fresh, "fresh-after-downgrade", "fresh unique legacy token must not be silently lost")
    }

    func testLegacyTokenNewerThanScopedTokenWinsAfterDowngrade() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        try f.seed([f.a])
        f.storage.seed("old-scoped", "token:\(f.a.accountKey)")
        f.storage.seed("new-legacy", "token:shared")
        let token = await f.service.accessToken(for: f.a)
        XCTAssertEqual(token, "new-legacy")
        XCTAssertNil(f.storage.raw("token:shared"))
    }

    // MARK: Direct account-store regressions

    private func makeStore(_ f: Fixture) -> JellyfinAccountStore {
        JellyfinAccountStore(keychain: f.storage, defaults: f.defaults)
    }

    /// Scoped writes fail so the old legacy token stays unresolved; a later
    /// successful re-auth of the same account must not be reverted to it.
    func testFreshReauthAfterUnresolvedMigrationIsNotRevertedToOldLegacyToken() throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let store = makeStore(f)
        try f.seed([f.a])
        f.storage.seed("old-legacy", "token:shared")
        f.storage.failWrites = [JellyfinAccountStore.tokenKey(f.a)]
        XCTAssertEqual(store.migrateLegacyTokens(), ["shared"])

        f.storage.failWrites = []
        // The migration attempt in addAccount fails once; its fresh write then
        // succeeds. Re-authentication must supersede the unresolved old token.
        f.storage.failNextWrites = [JellyfinAccountStore.tokenKey(f.a): 1]
        try store.addAccount(f.a, token: "fresh-reauth")

        XCTAssertEqual(store.token(for: f.a), "fresh-reauth")
        XCTAssertEqual(store.users().count, 1)
        XCTAssertEqual(
            store.token(for: f.a), "fresh-reauth", "stays fresh across repeated migrations")
        XCTAssertEqual(f.storage.raw(JellyfinAccountStore.tokenKey(f.a)), "fresh-reauth")
        XCTAssertNotEqual(
            f.storage.raw("token:shared"), "old-legacy", "old legacy must be gone or tombstoned")
    }

    /// Migration succeeds but deleting the legacy entry fails; re-auth afterwards
    /// must still win over the lingering old legacy copy.
    func testFreshReauthWinsWhenLegacyDeletionFailed() throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let store = makeStore(f)
        try f.seed([f.a])
        f.storage.seed("old-legacy", "token:shared")
        f.storage.failRemovals = ["token:shared"]
        store.migrateLegacyTokens()
        XCTAssertEqual(f.storage.raw(JellyfinAccountStore.tokenKey(f.a)), "old-legacy")
        XCTAssertEqual(f.storage.raw("token:shared"), "old-legacy", "deletion was injected to fail")

        try store.addAccount(f.a, token: "fresh-reauth")
        XCTAssertEqual(store.token(for: f.a), "fresh-reauth")
        _ = store.users()
        XCTAssertEqual(f.storage.raw(JellyfinAccountStore.tokenKey(f.a)), "fresh-reauth")

        f.storage.failRemovals = []
        XCTAssertEqual(store.token(for: f.a), "fresh-reauth")
        XCTAssertEqual(f.storage.raw(JellyfinAccountStore.tokenKey(f.a)), "fresh-reauth")
    }

    /// Expected behavior: a replacement profile whose raw id differs textually
    /// is rejected; row identity, current pointer and token stay intact.
    func testReplaceProfileWithDifferentRawIdKeepsIdentityPointerAndToken() throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let store = makeStore(f)
        try store.addAccount(f.a, token: "tok-a")
        store.setCurrent(f.a)

        let changed = UserProfile(id: "SHARED", name: "Renamed", serverId: "a")
        store.replaceProfile(changed, forKey: f.a.accountKey)

        let users = store.users()
        XCTAssertEqual(users.map(\.accountKey), [f.a.accountKey])
        XCTAssertEqual(
            users.first?.profile.id, "shared", "raw id of the stored row must not change")
        XCTAssertEqual(store.currentAccount()?.accountKey, f.a.accountKey)
        XCTAssertEqual(store.token(for: f.a), "tok-a")
        XCTAssertEqual(f.storage.raw(JellyfinAccountStore.tokenKey(f.a)), "tok-a")
        XCTAssertNil(store.storedAccount(StoredUser(profile: changed, server: f.a.server)))
    }

    /// While A and B still collide, the legacy token changes. Removing B must
    /// not let A inherit the newly observed (still unowned) token.
    func testLegacyTokenChangedDuringCollisionIsNeverInheritedAfterRemovingOther() throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let store = makeStore(f)
        try f.seed([f.a, f.b])
        f.storage.seed("first-ambiguous", "token:shared")
        _ = store.users()  // quarantines the first token

        f.storage.seed("newer-ambiguous", "token:shared")  // changed while collision persists
        _ = store.users()
        XCTAssertNil(store.token(for: f.a))
        XCTAssertNil(store.token(for: f.b))

        try f.seed([f.a])  // B removed, ambiguity ends
        _ = store.users()
        XCTAssertNil(store.token(for: f.a), "A must never inherit an unowned legacy token")
        XCTAssertNil(f.storage.raw(JellyfinAccountStore.tokenKey(f.a)))
        _ = store.users()
        XCTAssertNil(store.token(for: f.a))
    }
}
