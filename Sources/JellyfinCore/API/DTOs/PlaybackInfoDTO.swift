import Foundation

/// Response for `POST /Items/{itemId}/PlaybackInfo`.
public struct PlaybackInfoResponseDTO: Codable, Sendable {
    public let mediaSources: [MediaSourceDTO]?
    public let playSessionId: String?
    public let errorCode: String?

    private enum CodingKeys: String, CodingKey {
        case mediaSources = "MediaSources"
        case playSessionId = "PlaySessionId"
        case errorCode = "ErrorCode"
    }
}

/// Body for `POST /Sessions/Playing` — playback started.
public struct PlaybackStartInfoDTO: Codable, Sendable {
    public let itemId: String
    public let mediaSourceId: String
    public let playSessionId: String
    public let audioStreamIndex: Int?
    public let subtitleStreamIndex: Int?
    public let playMethod: String
    public let canSeek: Bool
    public let positionTicks: Int64?

    private enum CodingKeys: String, CodingKey {
        case itemId = "ItemId"
        case mediaSourceId = "MediaSourceId"
        case playSessionId = "PlaySessionId"
        case audioStreamIndex = "AudioStreamIndex"
        case subtitleStreamIndex = "SubtitleStreamIndex"
        case playMethod = "PlayMethod"
        case canSeek = "CanSeek"
        case positionTicks = "PositionTicks"
    }
}

/// Body for `POST /Sessions/Playing/Progress`.
public struct PlaybackProgressInfoDTO: Codable, Sendable {
    public let itemId: String
    public let mediaSourceId: String
    public let playSessionId: String
    public let positionTicks: Int64
    public let isPaused: Bool
    public let isMuted: Bool
    public let playMethod: String
    public let canSeek: Bool
    public let eventName: String

    private enum CodingKeys: String, CodingKey {
        case itemId = "ItemId"
        case mediaSourceId = "MediaSourceId"
        case playSessionId = "PlaySessionId"
        case positionTicks = "PositionTicks"
        case isPaused = "IsPaused"
        case isMuted = "IsMuted"
        case playMethod = "PlayMethod"
        case canSeek = "CanSeek"
        case eventName = "EventName"
    }
}

/// Body for `POST /Sessions/Playing/Stopped`.
public struct PlaybackStopInfoDTO: Codable, Sendable {
    public let itemId: String
    public let mediaSourceId: String
    public let playSessionId: String
    public let positionTicks: Int64
    public let failed: Bool

    private enum CodingKeys: String, CodingKey {
        case itemId = "ItemId"
        case mediaSourceId = "MediaSourceId"
        case playSessionId = "PlaySessionId"
        case positionTicks = "PositionTicks"
        case failed = "Failed"
    }
}
