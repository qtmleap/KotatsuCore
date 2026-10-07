import XCTest
@testable import KotatsuCore

final class JellyfinAuthCancellationTests: XCTestCase {

    func testAddUserThrowsCancellationAndPersistsNothingWhenCancelled() async throws {
        let suiteName = "app.jellyfin.tvos.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let keychain = KeychainStore(service: "app.jellyfin.tvos.tests.\(UUID().uuidString)")
        let userId = "cancelled-user-\(UUID().uuidString)"
        let tokenKey = "token:\(userId)"
        defer {
            keychain.removeValue(forKey: tokenKey)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let server = Server(
            id: "cancel-server",
            name: "Cancellation Test Server",
            url: try XCTUnwrap(URL(string: "https://example.invalid"))
        )
        let profile = UserProfile(id: userId, name: "Cancelled User", serverId: server.id)
        let service = JellyfinAuthService(
            http: JellyfinHTTPClient(server: server),
            keychain: keychain,
            defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName))
        )

        let task = Task {
            // Cancel the current task before reaching the persistence boundary.
            withUnsafeCurrentTask { $0?.cancel() }
            try await service.addUser(profile, server: server, accessToken: "synthetic-token")
        }

        do {
            try await task.value
            XCTFail("addUser should throw CancellationError when the task is cancelled")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        let storedUsers = await service.storedUsers()
        let currentUser = await service.currentUser()
        let accessToken = await service.accessToken(for: userId)
        XCTAssertTrue(storedUsers.isEmpty)
        XCTAssertNil(currentUser)
        XCTAssertNil(accessToken)
        XCTAssertNil(keychain.string(forKey: tokenKey))
        XCTAssertNil(defaults.data(forKey: JellyfinAuthService.storedUsersKey))
        XCTAssertNil(defaults.string(forKey: JellyfinAuthService.currentUserKey))
    }
}
