import XCTest
@testable import KotatsuCore

final class KeychainStoreTests: XCTestCase {

    private func makeStore() -> KeychainStore {
        // Isolate to a per-test service string so tests don't collide with
        // real app credentials or with each other across runs.
        KeychainStore(service: "app.jellyfin.tvos.tests.\(UUID().uuidString)")
    }

    func testWriteThenRead() {
        let s = makeStore()
        let key = "user-1"
        XCTAssertTrue(s.setString("access-token-abcdef", forKey: key))
        XCTAssertEqual(s.string(forKey: key), "access-token-abcdef")
        s.removeValue(forKey: key)
    }

    func testOverwrite() {
        let s = makeStore()
        let key = "user-2"
        XCTAssertTrue(s.setString("first", forKey: key))
        XCTAssertTrue(s.setString("second", forKey: key))
        XCTAssertEqual(s.string(forKey: key), "second")
        s.removeValue(forKey: key)
    }

    func testRemove() {
        let s = makeStore()
        let key = "user-3"
        s.setString("temp", forKey: key)
        XCTAssertTrue(s.removeValue(forKey: key))
        XCTAssertNil(s.string(forKey: key))
    }

    func testCodableRoundTrip() {
        struct Payload: Codable, Equatable { let token: String; let created: Date }
        let s = makeStore()
        let payload = Payload(token: "xyz", created: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertTrue(s.setCodable(payload, forKey: "payload"))
        let restored = s.codable(Payload.self, forKey: "payload")
        XCTAssertEqual(restored?.token, payload.token)
        s.removeValue(forKey: "payload")
    }
}
