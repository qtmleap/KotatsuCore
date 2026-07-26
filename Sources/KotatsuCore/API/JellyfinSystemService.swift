import Foundation

public actor JellyfinSystemService: SystemService {
    private let http: JellyfinHTTPClient

    public init(http: JellyfinHTTPClient) {
        self.http = http
    }

    public func fetchSystemInfo() async throws -> SystemInfo {
        let dto = try await http.send(SystemInfoRequest())
        return dto.toDomain()
    }

    public func fetchEncodingConfiguration() async throws -> EncodingConfiguration {
        // Admin-only. Callers should catch `JellyfinAPIError.forbidden` and
        // hide the encoding card rather than surfacing an error.
        let dto = try await http.send(EncodingOptionsRequest())
        return dto.toDomain()
    }

    public func fetchActiveSessions() async throws -> [ActiveSession] {
        let dtos = try await http.send(ActiveSessionsRequest())
        return dtos.map { $0.toDomain() }
    }
}
