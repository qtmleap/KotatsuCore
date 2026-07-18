import Foundation
import Security

/// A lightweight wrapper over the Keychain Services API for storing per-user
/// access tokens and small pieces of user/server metadata that must survive
/// device restarts and app reinstalls (as configured by the caller).
public struct KeychainStore: Sendable {
    public let service: String
    public let accessGroup: String?

    public init(service: String = "app.jellyfin.tvos.credentials", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    // MARK: - Raw data

    @discardableResult
    public func setData(_ data: Data, forKey key: String) -> Bool {
        var query = baseQuery(for: key)
        // Try update first
        let attributesToUpdate: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        if updateStatus == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            return addStatus == errSecSuccess
        }
        return false
    }

    public func data(forKey key: String) -> Data? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult
    public func removeValue(forKey key: String) -> Bool {
        let query = baseQuery(for: key)
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Strings / Codable convenience

    @discardableResult
    public func setString(_ value: String, forKey key: String) -> Bool {
        setData(Data(value.utf8), forKey: key)
    }

    public func string(forKey key: String) -> String? {
        data(forKey: key).flatMap { String(data: $0, encoding: .utf8) }
    }

    @discardableResult
    public func setCodable<T: Encodable>(_ value: T, forKey key: String) -> Bool {
        guard let data = try? JSONEncoder().encode(value) else { return false }
        return setData(data, forKey: key)
    }

    public func codable<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    // MARK: - Base query

    private func baseQuery(for account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}
