import Foundation

public protocol SyncPlayService: Sendable {
    var currentGroup: SyncPlayGroup? { get async }
    var events: AsyncStream<SyncPlayEvent> { get }

    func availableGroups() async throws -> [SyncPlayGroup]
    func createGroup(name: String) async throws -> SyncPlayGroup
    func joinGroup(id: String) async throws
    func leaveGroup() async throws

    // Local user actions — propagated to all group members via the server.
    func requestPlay(positionSeconds: TimeInterval) async
    func requestPause(positionSeconds: TimeInterval) async
    func requestSeek(positionSeconds: TimeInterval) async

    /// Replace the group's playlist with a single item and start playback
    /// there. All members receive a `PlayQueue` update on WebSocket. Only
    /// meaningful when we're actually in a group.
    func setNewQueue(itemIds: [String], startPositionSeconds: TimeInterval) async throws

    /// Report that the local player is loaded and ready to start (or
    /// resume from a pause). The server holds the group in Waiting until
    /// every member reports Ready, then broadcasts an Unpause command.
    func notifyReady(positionSeconds: TimeInterval, isPlaying: Bool, playlistItemId: String?) async

    /// Report that the local player has stalled and needs to rebuffer.
    /// Server transitions the group to Waiting so no one drifts ahead.
    func notifyBuffering(positionSeconds: TimeInterval, isPlaying: Bool, playlistItemId: String?) async

    /// Tell the group to stop playback entirely.
    func stopGroup() async
}
