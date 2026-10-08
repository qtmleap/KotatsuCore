import XCTest

@testable import KotatsuCore

/// Scoped (endpoint-qualified) account storage, legacy migration, anonymous
/// directory, session validation and request scoping. Servers are real
/// loopback listeners; nothing resolves external DNS.
final class ScopedAccountTests: XCTestCase {

    // MARK: Fixture

    private final class Fixture: @unchecked Sendable {
        let suiteName = "app.jellyfin.tvos.tests.\(UUID().uuidString)"
        let defaults: UserDefaults
        let keychain = KeychainStore(service: "app.jellyfin.tvos.tests.\(UUID().uuidString)")
        let http: JellyfinHTTPClient
        let service: JellyfinAuthService
        var servers: [ScriptedHTTPServer] = []

        init(accessGroup: String? = nil) throws {
            defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            let placeholder = Server(
                id: "placeholder", name: "", url: URL(string: "http://127.0.0.1:1")!)
            http = JellyfinHTTPClient(server: placeholder, deviceId: "scoped-test-device")
            let store: KeychainStore
            if let accessGroup {
                store = KeychainStore(service: keychain.service, accessGroup: accessGroup)
            } else {
                store = keychain
            }
            service = JellyfinAuthService(
                http: http, keychain: store,
                defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
        }

        func serve(
            _ handler:
                @escaping @Sendable (ScriptedHTTPServer.Request) -> ScriptedHTTPServer.Response,
            id: String = UUID().uuidString, path: String = ""
        ) async throws -> Server {
            let server = try ScriptedHTTPServer(handler: handler)
            servers.append(server)
            let port = try await server.start()
            return Server(id: id, name: id, url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        }

        func seed(_ users: [StoredUser], currentRawId: String? = nil) throws {
            defaults.set(
                try JSONEncoder().encode(users), forKey: JellyfinAuthService.storedUsersKey)
            if let currentRawId {
                defaults.set(currentRawId, forKey: JellyfinAuthService.currentUserKey)
            }
        }

        func cleanUp() {
            servers.forEach { $0.stop() }
            keychain.removeEntireService()
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    private func account(_ id: String, _ name: String, _ server: Server) -> StoredUser {
        StoredUser(profile: UserProfile(id: id, name: name, serverId: server.id), server: server)
    }

    private let ok: @Sendable (ScriptedHTTPServer.Request) -> ScriptedHTTPServer.Response = { _ in
        .json([:])
    }

    // MARK: Endpoint normalisation

    func testConnectionKeyCanonicalisesEndpoint() throws {
        func key(_ s: String) -> String {
            Server(id: "x", name: "x", url: URL(string: s)!).connectionKey
        }
        XCTAssertEqual(
            key("HTTPS://Media.Example.com:443/jf/"), key("https://media.example.com/jf"))
        XCTAssertEqual(key("http://host:80"), key("http://HOST"))
        XCTAssertNotEqual(key("https://host/jf"), key("https://host/jfx"))
        XCTAssertNotEqual(
            key("https://host/jf"), key("https://host/JF"), "base path is case-sensitive")
        XCTAssertNotEqual(key("https://host"), key("https://host:8920"))
        XCTAssertNotEqual(key("https://host"), key("http://host"))
        XCTAssertEqual(key("https://user:pw@host/jf?x=1#frag"), key("https://host/jf"))
    }

    func testAccountKeyIsStableEndpointScopedAndKeepsRawId() throws {
        let a = Server(id: "a", name: "a", url: URL(string: "https://a.example/jf")!)
        let b = Server(id: "b", name: "b", url: URL(string: "https://b.example/jf")!)
        let ua = account("raw", "A", a)
        let ub = account("raw", "B", b)
        XCTAssertEqual(ua.id, "raw")
        XCTAssertEqual(ub.id, "raw")
        XCTAssertNotEqual(ua.accountKey, ub.accountKey)
        XCTAssertEqual(ua.accountKey, account("raw", "renamed", a).accountKey)
        XCTAssertEqual(ua.accountKey.count, 64)
    }

    // MARK: Legacy migration

    func testLegacyTokenMigratesBeforeCollidingAccountIsAdded() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let a = try await f.serve(ok)
        let b = try await f.serve(ok)
        let legacyA = account("shared", "Alice A", a)
        try f.seed([legacyA], currentRawId: "shared")
        f.keychain.setString("legacy-token-a", forKey: "token:shared")

        try await f.service.addUser(
            legacyA.profile.withName("Alice B"), server: b, accessToken: "token-b")

        let tokenA = await f.service.accessToken(for: legacyA)
        let tokenB = await f.service.accessToken(for: account("shared", "x", b))
        XCTAssertEqual(tokenA, "legacy-token-a", "first account's token must survive the collision")
        XCTAssertEqual(tokenB, "token-b")
        XCTAssertNil(
            f.keychain.string(forKey: "token:shared"), "legacy key removed after verified copy")
        let stored = await f.service.storedUsers()
        XCTAssertEqual(stored.count, 2)
    }

    func testAmbiguousLegacyTokenIsNeverCopied() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let a = try await f.serve(ok)
        let b = try await f.serve(ok)
        let ua = account("shared", "A", a)
        let ub = account("shared", "B", b)
        try f.seed([ua, ub], currentRawId: "shared")
        f.keychain.setString("legacy-ambiguous", forKey: "token:shared")

        let tokenA = await f.service.accessToken(for: ua)
        let tokenB = await f.service.accessToken(for: ub)
        let rawToken = await f.service.accessToken(for: "shared")

        XCTAssertNil(tokenA)
        XCTAssertNil(tokenB)
        XCTAssertNil(rawToken)
        XCTAssertEqual(f.keychain.string(forKey: "token:shared"), "legacy-ambiguous")
    }

    func testMigrationMigratesEveryUniqueIdOnFirstOperation() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let a = try await f.serve(ok)
        let b = try await f.serve(ok)
        let ua = account("only-a", "A", a)
        let ub = account("only-b", "B", b)
        try f.seed([ua, ub])
        f.keychain.setString("ta", forKey: "token:only-a")
        f.keychain.setString("tb", forKey: "token:only-b")

        _ = await f.service.storedUsers()

        XCTAssertEqual(f.keychain.string(forKey: "token:\(ua.accountKey)"), "ta")
        XCTAssertEqual(f.keychain.string(forKey: "token:\(ub.accountKey)"), "tb")
        XCTAssertNil(f.keychain.string(forKey: "token:only-a"))
        XCTAssertNil(f.keychain.string(forKey: "token:only-b"))
    }

