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
    /// Landscape "still frame" — for episodes this is the episode's own
    /// screencap (Jellyfin stores it as the episode's Primary image); for
    /// movies/series it's the optional Thumb image type when the server
    /// provides one. Nil when no still is available.
    public let thumbURL: URL?
    /// Parent series ID — set on episode items so navigation can "climb up"
    /// from an episode tile to its owning show's Detail page. Nil for movies
    /// and standalone series items.
    public let seriesId: String?
    /// Episode number within the season. Populated only for episode items.
    public let episodeNumber: Int?
    /// Season number within the series. Populated only for episode items.
    public let seasonNumber: Int?
    public let overview: String?
    public let genres: [String]
    /// Distribution source parsed from the filename (`[AP]` → Prime Video,
    /// `[BD]` → Blu-ray, ...). Nil when the file name carries no known tag.
    public let distributionSource: MediaSource?
    public let progressFraction: Double?
    /// User's saved playback position, seeded from Jellyfin's
    /// `UserItemDataDto.PlaybackPositionTicks`. Populated for items with
    /// resume state; nil for fresh items and for items where the server
    /// didn't include userData.
    public let playbackPositionSeconds: TimeInterval?
    public let isFavorite: Bool
    public let isWatched: Bool
    /// Sprite grid metadata when the server has generated Netflix-style
    /// scrubber previews for this item. Nil for items without trickplay.
    public let trickplay: MediaTrickplayInfo?
    /// Directory URL — one tile file per index sits at
    /// `trickplayTileBaseURL/{tileIndex}.jpg`. Populated in lockstep with
    /// `trickplay`; both are set or both are nil.
    public let trickplayTileBaseURL: URL?

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
        thumbURL: URL? = nil,
        seriesId: String? = nil,
        episodeNumber: Int? = nil,
        seasonNumber: Int? = nil,
        overview: String? = nil,
        genres: [String] = [],
        distributionSource: MediaSource? = nil,
        progressFraction: Double? = nil,
        playbackPositionSeconds: TimeInterval? = nil,
        isFavorite: Bool = false,
        isWatched: Bool = false,
        trickplay: MediaTrickplayInfo? = nil,
        trickplayTileBaseURL: URL? = nil
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
        self.thumbURL = thumbURL
        self.seriesId = seriesId
        self.episodeNumber = episodeNumber
        self.seasonNumber = seasonNumber
        self.overview = overview
        self.genres = genres
        self.distributionSource = distributionSource
        self.progressFraction = progressFraction
        self.playbackPositionSeconds = playbackPositionSeconds
        self.isFavorite = isFavorite
        self.isWatched = isWatched
        self.trickplay = trickplay
        self.trickplayTileBaseURL = trickplayTileBaseURL
    }

    /// Resolves the URL for a specific trickplay tile file. Returns nil when
    /// the item has no trickplay data attached.
    public func trickplayTileURL(tileIndex: Int) -> URL? {
        trickplayTileBaseURL?.appendingPathComponent("\(tileIndex).jpg")
    }

    /// Best URL to display in a 16:9 landscape tile. For episodes we want
    /// the episode still (`thumbURL`) — that's what Netflix shows on
    /// Continue Watching. Falls back to the backdrop hero art (which for
    /// episodes resolves to the parent series's backdrop via the DTO's
    /// `ParentBackdropItemId` chain), then the poster as a last resort.
    public var landscapeURL: URL? {
        thumbURL ?? backdropURL ?? posterURL
    }
}
