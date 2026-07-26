import Foundation

public struct MediaDetail: Sendable, Codable, Identifiable, Hashable {
    public let item: MediaItem
    public let overview: String?
    public let genres: [String]
    public let tagline: String?
    public let mediaSources: [MediaSourceInfo]
    /// Grand total of nested items — for a `Series` this is the total number
    /// of episodes across every season. Nil for movies / items where the
    /// server didn't return the field.
    public let episodeCount: Int?

    public var id: String { item.id }

    public init(
        item: MediaItem,
        overview: String? = nil,
        genres: [String] = [],
        tagline: String? = nil,
        mediaSources: [MediaSourceInfo] = [],
        episodeCount: Int? = nil
    ) {
        self.item = item
        self.overview = overview
        self.genres = genres
        self.tagline = tagline
        self.mediaSources = mediaSources
        self.episodeCount = episodeCount
    }
}

public struct MediaSourceInfo: Sendable, Codable, Identifiable, Hashable {
    public let id: String
    public let container: String?
    public let videoCodec: String?
    public let videoProfile: String?
    public let width: Int?
    public let height: Int?
    public let videoBitrate: Int?
    public let audioTracks: [AudioTrackDescriptor]
    public let subtitleTracks: [SubtitleTrackDescriptor]

    // HDR / bit depth / colour lifted from the primary video stream. Kept on
    // MediaSourceInfo so UI doesn't have to reach into raw streams to draw
    // an HDR badge or a "1080p HEVC 10bit 24fps" summary.
    public let videoRange: String?
    public let videoRangeType: String?
    public let bitDepth: Int?
    public let colorSpace: String?
    public let pixelFormat: String?
    public let frameRate: Double?
    public let videoLevel: Double?
    /// Total file size in bytes for the on-disk media. Used for the compact
    /// "1.4 GB" / "800 MB" badge on episode rows so viewers can weigh
    /// bandwidth cost between multi-release editions.
    public let fileSize: Int64?

    public init(
        id: String,
        container: String? = nil,
        videoCodec: String? = nil,
        videoProfile: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        videoBitrate: Int? = nil,
        audioTracks: [AudioTrackDescriptor] = [],
        subtitleTracks: [SubtitleTrackDescriptor] = [],
        videoRange: String? = nil,
        videoRangeType: String? = nil,
        bitDepth: Int? = nil,
        colorSpace: String? = nil,
        pixelFormat: String? = nil,
        frameRate: Double? = nil,
        videoLevel: Double? = nil,
        fileSize: Int64? = nil
    ) {
        self.id = id
        self.container = container
        self.videoCodec = videoCodec
        self.videoProfile = videoProfile
        self.width = width
        self.height = height
        self.videoBitrate = videoBitrate
        self.audioTracks = audioTracks
        self.subtitleTracks = subtitleTracks
        self.videoRange = videoRange
        self.videoRangeType = videoRangeType
        self.bitDepth = bitDepth
        self.colorSpace = colorSpace
        self.pixelFormat = pixelFormat
        self.frameRate = frameRate
        self.videoLevel = videoLevel
        self.fileSize = fileSize
    }

    /// True when the source needs HDR-capable playback (HDR10 / HLG / Dolby
    /// Vision / etc.). `SDR` and unknown fall to false so the UI only
    /// upgrades the badge when the server says so explicitly.
    public var isHDR: Bool {
        guard let vrt = videoRangeType?.uppercased() else { return false }
        return vrt != "SDR"
    }
}

public struct AudioTrackDescriptor: Sendable, Codable, Identifiable, Hashable {
    public let id: Int
    public let language: String?
    public let codec: String?
    public let channels: Int?
    public let displayTitle: String
    /// Spatial audio marker from Jellyfin. `nil` when the stream is plain
    /// stereo/5.1/etc.; non-nil values are `"DolbyAtmos"`, `"DTSX"`, etc.
    public let spatialFormat: String?

    public init(
        id: Int,
        language: String? = nil,
        codec: String? = nil,
        channels: Int? = nil,
        displayTitle: String,
        spatialFormat: String? = nil
    ) {
        self.id = id
        self.language = language
        self.codec = codec
        self.channels = channels
        self.displayTitle = displayTitle
        self.spatialFormat = spatialFormat
    }
}

public struct SubtitleTrackDescriptor: Sendable, Codable, Identifiable, Hashable {
    public let id: Int
    public let language: String?
    public let codec: String?
    public let isForced: Bool
    public let isImageBased: Bool
    public let displayTitle: String

    public init(id: Int, language: String? = nil, codec: String? = nil, isForced: Bool = false, isImageBased: Bool = false, displayTitle: String) {
        self.id = id
        self.language = language
        self.codec = codec
        self.isForced = isForced
        self.isImageBased = isImageBased
        self.displayTitle = displayTitle
    }
}
