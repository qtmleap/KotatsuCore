import Foundation

public struct MockPlaybackService: PlaybackService {
    public init() {}

    public func requestPlayback(itemId: String, audioTrackId: Int?, subtitleTrackId: Int?) async throws -> PlaybackSession {
        try await Task.sleep(for: .milliseconds(600))
        return PlaybackSession(
            id: UUID().uuidString,
            itemId: itemId,
            mediaSourceId: "src-\(itemId)",
            streamURL: URL(string: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8")!,
            isTranscoded: true,
            audioTracks: [
                AudioTrackDescriptor(id: 1, language: "jpn", codec: "aac", channels: 2, displayTitle: "日本語 · AAC 2.0")
            ],
            subtitleTracks: [
                SubtitleTrackDescriptor(id: 1, language: "jpn", codec: "srt", displayTitle: "日本語")
            ],
            playSessionId: UUID().uuidString,
            startPositionSeconds: 0
        )
    }

    public func reportStarted(session: PlaybackSession) async {}
    public func reportProgress(session: PlaybackSession, positionSeconds: TimeInterval, isPaused: Bool) async {}
    public func reportStopped(session: PlaybackSession, positionSeconds: TimeInterval) async {}
}
