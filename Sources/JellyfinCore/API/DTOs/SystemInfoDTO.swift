import Foundation

/// Response for `GET /System/Info/Public`.
public struct SystemInfoPublicDTO: Codable, Sendable {
    public let localAddress: String?
    public let serverName: String?
    public let version: String?
    public let productName: String?
    public let operatingSystem: String?
    public let id: String?
    public let startupWizardCompleted: Bool?

    private enum CodingKeys: String, CodingKey {
        case localAddress = "LocalAddress"
        case serverName = "ServerName"
        case version = "Version"
        case productName = "ProductName"
        case operatingSystem = "OperatingSystem"
        case id = "Id"
        case startupWizardCompleted = "StartupWizardCompleted"
    }

    /// Convert to the public `Server` domain type. `serverURL` is the URL
    /// the caller used to discover the server (the server itself sometimes
    /// reports a `LocalAddress` that is inaccessible from clients).
    public func toDomain(serverURL: URL) -> Server {
        Server(
            id: id ?? UUID().uuidString,
            name: serverName ?? "Jellyfin",
            url: serverURL,
            version: version
        )
    }
}
