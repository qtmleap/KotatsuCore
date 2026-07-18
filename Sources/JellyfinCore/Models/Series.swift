import Foundation

public struct Season: Sendable, Codable, Identifiable, Hashable {
    public let id: String
    public let seriesId: String
    public let number: Int
    public let name: String
    public let episodeCount: Int
    public let posterURL: URL?

    public init(id: String, seriesId: String, number: Int, name: String, episodeCount: Int, posterURL: URL? = nil) {
        self.id = id
        self.seriesId = seriesId
        self.number = number
        self.name = name
        self.episodeCount = episodeCount
        self.posterURL = posterURL
    }
}

public struct Episode: Sendable, Codable, Identifiable, Hashable {
    public let id: String
    public let seriesId: String
    public let seasonId: String
    public let seasonNumber: Int
    public let episodeNumber: Int
    public let title: String
    public let overview: String?
    public let runtimeSeconds: Int?
    public let thumbnailURL: URL?
    public let progressFraction: Double?
    public let isWatched: Bool

    public init(
        id: String,
        seriesId: String,
        seasonId: String,
        seasonNumber: Int,
        episodeNumber: Int,
        title: String,
        overview: String? = nil,
        runtimeSeconds: Int? = nil,
        thumbnailURL: URL? = nil,
        progressFraction: Double? = nil,
        isWatched: Bool = false
    ) {
        self.id = id
        self.seriesId = seriesId
        self.seasonId = seasonId
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.title = title
        self.overview = overview
        self.runtimeSeconds = runtimeSeconds
        self.thumbnailURL = thumbnailURL
        self.progressFraction = progressFraction
        self.isWatched = isWatched
    }
}
