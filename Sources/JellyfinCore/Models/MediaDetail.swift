import Foundation

public struct MediaDetail: Sendable, Codable, Identifiable, Hashable {
    public let item: MediaItem
    public let overview: String?
    public let genres: [String]
    public let tagline: String?
    public let mediaSources: [MediaSourceInfo]

    public var id: String { item.id }

    public init(
        item: MediaItem,
        overview: String? = nil,
        genres: [String] = [],
        tagline: String? = nil,
        mediaSources: [MediaSourceInfo] = []
    ) {
        self.item = item
        self.overview = overview
        self.genres = genres
        self.tagline = tagline
        self.mediaSources = mediaSources
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

    public init(
        id: String,
        container: String? = nil,
        videoCodec: String? = nil,
        videoProfile: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        videoBitrate: Int? = nil,
        audioTracks: [AudioTrackDescriptor] = [],
        subtitleTracks: [SubtitleTrackDescriptor] = []
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
    }
}

public struct AudioTrackDescriptor: Sendable, Codable, Identifiable, Hashable {
    public let id: Int
    public let language: String?
    public let codec: String?
    public let channels: Int?
    public let displayTitle: String

    public init(id: Int, language: String? = nil, codec: String? = nil, channels: Int? = nil, displayTitle: String) {
        self.id = id
        self.language = language
        self.codec = codec
        self.channels = channels
        self.displayTitle = displayTitle
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
