import Foundation

public struct Server: Sendable, Codable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let url: URL
    public let version: String?

    public init(id: String, name: String, url: URL, version: String? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.version = version
    }
}
