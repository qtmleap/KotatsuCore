import CryptoKit
import Foundation

/// The slice of `KeychainStore` the account store needs. Internal so tests can
/// inject write / read faults without any production switch.
protocol CredentialStorage: Sendable {
    func string(forKey key: String) -> String?
    @discardableResult func setString(_ value: String, forKey key: String) -> Bool
    @discardableResult func removeValue(forKey key: String) -> Bool
}

extension KeychainStore: CredentialStorage {}

/// Persistence for stored accounts: profile JSON in `UserDefaults`, tokens in
/// the Keychain under `token:<accountKey>`. Legacy `token:<rawUserId>` entries
/// are migrated lazily, on every operation, for every uniquely identified
/// raw id; there is deliberately no "migration finished" flag so a partial
/// failure is retried next time (and `migrateLegacyTokens` reports it).
///
/// A legacy token seen while its raw id is shared by several accounts is
/// *unowned*: the raw id is recorded and the token is never claimed by any
/// account, even if the ambiguity later disappears.
///
/// Read-modify-write sequences on `UserDefaults` run under one process-wide
/// recursive lock (`transaction`) because several auth actors may share the
/// same defaults. The lock is never held across an `await`.
struct JellyfinAccountStore {
    static let currentUserKey = "app.jellyfin.tvos.currentUserId"
    static let currentAccountKey = "app.jellyfin.tvos.currentAccountKey"
    static let storedUsersKey = "app.jellyfin.tvos.storedUsers"
    static let unownedLegacyKey = "app.jellyfin.tvos.quarantinedLegacyTokens"

    private static let lock = NSRecursiveLock()

    let keychain: any CredentialStorage
    let defaults: UserDefaults

    func transaction<T>(_ body: () throws -> T) rethrows -> T {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return try body()
    }

    // MARK: Keys

    static func tokenKey(_ account: StoredUser) -> String { "token:\(account.accountKey)" }
    static func legacyTokenKey(rawId: String) -> String { "token:\(rawId)" }

    // MARK: Accounts

    func users() -> [StoredUser] {
        transaction {
            migrateLegacyTokens()
            return loadUsers()
        }
    }

    private func loadUsers() -> [StoredUser] {
        guard let data = defaults.data(forKey: Self.storedUsersKey) else { return [] }
        return (try? JSONDecoder().decode([StoredUser].self, from: data)) ?? []
    }

    func saveUsers(_ users: [StoredUser]) {
        if let data = try? JSONEncoder().encode(users) {
            defaults.set(data, forKey: Self.storedUsersKey)
        }
    }

    /// The stored row with this account key, if any.
    func storedAccount(_ account: StoredUser) -> StoredUser? {
        let key = account.accountKey
        return users().first { $0.accountKey == key }
    }

    /// The single stored account with this raw id; throws when several
    /// endpoints share it, returns nil when none does.
    func uniqueAccount(rawId: String) throws -> StoredUser? {
        let matches = users().filter { $0.profile.id == rawId }
        if matches.count > 1 { throw AccountStorageError.ambiguousUserId(rawId) }
        return matches.first
    }

    /// Replaces the stored profile of exactly this account, if still stored.
    func replaceProfile(_ profile: UserProfile, forKey key: String) {
        transaction {
            var all = users()
            guard let idx = all.firstIndex(where: { $0.accountKey == key }) else { return }
            guard profile.id == all[idx].profile.id else { return }
            all[idx] = StoredUser(profile: profile, server: all[idx].server)
            saveUsers(all)
        }
    }

    /// Inserts or replaces the account together with its token. The scoped
    /// write happens first; nothing else changes when it fails, or while an
    /// unresolved legacy token of a *different* account with the same raw id
    /// could be stranded by the new row.
    func addAccount(_ account: StoredUser, token: String) throws {
        try transaction {
            let unresolved = migrateLegacyTokens()
            var all = loadUsers()
            let key = account.accountKey
            if unresolved.contains(account.profile.id),
                !all.contains(where: { $0.accountKey == key })
            {
                throw AccountStorageError.keychainWriteFailed
            }
            guard writeToken(token, for: account) else {
                throw AccountStorageError.keychainWriteFailed
            }
            // A fresh scoped sign-in supersedes any legacy copy, including
            // one left behind by a failed migration/delete. Record ownership
            // loss before deletion so a failed delete cannot restore it later.
            let legacyKey = Self.legacyTokenKey(rawId: account.profile.id)
            if let legacy = keychain.string(forKey: legacyKey) {
                var digests = unownedDigests()
                digests[account.profile.id] = Self.digest(legacy)
                setUnownedDigests(digests)
                keychain.removeValue(forKey: legacyKey)
            }
            all.removeAll { $0.accountKey == key }
            all.append(account)
            saveUsers(all)
        }
    }

    /// Removes exactly this account's row and token(s) and returns the token
    /// that was stored, so the caller can revoke it remotely afterwards.
    func removeAccount(_ account: StoredUser) -> (account: StoredUser, token: String?)? {
        transaction {
            migrateLegacyTokens()
            var all = loadUsers()
            let key = account.accountKey
            guard let target = all.first(where: { $0.accountKey == key }) else {
                removeToken(for: account)
                return nil
            }
            let token = self.token(for: target)
            removeToken(for: target)
            if all.filter({ $0.profile.id == target.profile.id }).count == 1 {
                keychain.removeValue(forKey: Self.legacyTokenKey(rawId: target.profile.id))
            }
            all.removeAll { $0.accountKey == key }
            saveUsers(all)
            return (target, token)
        }
    }

