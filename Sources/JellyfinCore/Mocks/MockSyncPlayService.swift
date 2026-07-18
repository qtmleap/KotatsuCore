import Foundation

public actor MockSyncPlayService: SyncPlayService {
    private var _currentGroup: SyncPlayGroup?
    private let eventContinuation: AsyncStream<SyncPlayEvent>.Continuation
    public nonisolated let events: AsyncStream<SyncPlayEvent>

    public init() {
        var continuation: AsyncStream<SyncPlayEvent>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.eventContinuation = continuation
    }

    public var currentGroup: SyncPlayGroup? { _currentGroup }

    public func availableGroups() async throws -> [SyncPlayGroup] {
        try await Task.sleep(for: .milliseconds(300))
        return SampleData.syncPlayGroups
    }

    public func createGroup(name: String) async throws -> SyncPlayGroup {
        try await Task.sleep(for: .milliseconds(300))
        let group = SyncPlayGroup(
            id: "new-\(UUID().uuidString.prefix(8))",
            name: name,
            currentItemId: nil,
            participants: []
        )
        _currentGroup = group
        eventContinuation.yield(.groupChanged(group))
        return group
    }

    public func joinGroup(id: String) async throws {
        try await Task.sleep(for: .milliseconds(300))
        let group = SampleData.syncPlayGroups.first { $0.id == id } ?? SampleData.syncPlayGroups[0]
        _currentGroup = group
        eventContinuation.yield(.groupChanged(group))
    }

    public func leaveGroup() async throws {
        _currentGroup = nil
        eventContinuation.yield(.disconnected)
    }

    public func requestPlay(positionSeconds: TimeInterval) async {
        eventContinuation.yield(.play(positionSeconds: positionSeconds))
    }

    public func requestPause(positionSeconds: TimeInterval) async {
        eventContinuation.yield(.pause(positionSeconds: positionSeconds))
    }

    public func requestSeek(positionSeconds: TimeInterval) async {
        eventContinuation.yield(.seek(positionSeconds: positionSeconds))
    }
}
