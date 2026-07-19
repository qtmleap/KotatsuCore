import Foundation

/// Server administration surface. Every method is admin-recommended:
/// non-admin sessions will get a limited SystemInfo, a 403 on encoding
/// options, and only their own sessions. Callers should handle
/// `JellyfinAPIError.forbidden` gracefully rather than gating the UI.
public protocol SystemService: Sendable {
    func fetchSystemInfo() async throws -> SystemInfo
    func fetchEncodingConfiguration() async throws -> EncodingConfiguration
    func fetchActiveSessions() async throws -> [ActiveSession]
}
