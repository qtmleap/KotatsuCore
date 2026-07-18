import Foundation

public protocol PlaybackService: Sendable {
    func requestPlayback(itemId: String, audioTrackId: Int?, subtitleTrackId: Int?) async throws -> PlaybackSession
    func reportStarted(session: PlaybackSession) async
    func reportProgress(session: PlaybackSession, positionSeconds: TimeInterval, isPaused: Bool) async
    func reportStopped(session: PlaybackSession, positionSeconds: TimeInterval) async
}
