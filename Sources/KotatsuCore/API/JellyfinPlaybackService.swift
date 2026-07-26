import Foundation
import Alamofire
import os

/// Real `PlaybackService`. Wraps the two-phase Jellyfin playback flow:
///
/// 1. `POST /Items/{itemId}/PlaybackInfo` with our DeviceProfile so the
///    server can choose between direct play, direct stream, and transcode.
/// 2. Build the actual stream URL from the returned `MediaSource`.
///
/// Playback reporting (`/Sessions/Playing[/Progress|/Stopped]`) then keeps
/// "continue watching" and "next episode" shelves accurate.
public struct JellyfinPlaybackService: PlaybackService {
    private let http: JellyfinHTTPClient
    private let deviceProfileBuilder: DeviceProfileBuilder
    private let logger = Logger(subsystem: "app.jellyfin.tvos", category: "playback")

    public init(http: JellyfinHTTPClient, deviceProfileBuilder: DeviceProfileBuilder = DeviceProfileBuilder()) {
        self.http = http
        self.deviceProfileBuilder = deviceProfileBuilder
    }

    private var userId: String {
        get throws {
            guard let id = http.userId, !id.isEmpty else { throw JellyfinAPIError.unauthorized }
            return id
        }
    }

    public func requestPlayback(
        itemId: String,
        audioTrackId: Int?,
        subtitleTrackId: Int?,
        startPositionSeconds: TimeInterval
    ) async throws -> PlaybackSession {
        let uid = try userId
        let profile = deviceProfileBuilder.build()

        let response = try await http.send(PlaybackInfoRequest(
            itemId: itemId,
            userId: uid,
            maxStreamingBitrate: deviceProfileBuilder.maxStreamingBitrate,
            deviceProfile: profile,
            audioStreamIndex: audioTrackId,
            subtitleStreamIndex: subtitleTrackId,
            startPositionTicks: Int64(startPositionSeconds * 10_000_000)
        ))

        guard let source = response.mediaSources?.first else {
            throw JellyfinAPIError.missingField("MediaSources")
        }
        let playSessionId = response.playSessionId ?? UUID().uuidString

        // Decide direct play vs transcode. Jellyfin's `SupportsDirectPlay`
        // is authoritative — trust it.
        let streamURL: URL
        let isTranscoded: Bool
        if source.supportsDirectPlay == true {
            streamURL = try directPlayURL(itemId: itemId, sourceId: source.id, playSessionId: playSessionId)
            isTranscoded = false
        } else if let transcodingUrl = source.transcodingUrl {
            streamURL = try composeTranscodeURL(transcodingUrl)
            isTranscoded = true
        } else if source.supportsDirectStream == true {
            streamURL = try directPlayURL(itemId: itemId, sourceId: source.id, playSessionId: playSessionId, staticStream: false)
            isTranscoded = false
        } else {
            throw JellyfinAPIError.server(status: 415, body: "No playable stream in PlaybackInfo response")
        }

        return PlaybackSession(
            id: playSessionId,
            itemId: itemId,
            mediaSourceId: source.id,
            streamURL: streamURL,
            isTranscoded: isTranscoded,
            audioTracks: source.audioStreams.map { $0.toAudio() },
            subtitleTracks: source.subtitleStreams.map { $0.toSubtitle() },
            playSessionId: playSessionId,
            startPositionSeconds: startPositionSeconds
        )
    }

    private func directPlayURL(itemId: String, sourceId: String, playSessionId: String, staticStream: Bool = true) throws -> URL {
        guard let token = http.accessToken else { throw JellyfinAPIError.unauthorized }
        var comps = URLComponents(url: http.server.url, resolvingAgainstBaseURL: false)!
        var basePath = http.server.url.path
        if basePath.hasSuffix("/") { basePath.removeLast() }
        comps.path = basePath + "/Videos/\(itemId)/stream"
        var items: [URLQueryItem] = [
            URLQueryItem(name: "MediaSourceId", value: sourceId),
            URLQueryItem(name: "PlaySessionId", value: playSessionId),
            URLQueryItem(name: "DeviceId", value: http.deviceId),
            URLQueryItem(name: "api_key", value: token),
        ]
        if staticStream {
            items.append(URLQueryItem(name: "Static", value: "true"))
        }
        comps.queryItems = items
        guard let url = comps.url else { throw JellyfinAPIError.invalidURL }
        return url
    }

    private func composeTranscodeURL(_ transcodingUrl: String) throws -> URL {
        // TranscodingUrl is server-relative (starts with "/videos/...").
        // Absolute URLs are rare but supported.
        if transcodingUrl.lowercased().hasPrefix("http") {
            guard let url = URL(string: transcodingUrl) else { throw JellyfinAPIError.invalidURL }
            return url
        }
        var basePath = http.server.url.path
        if basePath.hasSuffix("/") { basePath.removeLast() }
        var url = http.server.url
        // Preserve query string from transcodingUrl.
        let combined = basePath + (transcodingUrl.hasPrefix("/") ? transcodingUrl : "/" + transcodingUrl)
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        // Split path and query.
        if let qIndex = combined.firstIndex(of: "?") {
            comps.path = String(combined[..<qIndex])
            comps.percentEncodedQuery = String(combined[combined.index(after: qIndex)...])
        } else {
            comps.path = combined
        }
        guard let composed = comps.url else { throw JellyfinAPIError.invalidURL }
        url = composed
        return url
    }

    // MARK: - Reporting

    public func reportStarted(session: PlaybackSession) async {
        let body = PlaybackStartInfoDTO(
            itemId: session.itemId,
            mediaSourceId: session.mediaSourceId,
            playSessionId: session.playSessionId,
            audioStreamIndex: nil,
            subtitleStreamIndex: nil,
            playMethod: session.isTranscoded ? "Transcode" : "DirectPlay",
            canSeek: true,
            positionTicks: Int64(session.startPositionSeconds * 10_000_000)
        )
        do {
            _ = try await http.send(ReportPlaybackStartRequest(payload: body))
        } catch {
            logger.warning("reportStarted failed: \(String(describing: error), privacy: .public)")
        }
    }

    public func reportProgress(session: PlaybackSession, positionSeconds: TimeInterval, isPaused: Bool) async {
        let body = PlaybackProgressInfoDTO(
            itemId: session.itemId,
            mediaSourceId: session.mediaSourceId,
            playSessionId: session.playSessionId,
            positionTicks: Int64(positionSeconds * 10_000_000),
            isPaused: isPaused,
            isMuted: false,
            playMethod: session.isTranscoded ? "Transcode" : "DirectPlay",
            canSeek: true,
            eventName: "TimeUpdate"
        )
        do {
            _ = try await http.send(ReportPlaybackProgressRequest(payload: body))
        } catch {
            logger.debug("reportProgress failed: \(String(describing: error), privacy: .public)")
        }
    }

    public func reportStopped(session: PlaybackSession, positionSeconds: TimeInterval) async {
        let body = PlaybackStopInfoDTO(
            itemId: session.itemId,
            mediaSourceId: session.mediaSourceId,
            playSessionId: session.playSessionId,
            positionTicks: Int64(positionSeconds * 10_000_000),
            failed: false
        )
        do {
            _ = try await http.send(ReportPlaybackStopRequest(payload: body))
        } catch {
            logger.warning("reportStopped failed: \(String(describing: error), privacy: .public)")
        }
    }
}