    // MARK: Current pointer

    func testLegacyCurrentPointerResolvesOnlyWhenUnique() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let a = try await f.serve(ok)
        let b = try await f.serve(ok)
        let ua = account("shared", "A", a)
        let ub = account("shared", "B", b)
        try f.seed([ua, ub], currentRawId: "shared")
        let ambiguous = await f.service.currentUser()
        XCTAssertNil(ambiguous)

        try f.seed([ua], currentRawId: "shared")
        let unique = await f.service.currentUser()
        XCTAssertEqual(unique?.accountKey, ua.accountKey)
    }

    func testCurrentAccountKeyIsDistinctFromRawPointer() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let a = try await f.serve(ok)
        let b = try await f.serve(ok)
        try await f.service.addUser(
            UserProfile(id: "shared", name: "A", serverId: a.id), server: a, accessToken: "ta")
        try await f.service.addUser(
            UserProfile(id: "shared", name: "B", serverId: b.id), server: b, accessToken: "tb")

        let current = await f.service.currentUser()
        XCTAssertEqual(current?.server.url, b.url)
        XCTAssertEqual(
            f.defaults.string(forKey: JellyfinAuthService.currentAccountKey), current?.accountKey)
        XCTAssertEqual(f.defaults.string(forKey: JellyfinAuthService.currentUserKey), "shared")
    }

    // MARK: Scoped token / switch / removal

    func testScopedSwitchAndSignOutAffectOnlyThatAccount() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let a = try await f.serve(ok)
        let b = try await f.serve(ok)
        try await f.service.addUser(
            UserProfile(id: "shared", name: "A", serverId: a.id), server: a, accessToken: "ta")
        try await f.service.addUser(
            UserProfile(id: "shared", name: "B", serverId: b.id), server: b, accessToken: "tb")
        let ua = account("shared", "A", a)
        let ub = account("shared", "B", b)

        let tokenA = await f.service.accessToken(for: ua)
        let tokenB = await f.service.accessToken(for: ub)
        XCTAssertEqual(tokenA, "ta")
        XCTAssertEqual(tokenB, "tb")

        try await f.service.switchUser(ua)
        XCTAssertEqual(f.http.accessToken, "ta")
        XCTAssertEqual(f.http.server.url, a.url)

        // Removing the non-current account leaves the active client untouched.
        try await f.service.signOut(ub)
        XCTAssertEqual(f.http.accessToken, "ta")
        let remaining = await f.service.storedUsers()
        XCTAssertEqual(remaining.map(\.accountKey), [ua.accountKey])
        XCTAssertNil(f.keychain.string(forKey: "token:\(ub.accountKey)"))
        XCTAssertEqual(f.keychain.string(forKey: "token:\(ua.accountKey)"), "ta")

        // Removing the current account clears pointers and the shared client.
        try await f.service.signOut(ua)
        let current = await f.service.currentUser()
        XCTAssertNil(current)
        XCTAssertNil(f.http.accessToken)
        XCTAssertNil(f.defaults.string(forKey: JellyfinAuthService.currentAccountKey))
    }

    func testSignOutSendsLogoutWithExactAccountTokenToItsOwnServer() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let a = try await f.serve(ok)
        let b = try await f.serve(ok)
        try await f.service.addUser(
            UserProfile(id: "shared", name: "A", serverId: a.id), server: a, accessToken: "ta")
        try await f.service.addUser(
            UserProfile(id: "shared", name: "B", serverId: b.id), server: b, accessToken: "tb")

        try await f.service.signOut(account("shared", "A", a))

        let logoutA = f.servers[0].requests.filter { $0.path == "/Sessions/Logout" }
        XCTAssertEqual(logoutA.count, 1)
        XCTAssertEqual(logoutA.first?.headers["x-emby-token"], "ta")
        XCTAssertTrue(f.servers[1].requests.isEmpty)
        // B was current; removing A must not clear B's shared client.
        XCTAssertEqual(f.http.accessToken, "tb")
    }

    func testAddUserReplacesByAccountKeyNotRawId() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let a = try await f.serve(ok)
        let b = try await f.serve(ok)
        try await f.service.addUser(
            UserProfile(id: "shared", name: "A", serverId: a.id), server: a, accessToken: "ta")
        try await f.service.addUser(
            UserProfile(id: "shared", name: "B", serverId: b.id), server: b, accessToken: "tb")
        try await f.service.addUser(
            UserProfile(id: "shared", name: "A2", serverId: a.id), server: a, accessToken: "ta2")

        let stored = await f.service.storedUsers()
        XCTAssertEqual(stored.count, 2)
        XCTAssertEqual(Set(stored.map(\.profile.name)), ["A2", "B"])
        let tokenA = await f.service.accessToken(for: account("shared", "", a))
        XCTAssertEqual(tokenA, "ta2")
    }

    func testFailedKeychainWriteChangesNothing() async throws {
        let f = try Fixture(accessGroup: "invalid.access.group.\(UUID().uuidString)")
        defer { f.cleanUp() }
        let a = try await f.serve(ok)
        let probe = KeychainStore(
            service: f.keychain.service, accessGroup: "invalid.access.group.probe")
        guard !probe.setString("x", forKey: "probe") else {
            probe.removeValue(forKey: "probe")
            throw XCTSkip(
                "Keychain accepted an invalid access group; cannot induce a write failure")
        }

        do {
            try await f.service.addUser(
                UserProfile(id: "u", name: "U", serverId: a.id), server: a, accessToken: "t")
            XCTFail("addUser must throw when the scoped Keychain write fails")
        } catch {
            XCTAssertEqual(error as? AccountStorageError, .keychainWriteFailed)
        }
        let stored = await f.service.storedUsers()
        let current = await f.service.currentUser()
        XCTAssertTrue(stored.isEmpty)
        XCTAssertNil(current)
        XCTAssertNil(f.http.accessToken)
        XCTAssertNil(f.defaults.data(forKey: JellyfinAuthService.storedUsersKey))
    }

    // MARK: Anonymous directory

    func testPublicDirectoryIsAnonymousAndDoesNotRetargetActiveClient() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let active = try await f.serve(ok)
        let target = try await f.serve({ request in
            request.path == "/Users/Public"
                ? .json([["Id": "p1", "Name": "Pat", "ServerId": "s", "PrimaryImageTag": "tag"]])
                : ScriptedHTTPServer.Response(status: 404)
        })
        try await f.service.addUser(
            UserProfile(id: "me", name: "Me", serverId: active.id), server: active,
            accessToken: "secret")

        let users = try await f.service.listPublicUsers(server: target)

        XCTAssertEqual(users.map(\.name), ["Pat"])
        XCTAssertNotNil(users.first?.primaryImageURL)
        let request = try XCTUnwrap(f.servers[1].requests.first)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.path, "/Users/Public")
        XCTAssertNil(request.headers["x-emby-token"])
        XCTAssertFalse(request.headers["authorization"]?.contains("Token=") ?? false)
        XCTAssertNil(request.headers["cookie"])
        XCTAssertEqual(f.http.server.url, active.url, "active client must not be retargeted")
        XCTAssertEqual(f.http.accessToken, "secret")
    }

    func testPublicDirectoryHonoursBasePath() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let target = try await f.serve({ _ in .json([]) }, path: "/jf/")
        _ = try await f.service.listPublicUsers(server: target)
        XCTAssertEqual(f.servers[0].requests.first?.path, "/jf/Users/Public")
    }

    // MARK: Session validation

    func testValidateStoredSessionMapsStatuses() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let status = StatusBox()
        let s = try await f.serve({ [status] _ in
            .json(["Id": "u", "Name": "U"], status: status.value)
        })
        try await f.service.addUser(
            UserProfile(id: "u", name: "U", serverId: s.id), server: s, accessToken: "t")
        let ua = account("u", "U", s)

        let valid = await f.service.validateStoredSession(for: ua)
        XCTAssertEqual(valid, .valid)
        status.value = 401
        let unauthorized401 = await f.service.validateStoredSession(for: ua)
        XCTAssertEqual(unauthorized401, .unauthorized)
        status.value = 403
        let unauthorized403 = await f.service.validateStoredSession(for: ua)
        XCTAssertEqual(unauthorized403, .unauthorized)
        status.value = 503
        let serverError = await f.service.validateStoredSession(for: ua)
        XCTAssertEqual(serverError, .unreachable)

        let validated = f.servers[0].requests.filter { $0.path == "/Users/u" }
        XCTAssertEqual(validated.first?.headers["x-emby-token"], "t")
    }

    func testValidateStoredSessionUnreachableWhenNothingListens() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let s = try await f.serve(ok)
        try await f.service.addUser(
            UserProfile(id: "u", name: "U", serverId: s.id), server: s, accessToken: "t")
        f.servers[0].stop()
        try await Task.sleep(for: .milliseconds(100))

        let result = await f.service.validateStoredSession(for: account("u", "U", s))
        XCTAssertEqual(result, .unreachable)
    }

    func testValidateWithoutStoredTokenIsUnauthorized() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let s = try await f.serve(ok)
        let result = await f.service.validateStoredSession(for: account("ghost", "G", s))
        XCTAssertEqual(result, .unauthorized)
        XCTAssertTrue(f.servers[0].requests.isEmpty)
    }

    func testDiscardSessionPostsLogoutWithGivenTokenOnly() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let s = try await f.serve(ok)
        await f.service.discardSession(server: s, accessToken: "transient")
        let request = try XCTUnwrap(f.servers[0].requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/Sessions/Logout")
        XCTAssertEqual(request.headers["x-emby-token"], "transient")
    }

    func testAuthRequestsDoNotFollowRedirectsOutOfScope() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let other = try await f.serve(ok)
        let redirecting = try await f.serve({ [other] _ in
            .redirect(to: other.url.absoluteString + "/Users/u")
        })
        try await f.service.addUser(
            UserProfile(id: "u", name: "U", serverId: redirecting.id), server: redirecting,
            accessToken: "t")

        let result = await f.service.validateStoredSession(for: account("u", "U", redirecting))

        XCTAssertEqual(result, .unreachable)
        XCTAssertTrue(f.servers[0].requests.isEmpty, "token must never reach the redirect target")
    }

    // MARK: Image scope

    func testServerScopeBoundaries() throws {
        let scope = try XCTUnwrap(ServerScope(url: URL(string: "https://Host.example/jf/")!))
        func contains(_ s: String) -> Bool { scope.contains(URL(string: s)) }
        XCTAssertTrue(contains("https://host.example/jf"))
        XCTAssertTrue(contains("https://host.example:443/jf/Items/1/Images/Primary"))
        XCTAssertFalse(contains("https://host.example/jfx/Items"))
        XCTAssertFalse(contains("https://host.example/other"))
        XCTAssertFalse(contains("http://host.example/jf/Items"))
        XCTAssertFalse(contains("https://host.example:8443/jf/Items"))
        XCTAssertFalse(contains("https://evil.example/jf/Items"))
        XCTAssertFalse(contains("https://host.example/jf/../secret"))
        XCTAssertFalse(contains("https://host.example/jf/%2e%2e/secret"))
        XCTAssertFalse(scope.contains(nil))
    }

    func testImageModifierAttachesAuthOnlyInsideScope() throws {
        let auth = try XCTUnwrap(
            JellyfinImageAuth(
                serverURL: URL(string: "https://host.example:8920/jf")!,
                headerValue: "MediaBrowser Token=\"t\""))
        let modifier = JellyfinKingfisher.makeAuthModifier(auth: auth)
        func header(_ s: String) -> String? {
            modifier.modified(for: URLRequest(url: URL(string: s)!))?.value(
                forHTTPHeaderField: "Authorization")
        }
        XCTAssertNotNil(header("https://host.example:8920/jf/Items/1/Images/Primary"))
        XCTAssertNil(header("https://host.example:8920/jfx/Items/1"))
        XCTAssertNil(header("https://host.example/jf/Items/1"))
        XCTAssertNil(header("http://host.example:8920/jf/Items/1"))
        XCTAssertNil(header("https://image.tmdb.org/t/p/w500/x.jpg"))
    }

    func testImageRedirectStripsAuthOutsideScope() throws {
        let scope = try XCTUnwrap(ServerScope(url: URL(string: "https://host.example/jf")!))
        func redirected(_ target: String) -> URLRequest {
            var request = URLRequest(url: URL(string: target)!)
            request.setValue("MediaBrowser Token=\"t\"", forHTTPHeaderField: "Authorization")
            request.setValue("t", forHTTPHeaderField: "X-Emby-Token")
            return JellyfinKingfisher.stripAuthIfOutOfScope(request, scope: scope)
        }
        XCTAssertNil(
            redirected("https://cdn.example/a.jpg").value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(
            redirected("https://cdn.example/a.jpg").value(forHTTPHeaderField: "X-Emby-Token"))
        XCTAssertNil(
            redirected("https://host.example/jfx/a.jpg").value(forHTTPHeaderField: "Authorization"))
        XCTAssertNotNil(
            redirected("https://host.example/jf/a.jpg").value(forHTTPHeaderField: "Authorization"))
    }

    @available(*, deprecated)
    func testDeprecatedHostInitializerIsStrictHTTPSRootScope() throws {
        let auth = JellyfinImageAuth(host: "Host.Example", headerValue: "h")
        let modifier = JellyfinKingfisher.makeAuthModifier(auth: auth)
        func header(_ s: String) -> String? {
            modifier.modified(for: URLRequest(url: URL(string: s)!))?.value(
                forHTTPHeaderField: "Authorization")
        }
        XCTAssertNotNil(header("https://host.example/anything"))
        XCTAssertNil(header("http://host.example/anything"))
        XCTAssertNil(header("https://host.example:8443/anything"))
    }

    // MARK: Cancellation & stale profile writes

    func testCancelledSwitchUserLeavesSelectionUnchanged() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let a = try await f.serve(ok)
        try await f.service.addUser(
            UserProfile(id: "u", name: "U", serverId: a.id), server: a, accessToken: "t")
        try await f.service.signOut(account("u", "U", a))
        try await f.service.addUser(
            UserProfile(id: "u", name: "U", serverId: a.id), server: a, accessToken: "t2")
        f.http.updateCredentials(accessToken: "before", userId: "before")
        let service = f.service
        let ua = account("u", "U", a)

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await service.switchUser(ua)
        }
        do {
            try await task.value
            XCTFail("switchUser must throw when cancelled")
        } catch is CancellationError {
        }
        XCTAssertEqual(f.http.accessToken, "before")
    }

    func testStaleProfileRefreshDoesNotOverwriteAfterSelectionChanges() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let slow = try await f.serve({ request in
            request.path == "/Users/u"
                ? ScriptedHTTPServer.Response(
                    body: (try? JSONSerialization.data(withJSONObject: [
                        "Id": "u", "Name": "STALE", "ServerId": "s",
                    ])) ?? Data(),
                    delay: 0.6)
                : .json([:])
        })
        let other = try await f.serve(ok)
        try await f.service.addUser(
            UserProfile(id: "u", name: "Original", serverId: slow.id), server: slow,
            accessToken: "t")
        try await f.service.addUser(
            UserProfile(id: "v", name: "V", serverId: other.id), server: other, accessToken: "t")
        let slowAccount = account("u", "Original", slow)

        try await f.service.switchUser(slowAccount)
        let staleRefresh = await f.service.pendingProfileRefresh
        try await f.service.switchUser(account("v", "V", other))
        await staleRefresh?.value  // deterministic: the stale response has arrived and been dropped

        let stored = await f.service.storedUsers()
        XCTAssertEqual(stored.first { $0.id == "u" }?.profile.name, "Original")
    }

    func testCurrentAccountProfileRefreshStillApplies() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let s = try await f.serve({ _ in .json(["Id": "u", "Name": "Renamed", "ServerId": "s"]) })
        try await f.service.addUser(
            UserProfile(id: "u", name: "Old", serverId: s.id), server: s, accessToken: "t")

        try await f.service.switchUser(account("u", "Old", s))
        await f.service.pendingProfileRefresh?.value

        let stored = await f.service.storedUsers()
        XCTAssertEqual(stored.first?.profile.name, "Renamed")
    }
}

