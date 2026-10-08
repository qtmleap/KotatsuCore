import CryptoKit
import Foundation

/// Result of a short, uncached check of a stored account's access token.
public enum StoredSessionStatus: Sendable, Equatable {
    /// The server accepted the stored token.
    case valid
    /// The server rejected the token (401/403) or no token is stored.
    case unauthorized
    /// The server could not be reached or answered with a non-auth failure.
    case unreachable
}

/// Failures raised by the local account store itself (not by the network).
public enum AccountStorageError: Error, Sendable, Equatable {
    /// The scoped Keychain item could not be written (or read back).
    case keychainWriteFailed
    /// A raw-user-id overload matched accounts on more than one endpoint.
    case ambiguousUserId(String)
}

// MARK: - Canonical endpoint identity

extension Server {
    /// Canonical credential namespace for this server: lowercase scheme and
    /// host, default port omitted, case-sensitive percent-encoded base path
    /// without trailing slash. Userinfo, query and fragment are dropped.
    public var connectionKey: String { Server.canonicalEndpoint(url) }

    static func canonicalEndpoint(_ url: URL) -> String {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let scheme = c.scheme?.lowercased()
        else { return url.absoluteString }
        var host = (c.host ?? "").lowercased()
        if host.contains(":") { host = "[\(host)]" }
        var key = "\(scheme)://\(host)"
        if let port = c.port, port != ServerScope.defaultPort(for: scheme) {
            key += ":\(port)"
        }
        key += ServerScope.trimmedBasePath(c.percentEncodedPath)
        return key
    }
}

extension StoredUser {
    /// Stable local identity: SHA-256 of the canonical endpoint, a delimiter
    /// and the raw Jellyfin user id. `id` stays the raw user id.
    public var accountKey: String {
        let material = Data((server.connectionKey + "\n" + profile.id).utf8)
        return SHA256.hash(data: material).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Request scope

/// Scheme / host / effective port / base-path boundary that credentials may
/// be sent to. The base path matches on a path-segment boundary, so `/jf`
/// contains `/jf/Items` but not `/jfx`.
struct ServerScope: Sendable, Hashable {
    let scheme: String
    let host: String
    let port: Int
    let basePath: String

    init(scheme: String, host: String, port: Int, basePath: String) {
        self.scheme = scheme
        self.host = host
        self.port = port
        self.basePath = basePath
    }

    init?(url: URL) {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let scheme = c.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = c.host?.lowercased(), !host.isEmpty
        else { return nil }
        self.init(
            scheme: scheme,
            host: host,
            port: c.port ?? Self.defaultPort(for: scheme),
            basePath: Self.trimmedBasePath(c.percentEncodedPath)
        )
    }

    func contains(_ url: URL?) -> Bool {
        guard let url, let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
            c.user == nil, c.password == nil,
            c.scheme?.lowercased() == scheme,
            c.host?.lowercased() == host,
            (c.port ?? Self.defaultPort(for: scheme)) == port
        else { return false }
        let path = c.percentEncodedPath
        guard Self.isSafePath(path) else { return false }
        if basePath.isEmpty { return true }
        return path == basePath || path.hasPrefix(basePath + "/")
    }

    /// Conservative traversal guard: rejects encoded or raw backslashes,
    /// encoded slashes, and any segment that decodes (once or twice) to a dot
    /// segment. Plain UTF-8 paths pass.
    static func isSafePath(_ path: String) -> Bool {
        let lower = path.lowercased()
        if lower.contains("\\") || lower.contains("%5c") || lower.contains("%2f") { return false }
        if lower.contains("%252f") || lower.contains("%255c") { return false }
        for segment in path.split(separator: "/", omittingEmptySubsequences: true) {
            var decoded = String(segment)
            for _ in 0..<2 { decoded = decoded.removingPercentEncoding ?? decoded }
            if decoded == "." || decoded == ".." { return false }
            if decoded.contains("/") || decoded.contains("\\") { return false }
        }
        return true
    }

    static func defaultPort(for scheme: String) -> Int {
        switch scheme {
        case "http": return 80
        case "https": return 443
        default: return 0
        }
    }

    static func trimmedBasePath(_ path: String) -> String {
        var trimmed = path
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        return trimmed
    }
}
