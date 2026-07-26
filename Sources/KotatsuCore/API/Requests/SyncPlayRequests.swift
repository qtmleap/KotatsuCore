import Foundation
import Alamofire

// MARK: - Group management

struct SyncPlayListRequest: JFRequest {
    typealias Response = [SyncPlayGroupInfoDTO]
    let method: HTTPMethod = .get
    var path: String { "/SyncPlay/List" }
}

/// `/SyncPlay/New` returns the freshly-created `GroupInfoDto` on 200. Some
/// server builds documented a 204 branch as well, so the response is typed
/// as an Optional — the service falls back to a `/List` diff when the body
/// comes back empty.
struct SyncPlayNewGroupRequest: JFRequest {
    typealias Response = SyncPlayGroupInfoDTO?
    let method: HTTPMethod = .post
    var path: String { "/SyncPlay/New" }
    let groupName: String
    var body: JFBody { .encodable(NewGroupRequestBody(groupName: groupName)) }
}

struct SyncPlayJoinRequest: JFRequest {
    typealias Response = JFEmptyResponse
    let method: HTTPMethod = .post
    var path: String { "/SyncPlay/Join" }
    let groupId: String
    var body: JFBody { .encodable(JoinGroupRequestBody(groupId: groupId)) }
}

struct SyncPlayLeaveRequest: JFRequest {
    typealias Response = JFEmptyResponse
    let method: HTTPMethod = .post
    var path: String { "/SyncPlay/Leave" }
}

// MARK: - Playback control

struct SyncPlayUnpauseRequest: JFRequest {
    typealias Response = JFEmptyResponse
    let method: HTTPMethod = .post
    var path: String { "/SyncPlay/Unpause" }
}

struct SyncPlayPauseRequest: JFRequest {
    typealias Response = JFEmptyResponse
    let method: HTTPMethod = .post
    var path: String { "/SyncPlay/Pause" }
}

struct SyncPlaySeekRequest: JFRequest {
    typealias Response = JFEmptyResponse
    let method: HTTPMethod = .post
    var path: String { "/SyncPlay/Seek" }
    let positionTicks: Int64
    var body: JFBody { .encodable(SeekRequestBody(positionTicks: positionTicks)) }
}

struct SyncPlayStopRequest: JFRequest {
    typealias Response = JFEmptyResponse
    let method: HTTPMethod = .post
    var path: String { "/SyncPlay/Stop" }
}

// MARK: - Playlist management

struct SyncPlaySetNewQueueRequest: JFRequest {
    typealias Response = JFEmptyResponse
    let method: HTTPMethod = .post
    var path: String { "/SyncPlay/SetNewQueue" }
    let itemIds: [String]
    let startPositionTicks: Int64
    var body: JFBody {
        .encodable(PlayRequestBody(
            playingQueue: itemIds,
            playingItemPosition: 0,
            startPositionTicks: startPositionTicks
        ))
    }
}

// MARK: - Client state reporting

struct SyncPlayReadyRequest: JFRequest {
    typealias Response = JFEmptyResponse
    let method: HTTPMethod = .post
    var path: String { "/SyncPlay/Ready" }
    let positionTicks: Int64
    let isPlaying: Bool
    let playlistItemId: String?
    let when: Date
    var body: JFBody {
        .encodable(ReadyRequestBody(
            when: when,
            positionTicks: positionTicks,
            isPlaying: isPlaying,
            playlistItemId: playlistItemId
        ))
    }
}

struct SyncPlayBufferingRequest: JFRequest {
    typealias Response = JFEmptyResponse
    let method: HTTPMethod = .post
    var path: String { "/SyncPlay/Buffering" }
    let positionTicks: Int64
    let isPlaying: Bool
    let playlistItemId: String?
    let when: Date
    var body: JFBody {
        .encodable(BufferingRequestBody(
            when: when,
            positionTicks: positionTicks,
            isPlaying: isPlaying,
            playlistItemId: playlistItemId
        ))
    }
}
