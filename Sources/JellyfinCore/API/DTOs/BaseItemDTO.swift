import Foundation

/// One JSON object type covers Movie / Series / Episode / Season in the
/// Jellyfin API. Optional fields let each concrete kind ignore what it
/// doesn't need.
public struct BaseItemDTO: Codable, Sendable, Hashable {
    public let id: String
    public let name: String?
    public let originalTitle: String?
    public let type: String?
    public let mediaType: String?
    public let productionYear: Int?
    public let runTimeTicks: Int64?
    public let officialRating: String?
    public let communityRating: Double?
    public let overview: String?
    public let tagline: String?
    public let genres: [String]?
    public let userData: UserItemDataDTO?

    // Image tags — the key is the image kind ("Primary", "Backdrop", "Logo", "Thumb").
    public let imageTags: [String: String]?
    public let backdropImageTags: [String]?
    public let parentBackdropItemId: String?
    public let parentBackdropImageTags: [String]?
    public let seriesId: String?
    public let seriesName: String?
    public let seasonId: String?
    public let seasonName: String?
    public let indexNumber: Int?
    public let parentIndexNumber: Int?
    public let childCount: Int?

    public let mediaSources: [MediaSourceDTO]?

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case originalTitle = "OriginalTitle"
        case type = "Type"
        case mediaType = "MediaType"
        case productionYear = "ProductionYear"
        case runTimeTicks = "RunTimeTicks"
        case officialRating = "OfficialRating"
        case communityRating = "CommunityRating"
        case overview = "Overview"
        case tagline = "Tagline"
        case genres = "Genres"
        case userData = "UserData"
        case imageTags = "ImageTags"
        case backdropImageTags = "BackdropImageTags"
        case parentBackdropItemId = "ParentBackdropItemId"
        case parentBackdropImageTags = "ParentBackdropImageTags"
        case seriesId = "SeriesId"
        case seriesName = "SeriesName"
        case seasonId = "SeasonId"
        case seasonName = "SeasonName"
        case indexNumber = "IndexNumber"
        case parentIndexNumber = "ParentIndexNumber"
        case childCount = "ChildCount"
        case mediaSources = "MediaSources"
    }

    public var mediaKind: MediaKind? {
        switch type?.lowercased() {
        case "movie": return .movie
        case "series": return .series
        case "episode": return .episode
        default: return nil
        }
    }

    public var runtimeSeconds: Int? {
        guard let ticks = runTimeTicks else { return nil }
        return Int(ticks / 10_000_000)
    }

    /// URL for a stored image tag, or nil if the tag isn't present.
    public func imageURL(kind: String, server: Server, maxWidth: Int? = nil) -> URL? {
        let tag: String?
        switch kind {
        case "Backdrop":
            tag = backdropImageTags?.first ?? parentBackdropImageTags?.first
        default:
            tag = imageTags?[kind]
        }
        guard let tag, !tag.isEmpty else { return nil }
        let itemForImage: String
        if kind == "Backdrop", let parent = parentBackdropItemId, backdropImageTags == nil {
            itemForImage = parent
        } else {
            itemForImage = id
        }
        var comps = URLComponents(url: server.url, resolvingAgainstBaseURL: false)!
        var basePath = server.url.path
        if basePath.hasSuffix("/") { basePath.removeLast() }
        let suffix = kind == "Backdrop" ? "/Items/\(itemForImage)/Images/Backdrop/0" : "/Items/\(itemForImage)/Images/\(kind)"
        comps.path = basePath + suffix
        var query: [URLQueryItem] = [
            URLQueryItem(name: "tag", value: tag),
            URLQueryItem(name: "quality", value: "90")
        ]
        if let maxWidth {
            query.append(URLQueryItem(name: "maxWidth", value: "\(maxWidth)"))
        }
        comps.queryItems = query
        return comps.url
    }

    public func toMediaItem(server: Server) -> MediaItem {
        let kind = mediaKind ?? .movie
        return MediaItem(
            id: id,
            kind: kind,
            title: name ?? originalTitle ?? "Untitled",
            year: productionYear,
            runtimeSeconds: runtimeSeconds,
            officialRating: officialRating,
            communityRating: communityRating,
            posterURL: imageURL(kind: "Primary", server: server, maxWidth: 600),
            backdropURL: imageURL(kind: "Backdrop", server: server, maxWidth: 1920),
            logoURL: imageURL(kind: "Logo", server: server, maxWidth: 800),
            progressFraction: userData?.playedPercentageFraction,
            isFavorite: userData?.isFavorite ?? false,
            isWatched: userData?.played ?? false
        )
    }

    public func toDetail(server: Server) -> MediaDetail {
        MediaDetail(
            item: toMediaItem(server: server),
            overview: overview,
            genres: genres ?? [],
            tagline: tagline,
            mediaSources: (mediaSources ?? []).map { $0.toDomain() }
        )
    }

    public func toEpisode(server: Server) -> Episode {
        Episode(
            id: id,
            seriesId: seriesId ?? "",
            seasonId: seasonId ?? "",
            seasonNumber: parentIndexNumber ?? 0,
            episodeNumber: indexNumber ?? 0,
            title: name ?? "Untitled",
            overview: overview,
            runtimeSeconds: runtimeSeconds,
            thumbnailURL: imageURL(kind: "Primary", server: server, maxWidth: 480)
                ?? imageURL(kind: "Thumb", server: server, maxWidth: 480),
            progressFraction: userData?.playedPercentageFraction,
            isWatched: userData?.played ?? false
        )
    }

    public func toSeason(server: Server, fallbackSeriesId: String? = nil) -> Season {
        Season(
            id: id,
            seriesId: seriesId ?? fallbackSeriesId ?? "",
            number: indexNumber ?? 0,
            name: name ?? "Season",
            episodeCount: childCount ?? 0,
            posterURL: imageURL(kind: "Primary", server: server, maxWidth: 400)
        )
    }
}

