import Foundation
import Alamofire

// MARK: - PlaybackInfo (arbitrary JSON body with DeviceProfile)

struct PlaybackInfoRequest: JFRequest, @unchecked Sendable {
    typealias Response = PlaybackInfoResponseDTO
    let method: HTTPMethod = .post
    let itemId: String
    let userId: String
    let maxStreamingBitrate: Int
    let audioStreamIndex: Int?
    let subtitleStreamIndex: Int?
    /// Pre-serialised body bytes. Computed at init time so the struct stays
    /// Sendable — `[String: Any]` values are not.
    private let bodyBytes: Data

    init(
        itemId: String,
        userId: String,
        maxStreamingBitrate: Int,
        deviceProfile: [String: Any],
        audioStreamIndex: Int?,
        subtitleStreamIndex: Int?,
        startPositionTicks: Int64 = 0
    ) {
        self.itemId = itemId
        self.userId = userId
        self.maxStreamingBitrate = maxStreamingBitrate
        self.audioStreamIndex = audioStreamIndex
        self.subtitleStreamIndex = subtitleStreamIndex

        var dict: [String: Any] = [
            "DeviceProfile": deviceProfile,
            "UserId": userId,
            "MaxStreamingBitrate": maxStreamingBitrate,
            // Non-zero StartTimeTicks tells Jellyfin to *originate the
            // transcoded segments* from that position, which keeps HLS
            // seeking accurate when we resume a partially-watched item.
            "StartTimeTicks": startPositionTicks,
            "AutoOpenLiveStream": true,
            "EnableDirectPlay": true,
            "EnableDirectStream": true,
            "EnableTranscoding": true,
            "AllowVideoStreamCopy": true,
            "AllowAudioStreamCopy": true
        ]
        if let audioStreamIndex {
            dict["AudioStreamIndex"] = audioStreamIndex
        }
        if let subtitleStreamIndex {
            dict["SubtitleStreamIndex"] = subtitleStreamIndex
        }
        self.bodyBytes = (try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    var path: String { "/Items/\(itemId)/PlaybackInfo" }
    var query: [String: String?] {
        [
            "UserId": userId,
            "AutoOpenLiveStream": "true",
            "MaxStreamingBitrate": "\(maxStreamingBitrate)"
        ]
    }

    var body: JFBody { .rawJSON(bodyBytes) }
}

// MARK: - Reporting (void)

struct ReportPlaybackStartRequest: JFRequest {
    typealias Response = JFEmptyResponse
    let method: HTTPMethod = .post
    var path: String { "/Sessions/Playing" }
    let payload: PlaybackStartInfoDTO
    var body: JFBody { .encodable(payload) }
}

struct ReportPlaybackProgressRequest: JFRequest {
    typealias Response = JFEmptyResponse
    let method: HTTPMethod = .post
    var path: String { "/Sessions/Playing/Progress" }
    let payload: PlaybackProgressInfoDTO
    var body: JFBody { .encodable(payload) }
}

struct ReportPlaybackStopRequest: JFRequest {
    typealias Response = JFEmptyResponse
    let method: HTTPMethod = .post
    var path: String { "/Sessions/Playing/Stopped" }
    let payload: PlaybackStopInfoDTO
    var body: JFBody { .encodable(payload) }
}
