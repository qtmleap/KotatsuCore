import Foundation

public enum MediaKind: String, Sendable, Codable, CaseIterable {
    case movie
    case series
    case episode
}

public struct MediaItem: Sendable, Codable, Identifiable, Hashable {
    public let id: String
    public let kind: MediaKind
    public let title: String
    public let year: Int?
    public let runtimeSeconds: Int?
    public let officialRating: String?
    public let communityRating: Double?
    public let posterURL: URL?
    public let backdropURL: URL?
    public let logoURL: URL?
    public let progressFraction: Double?
    public let isFavorite: Bool
    public let isWatched: Bool

    public init(
        id: String,
        kind: MediaKind,
        title: String,
        year: Int? = nil,
        runtimeSeconds: Int? = nil,
        officialRating: String? = nil,
        communityRating: Double? = nil,
        posterURL: URL? = nil,
        backdropURL: URL? = nil,
        logoURL: URL? = nil,
        progressFraction: Double? = nil,
        isFavorite: Bool = false,
        isWatched: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.year = year
        self.runtimeSeconds = runtimeSeconds
        self.officialRating = officialRating
        self.communityRating = communityRating
        self.posterURL = posterURL
        self.backdropURL = backdropURL
        self.logoURL = logoURL
        self.progressFraction = progressFraction
        self.isFavorite = isFavorite
        self.isWatched = isWatched
    }
}
