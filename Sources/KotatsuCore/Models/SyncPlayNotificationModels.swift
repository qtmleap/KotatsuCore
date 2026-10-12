import Foundation

/// Wire names of the `SendCommand.Command` values the SDK dispatches.
public enum SyncPlayCommandKind: String, Sendable, Hashable, Codable {
    case unpause = "Unpause"
    case pause = "Pause"
    case seek = "Seek"
    case stop = "Stop"
}

/// A group command received over the socket, with wire metadata preserved.
/// `positionSeconds` is `nil` when the server sent a null `PositionTicks`;
/// the SDK never invents zero.
/// Scope is preserved as received. The SDK rejects a known foreign group,
/// but consumers still need to fence events against their current membership
/// and playback generation, including after leaving a group. UUID scope may
/// use either compact or dashed form. Freshness is a consumer decision;
/// `when` is the execution anchor and can predate a Stop's `emittedAt`.
public struct SyncPlayCommand: Sendable, Hashable {
    public let kind: SyncPlayCommandKind
    public let groupId: String?
    public let playlistItemId: String?
    public let positionSeconds: TimeInterval?
    public let when: Date?
    public let emittedAt: Date?

    public init(
        kind: SyncPlayCommandKind,
        groupId: String? = nil,
        playlistItemId: String? = nil,
        positionSeconds: TimeInterval? = nil,
        when: Date? = nil,
        emittedAt: Date? = nil
    ) {
        self.kind = kind
        self.groupId = groupId
        self.playlistItemId = playlistItemId
        self.positionSeconds = positionSeconds
        self.when = when
        self.emittedAt = emittedAt
    }
}

/// A `PlayQueue` group update. `itemId` / `playlistItemId` are `nil` when the
/// queue is valid but has no current item (empty playlist or index -1).
/// A no-current update does not imply Stop or loss of group membership.
public struct SyncPlayQueueUpdate: Sendable, Hashable {
    public let groupId: String?
    public let itemId: String?
    public let playlistItemId: String?
    public let startPositionSeconds: TimeInterval
    public let isPlaying: Bool
    public let reason: String?
    public let lastUpdate: Date?

    public init(
        groupId: String? = nil,
        itemId: String? = nil,
        playlistItemId: String? = nil,
        startPositionSeconds: TimeInterval = 0,
        isPlaying: Bool = false,
        reason: String? = nil,
        lastUpdate: Date? = nil
    ) {
        self.groupId = groupId
        self.itemId = itemId
        self.playlistItemId = playlistItemId
        self.startPositionSeconds = startPositionSeconds
        self.isPlaying = isPlaying
        self.reason = reason
        self.lastUpdate = lastUpdate
    }
}
