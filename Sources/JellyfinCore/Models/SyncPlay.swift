import Foundation

public struct SyncPlayGroup: Sendable, Codable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let currentItemId: String?
    public let participants: [SyncPlayParticipant]

    public init(id: String, name: String, currentItemId: String? = nil, participants: [SyncPlayParticipant] = []) {
        self.id = id
        self.name = name
        self.currentItemId = currentItemId
        self.participants = participants
    }
}

public struct SyncPlayParticipant: Sendable, Codable, Identifiable, Hashable {
    public let id: String
    public let userName: String
    public let isOnline: Bool

    public init(id: String, userName: String, isOnline: Bool) {
        self.id = id
        self.userName = userName
        self.isOnline = isOnline
    }
}

public enum SyncPlayEvent: Sendable, Hashable {
    case play(positionSeconds: TimeInterval)
    case pause(positionSeconds: TimeInterval)
    case seek(positionSeconds: TimeInterval)
    case groupChanged(SyncPlayGroup)
    case participantJoined(SyncPlayParticipant)
    case participantLeft(String)
    case disconnected
}
