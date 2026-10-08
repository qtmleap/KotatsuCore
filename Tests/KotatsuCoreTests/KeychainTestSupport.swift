import Foundation
import Security

@testable import KotatsuCore

extension KeychainStore {
    /// Test utility: deletes every item stored under this store's unique
    /// service, so scoped and legacy keys are both cleaned up.
    func removeEntireService() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
