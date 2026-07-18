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
        SyncPlayGroup(
            id: groupId,
            name: groupName ?? "SyncPlay",
            currentItemId: nil,
            participants: (participants ?? []).map { name in
                SyncPlayParticipant(id: name, userName: name, isOnline: true)
            }
        )
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
