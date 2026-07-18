import Foundation

public protocol SyncPlayService: Sendable {
    var currentGroup: SyncPlayGroup? { get async }
    var events: AsyncStream<SyncPlayEvent> { get }

    func availableGroups() async throws -> [SyncPlayGroup]
    func createGroup(name: String) async throws -> SyncPlayGroup
    func joinGroup(id: String) async throws
    func leaveGroup() async throws

    func requestPlay(positionSeconds: TimeInterval) async
    func requestPause(positionSeconds: TimeInterval) async
    func requestSeek(positionSeconds: TimeInterval) async
}
