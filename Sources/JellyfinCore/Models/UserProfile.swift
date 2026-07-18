import Foundation

public struct UserProfile: Sendable, Codable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let serverId: String
    public let primaryImageURL: URL?
    public let hasParentalControls: Bool

    public init(
        id: String,
        name: String,
        serverId: String,
        primaryImageURL: URL? = nil,
        hasParentalControls: Bool = false
    ) {
        self.id = id
        self.name = name
        self.serverId = serverId
        self.primaryImageURL = primaryImageURL
        self.hasParentalControls = hasParentalControls
    }
}
