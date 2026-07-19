import Foundation
import Alamofire

// MARK: - Group management

struct SyncPlayListRequest: JFRequest {
    typealias Response = [SyncPlayGroupInfoDTO]
    let method: HTTPMethod = .get
    var path: String { "/SyncPlay/List" }
}

struct SyncPlayNewGroupRequest: JFRequest {
    typealias Response = JFEmptyResponse
    let method: HTTPMethod = .post
    var path: String { "/SyncPlay/New" }
    let groupName: String
    var query: [String: String?] { ["GroupName": groupName] }
}

struct SyncPlayJoinRequest: JFRequest {
    typealias Response = JFEmptyResponse
    let method: HTTPMethod = .post
    var path: String { "/SyncPlay/Join" }
    let groupId: String
    var query: [String: String?] { ["GroupId": groupId] }
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
    var query: [String: String?] { ["PositionTicks": "\(positionTicks)"] }
}