private final class StatusBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 200
    var value: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _value = newValue
        }
    }
}

extension UserProfile {
    fileprivate func withName(_ name: String) -> UserProfile {
        UserProfile(
            id: id, name: name, serverId: serverId, primaryImageURL: primaryImageURL,
            hasParentalControls: hasParentalControls)
    }
}

extension ScopedAccountTests {
    func testValidateStoredSessionRejectsMismatchedIdAndInvalidBody() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let body = BodyBox(["Id": "someone-else", "Name": "X"])
        let s = try await f.serve({ [body] _ in .json(body.value) })
        try await f.service.addUser(
            UserProfile(id: "u", name: "U", serverId: s.id), server: s, accessToken: "t")
        let ua = account("u", "U", s)
        let mismatch = await f.service.validateStoredSession(for: ua)
        XCTAssertEqual(mismatch, .unauthorized)
        body.value = ["unexpected": "html-ish"]
        let invalid = await f.service.validateStoredSession(for: ua)
        XCTAssertEqual(invalid, .unreachable)
    }

    func testValidateStoredSessionMapsNotFoundToUnauthorized() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let s = try await f.serve({ _ in ScriptedHTTPServer.Response(status: 404) })
        try await f.service.addUser(
            UserProfile(id: "u", name: "U", serverId: s.id), server: s, accessToken: "t")
        let result = await f.service.validateStoredSession(for: account("u", "U", s))
        XCTAssertEqual(result, .unauthorized)
    }

    func testAuthenticateDoesNotSendSharedClientToken() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let target = try await f.serve({ _ in
            .json(["AccessToken": "new", "User": ["Id": "u", "Name": "U"]])
        })
        f.http.updateCredentials(accessToken: "old-session-token", userId: "old")
        let result = try await f.service.authenticate(server: target, username: "u", password: "p")
        XCTAssertEqual(result.accessToken, "new")
        let request = try XCTUnwrap(f.servers[0].requests.first)
        XCTAssertNil(request.headers["x-emby-token"])
        XCTAssertFalse(request.headers["authorization"]?.contains("old-session-token") ?? false)
        XCTAssertEqual(
            f.http.accessToken, "old-session-token", "shared client must not be retargeted")
    }

    func testDiscoverRefusesRedirectOutOfScopeWithClearFailure() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let other = try await f.serve(ok)
        let redirecting = try await f.serve({ [other] _ in
            .redirect(to: other.url.absoluteString + "/System/Info/Public")
        })
        do {
            _ = try await f.service.discoverServer(url: redirecting.url)
            XCTFail("discovery must not pretend a refused redirect succeeded")
        } catch {
            XCTAssertTrue(f.servers[0].requests.isEmpty)
        }
    }

    func testDiscoverStillSucceedsInScope() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let s = try await f.serve({ _ in
            .json(["Id": "sid", "ServerName": "Home", "Version": "10.10.0"])
        })
        let found = try await f.service.discoverServer(url: s.url)
        XCTAssertEqual(found.id, "sid")
        XCTAssertEqual(found.url, s.url)
    }

    func testSignOutDuringRemoteLogoutDoesNotDeleteNewerSameAccountSignIn() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let gate = Gate()
        let s = try await f.serve({ [gate] request in
            if request.path == "/Sessions/Logout" { gate.waitBlocking() }
            return .json([:])
        })
        let ua = account("u", "U", s)
        try await f.service.addUser(ua.profile, server: s, accessToken: "old")
        let service = f.service
        let out = Task { try await service.signOut(ua) }
        // The local removal is synchronous in the actor, so by the time the
        // logout request reaches the server the old row is already gone.
        try await gate.waitForArrival()
        try await f.service.addUser(ua.profile, server: s, accessToken: "new")
        gate.release()
        try await out.value
        let token = await f.service.accessToken(for: ua)
        let stored = await f.service.storedUsers()
        XCTAssertEqual(token, "new")
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(
            f.servers[0].requests.last { $0.path == "/Sessions/Logout" }?.headers["x-emby-token"],
            "old")
    }

    func testConcurrentAddUsersOnSharedDefaultsLoseNoAccount() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let s = try await f.serve(ok)
        let second = JellyfinAuthService(
            http: JellyfinHTTPClient(server: s, deviceId: "second"), keychain: f.keychain,
            defaults: try XCTUnwrap(UserDefaults(suiteName: f.suiteName)))
        let first = f.service
        await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<8 {
                let target = i.isMultiple(of: 2) ? first : second
                group.addTask {
                    try await target.addUser(
                        UserProfile(id: "u\(i)", name: "U\(i)", serverId: s.id), server: s,
                        accessToken: "t\(i)"
                    )
                }
            }
        }
        let stored = await first.storedUsers()
        XCTAssertEqual(Set(stored.map(\.id)), Set((0..<8).map { "u\($0)" }))
    }
}

final class BodyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: [String: String]
    init(_ v: [String: String]) { _value = v }
    var value: [String: String] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _value = newValue
        }
    }
}

/// Deterministic barrier: the server handler blocks until released, and the
/// test can wait until the request has actually arrived.
final class Gate: @unchecked Sendable {
    private let arrived = DispatchSemaphore(value: 0)
    private let proceed = DispatchSemaphore(value: 0)
    func waitBlocking() {
        arrived.signal()
        proceed.wait()
    }
    func release() { proceed.signal() }
    func waitForArrival() async throws {
        let sem = arrived
        await withCheckedContinuation { c in
            DispatchQueue.global().async {
                sem.wait()
                c.resume()
            }
        }
    }
}
