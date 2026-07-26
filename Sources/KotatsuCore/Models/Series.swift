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
    /// Saved playback position from Jellyfin's `PlaybackPositionTicks`.
    /// Non-nil means the user paused midway through — use for "続きから再生".
    public let playbackPositionSeconds: TimeInterval?
    /// Distribution source parsed from the filename — same convention as
    /// `MediaItem.distributionSource`. A single title's episodes can carry
    /// different sources (Prime Video / Hulu / Crunchyroll for the same
    /// episode number) and Jellyfin returns them as separate `Episode`s.
    public let distributionSource: MediaSource?
    /// Release variant parsed from the folder name after the `[XX]` tag —
    /// e.g. `"FLCL Alternative"` for `[AP] FLCL Alternative/S01E01.mkv`.
    /// Distinguishes alternate editions Jellyfin groups under one series
    /// item; nil when the show has a single edition.
    public let releaseVariant: String?
    /// Primary media source — video codec, resolution, audio tracks. Present
    /// when the shelf request included `Fields=MediaSources,MediaStreams`.
    public let primarySource: MediaSourceInfo?
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
        playbackPositionSeconds: TimeInterval? = nil,
        distributionSource: MediaSource? = nil,
        releaseVariant: String? = nil,
        primarySource: MediaSourceInfo? = nil,
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
        self.playbackPositionSeconds = playbackPositionSeconds
        self.distributionSource = distributionSource
        self.releaseVariant = releaseVariant
        self.primarySource = primarySource
        self.isWatched = isWatched
    }
}
