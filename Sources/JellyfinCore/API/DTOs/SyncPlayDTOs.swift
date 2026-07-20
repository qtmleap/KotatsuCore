import Foundation

/// Element in the response of `GET /SyncPlay/List`.
public struct SyncPlayGroupInfoDTO: Codable, Sendable {
    public let groupId: String
    public let groupName: String?
    public let state: String?
    public let participants: [String]?
    public let lastUpdatedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case groupId = "GroupId"
        case groupName = "GroupName"
        case state = "State"
        case participants = "Participants"
        case lastUpdatedAt = "LastUpdatedAt"
    }

    public func toDomain() -> SyncPlayGroup {
        // Jellyfin sometimes returns an empty string for `GroupName` (older
        // servers, or when a group was created with `GroupName=""`). Treat
        // that as "no name provided" so the row shows a readable fallback
        // instead of a blank cell.
        let trimmed = (groupName ?? "").trimmingCharacters(in: .whitespaces)
        return SyncPlayGroup(
            id: groupId,
            name: trimmed.isEmpty ? "(名称未設定)" : trimmed,
            currentItemId: nil,
            participants: (participants ?? []).map { name in
                SyncPlayParticipant(id: name, userName: name, isOnline: true)
            }
        )
    }
}

/// Request bodies for the `/SyncPlay/*` POST endpoints. The Jellyfin API
/// spec (openapi 3.0.4) is explicit: these fields go in a JSON body, NOT
/// as query parameters. The controller rejects query-only calls with 400,
/// so `SyncPlayNewGroupRequest` etc. must all send an `application/json`
/// payload built from these structs.

struct NewGroupRequestBody: Encodable, Sendable {
    let groupName: String
    enum CodingKeys: String, CodingKey { case groupName = "GroupName" }
}

struct JoinGroupRequestBody: Encodable, Sendable {
    let groupId: String
    enum CodingKeys: String, CodingKey { case groupId = "GroupId" }
}

struct SeekRequestBody: Encodable, Sendable {
    let positionTicks: Int64
    enum CodingKeys: String, CodingKey { case positionTicks = "PositionTicks" }
}

/// Body for `POST /SyncPlay/SetNewQueue`. Replaces the group's playlist with
/// a fresh queue starting at the given position. When the first client in
/// a group calls this, the server transitions from Idle → Waiting and
/// broadcasts a `PlayQueue` update to all members.
struct PlayRequestBody: Encodable, Sendable {
    let playingQueue: [String]
    let playingItemPosition: Int
    let startPositionTicks: Int64
    enum CodingKeys: String, CodingKey {
        case playingQueue = "PlayingQueue"
        case playingItemPosition = "PlayingItemPosition"
        case startPositionTicks = "StartPositionTicks"
    }
}

/// Body for `POST /SyncPlay/Ready` — sent when the local player finishes
/// buffering the current item and is ready to start playback (or resume
/// from a pause). The server waits for every member to report Ready before
/// issuing an Unpause command, which is how the "everyone starts at the
/// same wall-clock time" invariant is maintained.
struct ReadyRequestBody: Encodable, Sendable {
    let when: Date
    let positionTicks: Int64
    let isPlaying: Bool
    let playlistItemId: String?
    enum CodingKeys: String, CodingKey {
        case when = "When"
        case positionTicks = "PositionTicks"
        case isPlaying = "IsPlaying"
        case playlistItemId = "PlaylistItemId"
    }
}

/// Same shape as `ReadyRequestBody` but sent when the client falls into a
/// stall / rebuffer. Server transitions the group to Waiting and pauses
/// everyone else until we send Ready again.
struct BufferingRequestBody: Encodable, Sendable {
    let when: Date
    let positionTicks: Int64
    let isPlaying: Bool
    let playlistItemId: String?
    enum CodingKeys: String, CodingKey {
        case when = "When"
        case positionTicks = "PositionTicks"
        case isPlaying = "IsPlaying"
        case playlistItemId = "PlaylistItemId"
    }
}

// MARK: - WebSocket payloads

/// Wire shape of the `SendCommand` object that ships inside a
/// `SyncPlayCommand` WebSocket message. `Command` is one of
/// `Unpause | Pause | Stop | Seek` per the spec; `PositionTicks` is
/// nullable (Pause without a position is legal, for example).
public struct SendCommandDTO: Codable, Sendable {
    public let groupId: String?
    public let playlistItemId: String?
    public let when: Date?
    public let positionTicks: Int64?
    public let command: String?
    public let emittedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case groupId = "GroupId"
        case playlistItemId = "PlaylistItemId"
        case when = "When"
        case positionTicks = "PositionTicks"
        case command = "Command"
        case emittedAt = "EmittedAt"
    }
}

/// Element inside a `PlayQueueUpdate.Playlist` array. `ItemId` is the
/// media library item; `PlaylistItemId` is the server-generated identifier
/// scoped to the current queue — required when calling Ready.
public struct SyncPlayQueueItemDTO: Codable, Sendable {
    public let itemId: String
    public let playlistItemId: String

    private enum CodingKeys: String, CodingKey {
        case itemId = "ItemId"
        case playlistItemId = "PlaylistItemId"
    }
}

/// Wire shape of `PlayQueueUpdate.Data` — the payload of a
/// `SyncPlayGroupUpdate` with `Type = PlayQueue`. Tells every member what
/// to load, where in the queue we are, and what the last-known playback
/// position was.
public struct PlayQueueUpdateDTO: Codable, Sendable {
    public let reason: String?
    public let playlist: [SyncPlayQueueItemDTO]?
    public let playingItemIndex: Int?
    public let startPositionTicks: Int64?
    public let isPlaying: Bool?

    private enum CodingKeys: String, CodingKey {
        case reason = "Reason"
        case playlist = "Playlist"
        case playingItemIndex = "PlayingItemIndex"
        case startPositionTicks = "StartPositionTicks"
        case isPlaying = "IsPlaying"
    }
}

/// Typed WebSocket envelope for `SyncPlayCommand` messages. Used to decode
/// the top-level frame with `Data` bound to `SendCommandDTO`.
public struct SyncPlayCommandMessageDTO: Decodable, Sendable {
    public let messageType: String
    public let data: SendCommandDTO?

    private enum CodingKeys: String, CodingKey {
        case messageType = "MessageType"
        case data = "Data"
    }
}

/// Envelope for a WebSocket message from the Jellyfin server. Payload shape
/// depends on `MessageType`.
public struct WebSocketMessageDTO: Codable, Sendable {
    public let messageType: String
    public let messageId: String?

    private enum CodingKeys: String, CodingKey {
        case messageType = "MessageType"
        case messageId = "MessageId"
    }
}

/// GroupUpdate payload. `Type` selects a specific update kind
/// ("StateUpdate", "GroupJoined", "UserJoined", "UserLeft", ...).
public struct GroupUpdateDTO: Codable, Sendable {
    public let groupId: String?
    public let type: String?

    private enum CodingKeys: String, CodingKey {
        case groupId = "GroupId"
        case type = "Type"
    }
}
