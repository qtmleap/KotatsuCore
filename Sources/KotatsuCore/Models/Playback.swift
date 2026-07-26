import Foundation

public struct PlaybackSession: Sendable, Codable, Identifiable, Hashable {
    public let id: String
    public let itemId: String
    public let mediaSourceId: String
    public let streamURL: URL
    public let isTranscoded: Bool
    public let audioTracks: [AudioTrackDescriptor]
    public let subtitleTracks: [SubtitleTrackDescriptor]
    public let playSessionId: String
    public let startPositionSeconds: TimeInterval

    public init(
        id: String,
        itemId: String,
        mediaSourceId: String,
        streamURL: URL,
        isTranscoded: Bool,
        audioTracks: [AudioTrackDescriptor] = [],
        subtitleTracks: [SubtitleTrackDescriptor] = [],
        playSessionId: String,
        startPositionSeconds: TimeInterval = 0
    ) {
        self.id = id
        self.itemId = itemId
        self.mediaSourceId = mediaSourceId
        self.streamURL = streamURL
        self.isTranscoded = isTranscoded
        self.audioTracks = audioTracks
        self.subtitleTracks = subtitleTracks
        self.playSessionId = playSessionId
        self.startPositionSeconds = startPositionSeconds
    }
}

public enum PlaybackProgressEvent: Sendable, Codable, Hashable {
    case started
    case progress(positionSeconds: TimeInterval, isPaused: Bool)
    case stopped(positionSeconds: TimeInterval)
}
