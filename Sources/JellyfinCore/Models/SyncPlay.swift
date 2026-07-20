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
    /// Server issued an Unpause command. `positionSeconds` is where the
    /// server thinks playback should resume — the client should seek to it
    /// before hitting play so members converge, not drift.
    case play(positionSeconds: TimeInterval)
    case pause(positionSeconds: TimeInterval)
    case seek(positionSeconds: TimeInterval)
    /// Server issued a Stop command — the group's queue is being torn down,
    /// or the initiator hit /SyncPlay/Stop. Client should exit playback.
    case stop
    case groupChanged(SyncPlayGroup)
    case participantJoined(SyncPlayParticipant)
    case participantLeft(String)
    /// Server broadcasted a new playlist for the group. `playlistItemId` is
    /// the server-generated identifier for the current item; clients need
    /// it when calling `/SyncPlay/Ready`.
    case queueUpdated(itemId: String, playlistItemId: String, startPositionSeconds: TimeInterval, isPlaying: Bool)
    case disconnected
}