    // MARK: Current pointer

    func currentAccount() -> StoredUser? {
        let all = users()
        if let key = defaults.string(forKey: Self.currentAccountKey) {
            return all.first { $0.accountKey == key }
        }
        if let raw = defaults.string(forKey: Self.currentUserKey) {
            let matches = all.filter { $0.profile.id == raw }
            return matches.count == 1 ? matches[0] : nil
        }
        return nil
    }

    var currentAccountKeyValue: String? {
        if let key = defaults.string(forKey: Self.currentAccountKey) { return key }
        return currentAccount()?.accountKey
    }

    func setCurrent(_ account: StoredUser) {
        defaults.set(account.accountKey, forKey: Self.currentAccountKey)
        // Raw id is kept for compatibility resolution only.
        defaults.set(account.profile.id, forKey: Self.currentUserKey)
    }

    func clearCurrent() {
        defaults.removeObject(forKey: Self.currentAccountKey)
        defaults.removeObject(forKey: Self.currentUserKey)
    }

    // MARK: Tokens

    /// The scoped token. If migration of this account's legacy token is still
    /// unresolved, the legacy token (the newer write) is returned instead of
    /// losing it.
    func token(for account: StoredUser) -> String? {
        transaction {
            let unresolved = migrateLegacyTokens()
            if unresolved.contains(account.profile.id),
                let legacy = keychain.string(forKey: Self.legacyTokenKey(rawId: account.profile.id))
            {
                return legacy
            }
            return keychain.string(forKey: Self.tokenKey(account))
        }
    }

    /// Writes the scoped token. A successful Keychain write is authoritative:
    /// a failed read-back would not mean the credential is unchanged, so it is
    /// not used to report failure. False means the write itself failed.
    func writeToken(_ token: String, for account: StoredUser) -> Bool {
        keychain.setString(token, forKey: Self.tokenKey(account))
    }

    func removeToken(for account: StoredUser) {
        keychain.removeValue(forKey: Self.tokenKey(account))
    }

    // MARK: Migration

    /// raw id -> digest of the quarantined legacy token.
    private func unownedDigests() -> [String: String] {
        (defaults.dictionary(forKey: Self.unownedLegacyKey) as? [String: String]) ?? [:]
    }

    private func setUnownedDigests(_ value: [String: String]) {
        if value.isEmpty {
            defaults.removeObject(forKey: Self.unownedLegacyKey)
        } else {
            defaults.set(value, forKey: Self.unownedLegacyKey)
        }
    }

    private static func digest(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Moves each uniquely identified legacy token to its scoped key and
    /// returns the raw ids whose legacy token could not be moved. The legacy
    /// entry is deleted only after the scoped write reads back. When both
    /// exist and differ, the legacy one is newer (a downgraded build signed in
    /// again) and replaces the scoped one. A legacy token seen while several
    /// accounts share the raw id is quarantined (digest recorded) and never
    /// copied; once the ambiguity ends that exact token is discarded, never
    /// promoted to an owner. A different (fresh) legacy token is not affected.
    @discardableResult
    func migrateLegacyTokens() -> Set<String> {
        transaction {
            let all = loadUsers()
            let counts = Dictionary(grouping: all, by: \.profile.id).mapValues(\.count)
            let original = unownedDigests()
            var quarantine = original
            var unresolved = Set<String>()

            for (rawId, count) in counts where count > 1 {
                if let legacy = keychain.string(forKey: Self.legacyTokenKey(rawId: rawId)) {
                    quarantine[rawId] = Self.digest(legacy)
                }
            }
            for (rawId, recorded) in quarantine where counts[rawId] ?? 0 <= 1 {
                let key = Self.legacyTokenKey(rawId: rawId)
                if let legacy = keychain.string(forKey: key), Self.digest(legacy) == recorded {
                    guard keychain.removeValue(forKey: key) else { continue }
                }
                quarantine.removeValue(forKey: rawId)
            }
            if quarantine != original { setUnownedDigests(quarantine) }

            for user in all where counts[user.profile.id] == 1 && quarantine[user.profile.id] == nil
            {
                let legacyKey = Self.legacyTokenKey(rawId: user.profile.id)
                guard let legacy = keychain.string(forKey: legacyKey) else { continue }
                let scopedKey = Self.tokenKey(user)
                if keychain.string(forKey: scopedKey) != legacy {
                    guard keychain.setString(legacy, forKey: scopedKey),
                        keychain.string(forKey: scopedKey) == legacy
                    else {
                        unresolved.insert(user.profile.id)
                        continue
                    }
                }
                // A verified copy consumes this exact legacy value. If its
                // deletion fails, it must never override a later scoped login.
                var consumed = unownedDigests()
                consumed[user.profile.id] = Self.digest(legacy)
                setUnownedDigests(consumed)
                keychain.removeValue(forKey: legacyKey)
            }
            if defaults.string(forKey: Self.currentAccountKey) == nil,
                let raw = defaults.string(forKey: Self.currentUserKey)
            {
                let matches = all.filter { $0.profile.id == raw }
                if matches.count == 1 {
                    defaults.set(matches[0].accountKey, forKey: Self.currentAccountKey)
                }
            }
            return unresolved
        }
    }
}