public struct UserItemDataDTO: Codable, Sendable, Hashable {
    public let played: Bool?
    public let isFavorite: Bool?
    public let playCount: Int?
    public let playbackPositionTicks: Int64?
    public let playedPercentage: Double?

    private enum CodingKeys: String, CodingKey {
        case played = "Played"
        case isFavorite = "IsFavorite"
        case playCount = "PlayCount"
        case playbackPositionTicks = "PlaybackPositionTicks"
        case playedPercentage = "PlayedPercentage"
    }

    public var playedPercentageFraction: Double? {
        if let p = playedPercentage { return max(0, min(1, p / 100)) }
        return nil
    }
}

public struct MediaSourceDTO: Codable, Sendable, Hashable {
    public let id: String
    public let container: String?
    public let name: String?
    public let mediaStreams: [MediaStreamDTO]?
    public let bitrate: Int?
    public let size: Int64?

    // Playback decision flags — populated by /Items/{id}/PlaybackInfo.
    public let supportsDirectPlay: Bool?
    public let supportsDirectStream: Bool?
    public let supportsTranscoding: Bool?
    public let transcodingUrl: String?
    public let transcodingSubProtocol: String?
    public let transcodingContainer: String?

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case container = "Container"
        case name = "Name"
        case mediaStreams = "MediaStreams"
        case bitrate = "Bitrate"
        case size = "Size"
        case supportsDirectPlay = "SupportsDirectPlay"
        case supportsDirectStream = "SupportsDirectStream"
        case supportsTranscoding = "SupportsTranscoding"
        case transcodingUrl = "TranscodingUrl"
        case transcodingSubProtocol = "TranscodingSubProtocol"
        case transcodingContainer = "TranscodingContainer"
    }

    public var videoStream: MediaStreamDTO? {
        mediaStreams?.first { $0.type?.lowercased() == "video" }
    }

    public var audioStreams: [MediaStreamDTO] {
        (mediaStreams ?? []).filter { $0.type?.lowercased() == "audio" }
    }

    public var subtitleStreams: [MediaStreamDTO] {
        (mediaStreams ?? []).filter { $0.type?.lowercased() == "subtitle" }
    }

    public func toDomain() -> MediaSourceInfo {
        let video = videoStream
        return MediaSourceInfo(
            id: id,
            container: container,
            videoCodec: video?.codec,
            videoProfile: video?.profile,
            width: video?.width,
            height: video?.height,
            videoBitrate: video?.bitRate ?? bitrate,
            audioTracks: audioStreams.map { $0.toAudio() },
            subtitleTracks: subtitleStreams.map { $0.toSubtitle() }
        )
    }
}

