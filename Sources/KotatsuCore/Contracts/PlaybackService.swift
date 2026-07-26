import Foundation

public protocol PlaybackService: Sendable {
    /// `startPositionSeconds` seeds the returned session so the player can
    /// seek there on start. Pass 0 to start from the beginning; pass the
    /// item's saved position to resume "続きから再生".
    func requestPlayback(
        itemId: String,
        audioTrackId: Int?,
        subtitleTrackId: Int?,
        startPositionSeconds: TimeInterval
    ) async throws -> PlaybackSession
    func reportStarted(session: PlaybackSession) async
    func reportProgress(session: PlaybackSession, positionSeconds: TimeInterval, isPaused: Bool) async
    func reportStopped(session: PlaybackSession, positionSeconds: TimeInterval) async
}

public extension PlaybackService {
    /// Convenience overload for callers that always start from the beginning
    /// (matches the pre-resume signature).
    func requestPlayback(itemId: String, audioTrackId: Int?, subtitleTrackId: Int?) async throws -> PlaybackSession {
        try await requestPlayback(itemId: itemId, audioTrackId: audioTrackId, subtitleTrackId: subtitleTrackId, startPositionSeconds: 0)
    }
}
