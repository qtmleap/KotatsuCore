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
    /// Jellyfin returns a **plural** `Taglines: [String]` array — the legacy
    /// singular `Tagline` field does not exist in 10.x. Convenience accessor
    /// `tagline` returns the first element for the common "one tagline" case.
    public let taglines: [String]?
    public let genres: [String]?
    /// Server-side filesystem path — used to sniff distribution-source tags
    /// like `[AP]` (Prime Video), `[BD]` (Blu-ray) that live in the file
    /// name. Requires `Fields=Path` on the shelf request.
    public let path: String?
    public let userData: UserItemDataDTO?

    // Image tags — the key is the image kind ("Primary", "Backdrop", "Logo", "Thumb").
    public let imageTags: [String: String]?
    public let backdropImageTags: [String]?
    public let parentBackdropItemId: String?
    public let parentBackdropImageTags: [String]?
    /// Reference to the parent series's Primary (portrait poster) — set on
    /// episode payloads. Lets us render "series poster on a Continue Watching
    /// episode tile" without a second lookup.
    public let seriesPrimaryImageTag: String?
    /// Reference to the parent series's Logo — set on episode payloads. Used
    /// so an episode tile can display the series's title logo overlay.
    public let parentLogoItemId: String?
    public let parentLogoImageTag: String?
    public let seriesId: String?
    public let seriesName: String?
    public let seasonId: String?
    public let seasonName: String?
    public let indexNumber: Int?
    public let parentIndexNumber: Int?
    public let childCount: Int?
    /// Total nested item count for containers. On a `Series` this is the
    /// grand total of episodes across all seasons — `ChildCount` on the same
    /// object is only the number of *seasons*.
    public let recursiveItemCount: Int?

    public let mediaSources: [MediaSourceDTO]?

    /// Nested `{mediaSourceId: {widthAsString: {tile grid metadata}}}`. Empty
    /// dict when the server hasn't generated trickplay for this item; nil
    /// when the request didn't include `Trickplay` in Fields.
    // Wire-format representation of `Trickplay: { {msid}: { {width}: {...} } }`.
    // Kept internal because the mapping type is internal — callers should go
    // through `preferredTrickplay()` and receive the domain model.
    let trickplay: [String: [String: TrickplayInfoDTO]]?

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
        case taglines = "Taglines"
        case genres = "Genres"
        case path = "Path"
        case userData = "UserData"
        case imageTags = "ImageTags"
        case backdropImageTags = "BackdropImageTags"
        case parentBackdropItemId = "ParentBackdropItemId"
        case parentBackdropImageTags = "ParentBackdropImageTags"
        case seriesPrimaryImageTag = "SeriesPrimaryImageTag"
        case parentLogoItemId = "ParentLogoItemId"
        case parentLogoImageTag = "ParentLogoImageTag"
        case seriesId = "SeriesId"
        case seriesName = "SeriesName"
        case seasonId = "SeasonId"
        case seasonName = "SeasonName"
        case indexNumber = "IndexNumber"
        case parentIndexNumber = "ParentIndexNumber"
        case childCount = "ChildCount"
        case recursiveItemCount = "RecursiveItemCount"
        case mediaSources = "MediaSources"
        case trickplay = "Trickplay"
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
        return Self.makeImageURL(itemId: itemForImage, kind: kind, tag: tag, server: server, maxWidth: maxWidth)
    }

    /// Builds an `/Items/{id}/Images/{kind}` URL for an arbitrary
    /// (itemId, kind, tag) triplet — used for parent-series image fallbacks
    /// where the "owner" of the artwork is a different item than `self`.
    private static func makeImageURL(itemId: String, kind: String, tag: String, server: Server, maxWidth: Int?) -> URL? {
        var comps = URLComponents(url: server.url, resolvingAgainstBaseURL: false)!
        var basePath = server.url.path
        if basePath.hasSuffix("/") { basePath.removeLast() }
        let suffix = kind == "Backdrop" ? "/Items/\(itemId)/Images/Backdrop/0" : "/Items/\(itemId)/Images/\(kind)"
        comps.path = basePath + suffix
        // Force an explicit format. Without `format`, Jellyfin picks the
        // encoding based on source file / server config and can hand back
        // WebP — which ImageIO on Apple TV HD (A8) surfaces as
        // `Error -17102 decompressing image -- possibly corrupt`, leaving
        // the tile blank.
        //  * Logo needs alpha (title logos are keyed on the artwork) so
        //    it must stay lossless-with-transparency → PNG.
        //  * Everything else (Primary poster, Backdrop, Thumb) is opaque
        //    photography → JPEG, smaller payload, universally decodable.
        let format = (kind == "Logo") ? "Png" : "Jpg"
        var query: [URLQueryItem] = [
            URLQueryItem(name: "tag", value: tag),
            URLQueryItem(name: "format", value: format),
            URLQueryItem(name: "quality", value: "90")
        ]
        if let maxWidth {
            query.append(URLQueryItem(name: "maxWidth", value: "\(maxWidth)"))
        }
        comps.queryItems = query
        return comps.url
    }

    /// URL for the *parent series's* Primary (portrait poster). Populated
    /// on episode payloads via `SeriesPrimaryImageTag` + `SeriesId`; nil for
    /// items that aren't episodes or that lack the parent reference.
    public func seriesPrimaryImageURL(server: Server, maxWidth: Int? = nil) -> URL? {
        guard let sid = seriesId, let tag = seriesPrimaryImageTag, !tag.isEmpty else { return nil }
        return Self.makeImageURL(itemId: sid, kind: "Primary", tag: tag, server: server, maxWidth: maxWidth)
    }

    /// URL for the parent series's Logo — set on episodes so an episode
    /// tile can display the show's title logo overlay.
    public func parentLogoImageURL(server: Server, maxWidth: Int? = nil) -> URL? {
        guard let pid = parentLogoItemId, let tag = parentLogoImageTag, !tag.isEmpty else { return nil }
        return Self.makeImageURL(itemId: pid, kind: "Logo", tag: tag, server: server, maxWidth: maxWidth)
    }

    /// Selects the largest available trickplay variant across the primary
    /// media source and maps to the domain model. Nil when the item has no
    /// generated trickplay tiles.
    ///
    /// The 16:9 wide slot on a focused shelf paints these into a ~853×480
    /// region — the historical 320px-only default upscales roughly 2.7× and
    /// reads mushy. Servers that expose multiple widths (e.g. `320,1280`)
    /// let the shelf pick the higher-res variant; servers still on the
    /// single 320 default get the same tiles they were getting.
    public func preferredTrickplay() -> MediaTrickplayInfo? {
        guard let byMSID = trickplay, !byMSID.isEmpty else { return nil }
        // Prefer the media source whose ID matches the primary MediaSourceDTO;
        // else take whatever the server sent first.
        let primaryMSID = mediaSources?.first?.id
        let (msid, byWidth): (String, [String: TrickplayInfoDTO]) = {
            if let primaryMSID, let b = byMSID[primaryMSID] { return (primaryMSID, b) }
            return byMSID.first!
        }()
        guard !byWidth.isEmpty else { return nil }
        let widths = byWidth.keys.compactMap { Int($0) }.sorted()
        guard let w = widths.last, let dto = byWidth[String(w)] else { return nil }
        return MediaTrickplayInfo(
            mediaSourceId: msid,
            width: dto.width,
            height: dto.height,
            tileWidth: dto.tileWidth,
            tileHeight: dto.tileHeight,
            tileCount: dto.thumbnailCount,
            intervalMs: dto.interval
        )
    }

    /// Base directory for trickplay tile sprites. Append `/{tileIndex}.jpg`
    /// to fetch a specific tile. Jellyfin routes trickplay under the item ID
    /// (not the media source ID) — media source ID would only matter when a
    /// server has multiple sources for the same item; for the shelf we hand
    /// off the smallest variant and don't disambiguate.
    public func trickplayTileBaseURL(info: MediaTrickplayInfo, server: Server) -> URL? {
        var comps = URLComponents(url: server.url, resolvingAgainstBaseURL: false)!
        var basePath = server.url.path
        if basePath.hasSuffix("/") { basePath.removeLast() }
        comps.path = basePath + "/Videos/\(id)/Trickplay/\(info.width)"
        return comps.url
    }

    public func toMediaItem(server: Server) -> MediaItem {
        let kind = mediaKind ?? .movie
        let tp = preferredTrickplay()
        let tpBase = tp.flatMap { trickplayTileBaseURL(info: $0, server: server) }
        // Episodes: prefer the parent series's Primary (portrait poster) so
        // Continue Watching / Next Up rows read as "the show", not "the
        // one episode". Falls back to the item's own Primary for movies,
        // series themselves, and edge cases where the parent tag is absent.
        let poster = seriesPrimaryImageURL(server: server, maxWidth: 600)
            ?? imageURL(kind: "Primary", server: server, maxWidth: 600)
        // Same idea for the title logo — series-parent first, own next.
        let logo = imageURL(kind: "Logo", server: server, maxWidth: 800)
            ?? parentLogoImageURL(server: server, maxWidth: 800)
        // Episode still frame: for episode payloads Jellyfin stores the
        // screencap as the item's own Primary. `Thumb` is the landscape
        // still on movie/series items when the server provides one.
        let thumb: URL?
        if kind == .episode {
            thumb = imageURL(kind: "Primary", server: server, maxWidth: 800)
        } else {
            thumb = imageURL(kind: "Thumb", server: server, maxWidth: 800)
        }
        return MediaItem(
            id: id,
            kind: kind,
            title: name ?? originalTitle ?? "Untitled",
            year: productionYear,
            runtimeSeconds: runtimeSeconds,
            officialRating: officialRating,
            communityRating: communityRating,
            posterURL: poster,
            // Hero/Detail backdrops paint into a ~1920pt-wide surface but
            // Apple TV HD (A8) chokes on decoding a full 1920×1080 JPG
            // (300–500ms per image). Ask for 1280px source — the extra
            // upscale is imperceptible at the tvOS 3m viewing distance
            // and cuts both transfer time and CPU decode noticeably.
            backdropURL: imageURL(kind: "Backdrop", server: server, maxWidth: 1280),
            logoURL: logo,
            thumbURL: thumb,
            seriesId: seriesId,
            episodeNumber: kind == .episode ? indexNumber : nil,
            seasonNumber: kind == .episode ? parentIndexNumber : nil,
            overview: overview,
            genres: genres ?? [],
            distributionSource: path.flatMap { MediaSource.detect(fromPath: $0) },
            progressFraction: userData?.playedPercentageFraction,
            playbackPositionSeconds: userData?.playbackPositionSeconds,
            isFavorite: userData?.isFavorite ?? false,
            isWatched: userData?.played ?? false,
            trickplay: tp,
            trickplayTileBaseURL: tpBase
        )
    }

    public func toDetail(server: Server) -> MediaDetail {
        MediaDetail(
            item: toMediaItem(server: server),
            overview: overview,
            genres: genres ?? [],
            tagline: taglines?.first,
            mediaSources: (mediaSources ?? []).map { $0.toDomain() },
            episodeCount: recursiveItemCount
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
            playbackPositionSeconds: userData?.playbackPositionSeconds,
            distributionSource: path.flatMap { MediaSource.detect(fromPath: $0) },
            releaseVariant: {
                guard let p = path, let s = MediaSource.detect(fromPath: p) else { return nil }
                return MediaSource.detectVariant(fromPath: p, source: s)
            }(),
            primarySource: mediaSources?.first?.toDomain(),
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

    /// Convert Jellyfin's tick-based position into seconds. Nil / zero maps
    /// to nil so the caller can treat "no saved position" identically.
    public var playbackPositionSeconds: TimeInterval? {
        guard let ticks = playbackPositionTicks, ticks > 0 else { return nil }
        return TimeInterval(ticks) / 10_000_000
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
            subtitleTracks: subtitleStreams.map { $0.toSubtitle() },
            videoRange: video?.videoRange,
            videoRangeType: video?.videoRangeType,
            bitDepth: video?.bitDepth,
            colorSpace: video?.colorSpace,
            pixelFormat: video?.pixelFormat,
            frameRate: video?.averageFrameRate,
            videoLevel: video?.level,
            fileSize: size
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

    // Colour / HDR / bit-depth. `videoRangeType` is the canonical HDR marker
    // Jellyfin computes server-side ("SDR" / "HDR10" / "HLG" / "DOVI" / …).
    public let colorRange: String?
    public let colorSpace: String?
    public let colorTransfer: String?
    public let colorPrimaries: String?
    public let bitDepth: Int?
    public let pixelFormat: String?
    public let videoRange: String?
    public let videoRangeType: String?
    public let level: Double?

    // Frame rate. `averageFrameRate` is the media's declared average; the
    // realtime and reference numbers exist for progressive / interlaced
    // adjustment but the average is what UI wants.
    public let averageFrameRate: Double?

    // Audio spatial ("None" / "DolbyAtmos" / "DTSX" / …). Non-"None" is what
    // signals Atmos-style playback in the UI.
    public let audioSpatialFormat: String?

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
        case colorRange = "ColorRange"
        case colorSpace = "ColorSpace"
        case colorTransfer = "ColorTransfer"
        case colorPrimaries = "ColorPrimaries"
        case bitDepth = "BitDepth"
        case pixelFormat = "PixelFormat"
        case videoRange = "VideoRange"
        case videoRangeType = "VideoRangeType"
        case level = "Level"
        case averageFrameRate = "AverageFrameRate"
        case audioSpatialFormat = "AudioSpatialFormat"
    }

    func toAudio() -> AudioTrackDescriptor {
        AudioTrackDescriptor(
            id: index ?? 0,
            language: language,
            codec: codec,
            channels: channels,
            displayTitle: displayTitle ?? title ?? (codec ?? "Audio"),
            spatialFormat: (audioSpatialFormat?.lowercased() == "none" ? nil : audioSpatialFormat)
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