public struct MediaStreamDTO: Codable, Sendable, Hashable {
    public let index: Int?
    public let type: String?
    public let codec: String?
    public let profile: String?
    public let language: String?
    public let title: String?
    public let displayTitle: String?
    public let width: Int?
    public let height: Int?
    public let bitRate: Int?
    public let channels: Int?
    public let isDefault: Bool?
    public let isForced: Bool?
    public let isExternal: Bool?
    public let isTextSubtitleStream: Bool?

    private enum CodingKeys: String, CodingKey {
        case index = "Index"
        case type = "Type"
        case codec = "Codec"
        case profile = "Profile"
        case language = "Language"
        case title = "Title"
        case displayTitle = "DisplayTitle"
        case width = "Width"
        case height = "Height"
        case bitRate = "BitRate"
        case channels = "Channels"
        case isDefault = "IsDefault"
        case isForced = "IsForced"
        case isExternal = "IsExternal"
        case isTextSubtitleStream = "IsTextSubtitleStream"
    }

    func toAudio() -> AudioTrackDescriptor {
        AudioTrackDescriptor(
            id: index ?? 0,
            language: language,
            codec: codec,
            channels: channels,
            displayTitle: displayTitle ?? title ?? (codec ?? "Audio")
        )
    }

    func toSubtitle() -> SubtitleTrackDescriptor {
        SubtitleTrackDescriptor(
            id: index ?? 0,
            language: language,
            codec: codec,
            isForced: isForced ?? false,
            isImageBased: !(isTextSubtitleStream ?? true),
            displayTitle: displayTitle ?? title ?? language ?? (codec ?? "Subtitle")
        )
    }
}

/// Standard `QueryResult<BaseItemDto>` wrapper used by most media list
/// endpoints (`/Users/{id}/Items`, `/Shows/NextUp`, etc.).
public struct BaseItemQueryResultDTO: Codable, Sendable {
    public let items: [BaseItemDTO]
    public let totalRecordCount: Int?
    public let startIndex: Int?

    private enum CodingKeys: String, CodingKey {
        case items = "Items"
        case totalRecordCount = "TotalRecordCount"
        case startIndex = "StartIndex"
    }
}

/// `GET /Search/Hints` returns hint objects, not full BaseItemDto. Enough
/// fields overlap that we can reduce to `MediaItem` for the UI.
public struct SearchHintResultDTO: Codable, Sendable {
    public let searchHints: [SearchHintDTO]
    public let totalRecordCount: Int?

    private enum CodingKeys: String, CodingKey {
        case searchHints = "SearchHints"
        case totalRecordCount = "TotalRecordCount"
    }
}

public struct SearchHintDTO: Codable, Sendable {
    public let itemId: String?
    public let id: String?
    public let name: String?
    public let type: String?
    public let productionYear: Int?
    public let runTimeTicks: Int64?
    public let primaryImageTag: String?

    private enum CodingKeys: String, CodingKey {
        case itemId = "ItemId"
        case id = "Id"
        case name = "Name"
        case type = "Type"
        case productionYear = "ProductionYear"
        case runTimeTicks = "RunTimeTicks"
        case primaryImageTag = "PrimaryImageTag"
    }

    public func toMediaItem(server: Server) -> MediaItem? {
        let resolvedId = itemId ?? id
        guard let resolvedId else { return nil }
        let kind: MediaKind
        switch type?.lowercased() {
        case "movie": kind = .movie
        case "series": kind = .series
        case "episode": kind = .episode
        default: return nil
        }
        var poster: URL?
        if let tag = primaryImageTag, !tag.isEmpty {
            var comps = URLComponents(url: server.url, resolvingAgainstBaseURL: false)!
            var basePath = server.url.path
            if basePath.hasSuffix("/") { basePath.removeLast() }
            comps.path = basePath + "/Items/\(resolvedId)/Images/Primary"
            comps.queryItems = [
                URLQueryItem(name: "tag", value: tag),
                URLQueryItem(name: "quality", value: "90"),
                URLQueryItem(name: "maxWidth", value: "600")
            ]
            poster = comps.url
        }
        return MediaItem(
            id: resolvedId,
            kind: kind,
            title: name ?? "Untitled",
            year: productionYear,
            runtimeSeconds: runTimeTicks.map { Int($0 / 10_000_000) },
            posterURL: poster
        )
    }
}
