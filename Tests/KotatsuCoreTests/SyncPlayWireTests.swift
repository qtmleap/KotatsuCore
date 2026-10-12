import XCTest

@testable import KotatsuCore

/// End-to-end receive/decode/dispatch tests for `JellyfinSyncPlayService`.
///
/// `handle(message:)` is private, so every frame travels the real path:
/// loopback `SyncPlayWireServer` (RFC 6455 upgrade, unmasked text/binary
/// frames) -> `URLSessionWebSocketTask.receive()` -> `listenLoop` ->
/// `handle(message:)` -> `AsyncStream<SyncPlayEvent>`.
///
/// Negative assertions never sleep. The server writes frames in order on one
/// TCP stream and the client handles them serially, so a positive *barrier*
/// frame sent last proves every earlier frame was already processed:
///  * `markerEvents` uses a final `GroupJoined` (-> `.groupChanged`) marker and
///    returns everything emitted before it;
///  * `barrierThenCurrentGroup` uses a final matching `Stop` (non-mutating) so
///    `currentGroup` can be read after the barrier without the marker
///    overwriting it.
///
final class SyncPlayWireTests: XCTestCase {
    private static let group = SyncPlayGroup(
        id: "group-1", name: "Fake", currentItemId: nil,
        participants: [SyncPlayParticipant(id: "alice", userName: "alice", isOnline: true)])

    private final class EventLog: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [SyncPlayEvent] = []
        func append(_ e: SyncPlayEvent) {
            lock.lock()
            items.append(e)
            lock.unlock()
        }
        var all: [SyncPlayEvent] {
            lock.lock()
            defer { lock.unlock() }
            return items
        }
    }

    private struct Fixture {
        let server: SyncPlayWireServer
        let service: JellyfinSyncPlayService
        let log: EventLog
        let cleanup: () -> Void

        /// Bounded positive wait for the first event at/after `from` matching `predicate`.
        func waitForEvent(from: Int = 0, _ predicate: (SyncPlayEvent) -> Bool) async throws -> Int {
            for _ in 0..<1000 {
                let events = log.all
                if let i = events.indices.dropFirst(from).first(where: { predicate(events[$0]) }) {
                    return i
                }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            throw SyncPlayWireServer.WireError.timeout("expected event")
        }

        /// Sends `frames`, then a final `GroupJoined(group-marker)` and returns all
        /// events emitted between the initial createGroup event and the marker.
        func markerEvents(_ frames: [String]) async throws -> [SyncPlayEvent] {
            for f in frames { try await server.sendText(f) }
            try await server.sendText(SyncPlayWireTests.marker())
            let i = try await waitForEvent(from: 1) {
                if case .groupChanged(let g) = $0 { return g.id == "group-marker" }
                return false
            }
            return Array(log.all[1..<i])
        }

        /// Sends `frames`, then a matching `Stop` (group-1) barrier; returns events
        /// before the barrier and `currentGroup` as observed right after it.
        func barrierThenCurrentGroup(
            _ frames: [String], barrierGroupId: String = "group-1"
        ) async throws -> (
            [SyncPlayEvent], SyncPlayGroup?
        ) {
            for f in frames { try await server.sendText(f) }
            try await server.sendText(
                SyncPlayWireFrames.command(
                    "Stop", groupId: barrierGroupId, playlistItemId: "barrier"))
            let i = try await waitForEvent(from: 1, SyncPlayWireTests.isBarrierStop)
            let current = await service.currentGroup
            return (Array(log.all[1..<i]), current)
        }
    }

    static let wireDate: Date = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: SyncPlayWireFrames.wireDate)!
    }()

    /// Expected typed command for `SyncPlayWireFrames.command` defaults.
    private static func cmd(
        _ kind: SyncPlayCommandKind, position: TimeInterval?, groupId: String = "group-1",
        playlistItemId: String = "pl-1"
    ) -> SyncPlayEvent {
        .command(
            SyncPlayCommand(
                kind: kind, groupId: groupId, playlistItemId: playlistItemId,
                positionSeconds: position,
                when: wireDate, emittedAt: wireDate))
    }

    private static func isBarrierStop(_ e: SyncPlayEvent) -> Bool {
        if case .command(let c) = e { return c.kind == .stop && c.playlistItemId == "barrier" }
        return false
    }

    private static func marker() -> String {
        SyncPlayWireFrames.groupUpdate(
            type: "GroupJoined", groupId: "group-marker",
            data: SyncPlayWireFrames.groupInfo(id: "group-marker", name: "Marker"))
    }

    /// Boots server + service and joins group-1 via the real `createGroup` REST
    /// path, then waits (bounded) for the WebSocket upgrade. `log.all[0]` is
    /// always `.groupChanged(group-1)`.
    /// `holdUpgrade` (test-controlled) withholds the WebSocket 101 and skips the
    /// upgrade wait, leaving the socket allocated but still connecting.
    /// `holdPauseResponse` withholds the REST 204 of `POST /SyncPlay/Pause`.
    private func makeFixture(
        holdUpgrade: Bool = false, holdPauseResponse: Bool = false
    ) async throws -> Fixture {
        let server = try SyncPlayWireServer(
            holdUpgrade: holdUpgrade, holdPauseResponse: holdPauseResponse)
        let port = try await server.start()
        let session = URLSession(configuration: .ephemeral)
        let base = Server(id: "s", name: "s", url: URL(string: "http://127.0.0.1:\(port)")!)
        let http = JellyfinHTTPClient(
            server: base, accessToken: "synthetic-token", userId: "user", deviceId: "device")
        let service = JellyfinSyncPlayService(http: http, urlSession: session)
        let log = EventLog()
        let consumer = Task {
            for await event in service.events { log.append(event) }
        }
        let fixture = Fixture(
            server: server, service: service, log: log,
            cleanup: {
                consumer.cancel()
                session.invalidateAndCancel()
                server.stop()
            })
        do {
            let created = try await service.createGroup(name: "Fake")
            XCTAssertEqual(created, Self.group)
            if !holdUpgrade { try await server.waitForSocket() }
            _ = try await fixture.waitForEvent { $0 == .groupChanged(Self.group) }
        } catch {
            fixture.cleanup()
            throw error
        }
        return fixture
    }

    // MARK: - Commands (known outputs)

    /// Catches: a command name mapped to the wrong event, ticks->seconds
    /// conversion errors, null PositionTicks not defaulting to 0, and text vs
    /// binary frames being decoded differently.
    func testCommandsDispatchEventsForTextAndBinaryFrames() async throws {
        let f = try await makeFixture()
        defer { f.cleanup() }

        let cases: [(String, Int64?, SyncPlayEvent)] = [
            ("Unpause", 125_000_000, Self.cmd(.unpause, position: 12.5)),
            ("Pause", 30_000_000, Self.cmd(.pause, position: 3)),
            ("Pause", nil, Self.cmd(.pause, position: nil)),
            ("Seek", 600_000_000, Self.cmd(.seek, position: 60)),
            ("Stop", 0, Self.cmd(.stop, position: 0)),
        ]
        var expected: [SyncPlayEvent] = []
        for binary in [false, true] {
            for (name, ticks, event) in cases {
                let frame = SyncPlayWireFrames.command(name, ticks: ticks)
                if binary {
                    try await f.server.sendBinary(Data(frame.utf8))
                } else {
                    try await f.server.sendText(frame)
                }
                expected.append(event)
            }
        }
        let events = try await f.markerEvents([])
        XCTAssertEqual(events, expected)
    }

    /// Catches: metadata-rich frames (EmittedAt/When/PlaylistItemId) breaking
    /// command decoding, and a Stop whose PlaylistItemId differs from the
    /// current item being dropped. Stop is group-wide, so GroupId alone scopes it.
    func testMatchingGroupStopWithDifferentPlaylistItemIdStillStops() async throws {
        let f = try await makeFixture()
        defer { f.cleanup() }
        let events = try await f.markerEvents([
            SyncPlayWireFrames.command(
                "Stop", groupId: "group-1", playlistItemId: "some-other-item")
        ])
        XCTAssertEqual(events, [Self.cmd(.stop, position: 0, playlistItemId: "some-other-item")])
    }

    // MARK: - Group updates (known outputs)

    /// Catches: GroupJoined inner GroupInfoDto not decoded/replacing membership.
    func testGroupJoinedReplacesCurrentGroup() async throws {
        let f = try await makeFixture()
        defer { f.cleanup() }
        let joined = SyncPlayWireFrames.groupUpdate(
            type: "GroupJoined", groupId: "group-2",
            data: SyncPlayWireFrames.groupInfo(id: "group-2", name: "Other", participants: ["bob"]))
        try await f.server.sendText(joined)
        let expected = SyncPlayGroup(
            id: "group-2", name: "Other",
            participants: [SyncPlayParticipant(id: "bob", userName: "bob", isOnline: true)])
        _ = try await f.waitForEvent(from: 1) { $0 == .groupChanged(expected) }
        let current = await f.service.currentGroup
        XCTAssertEqual(current, expected)
    }

    /// Catches: UserJoined/UserLeft payload (a plain username string) mishandled.
    func testUserJoinedAndLeftDispatchParticipantEvents() async throws {
        let f = try await makeFixture()
        defer { f.cleanup() }
        let events = try await f.markerEvents([
            SyncPlayWireFrames.groupUpdate(type: "UserJoined", data: "bob"),
            SyncPlayWireFrames.groupUpdate(type: "UserLeft", data: "bob"),
        ])
        XCTAssertEqual(
            events,
            [
                .participantJoined(SyncPlayParticipant(id: "bob", userName: "bob", isOnline: true)),
                .participantLeft("bob"),
            ])
    }

    /// Catches: any Reason of the full PlayQueue wire inventory failing to
    /// decode (full shape incl. LastUpdate/RepeatMode/ShuffleMode) or the
    /// current item/position/IsPlaying being mis-extracted.
    func testEveryPlayQueueReasonDispatchesQueueUpdated() async throws {
        let f = try await makeFixture()
        defer { f.cleanup() }
        let reasons = [
            "NewPlaylist", "SetCurrentItem", "RemoveItems", "MoveItem", "Queue", "QueueNext",
            "NextItem", "PreviousItem", "RepeatMode", "ShuffleMode",
        ]
        let events = try await f.markerEvents(
            reasons.map { SyncPlayWireFrames.playQueue(reason: $0) })
        let expected = reasons.map {
            SyncPlayEvent.queueChanged(
                SyncPlayQueueUpdate(
                    groupId: "group-1", itemId: "item-b", playlistItemId: "pl-b",
                    startPositionSeconds: 5,
                    isPlaying: true, reason: $0, lastUpdate: Self.wireDate))
        }
        XCTAssertEqual(events, expected)
    }

    /// Catches: membership-ending updates (matching group) not clearing the
    /// group or not emitting exactly one `.disconnected`.
    func testMatchingGroupLeftAndRejectionsClearMembership() async throws {
        for type in ["GroupLeft", "NotInGroup", "GroupDoesNotExist"] {
            let f = try await makeFixture()
            defer { f.cleanup() }
            try await f.server.sendText(
                SyncPlayWireFrames.groupUpdate(type: type, groupId: "group-1", data: "group-1"))
            _ = try await f.waitForEvent(from: 1) { $0 == .disconnected }
            let current = await f.service.currentGroup
            XCTAssertNil(current, type)
        }
    }

    /// Documents CURRENT intentional behaviour: `StateUpdate` and
    /// `LibraryAccessDenied` have no `SyncPlayEvent` yet, so they emit nothing
    /// and keep membership. Revisit when an event API is added for them.
    func testStateUpdateAndLibraryAccessDeniedAreCurrentlyIgnored() async throws {
        let f = try await makeFixture()
        defer { f.cleanup() }
        let (events, current) = try await f.barrierThenCurrentGroup([
            SyncPlayWireFrames.groupUpdate(
                type: "StateUpdate",
                data: ["State": "Waiting", "Reason": "Buffer", "PositionTicks": 0] as [String: Any]),
            SyncPlayWireFrames.groupUpdate(type: "LibraryAccessDenied", data: ""),
        ])
        XCTAssertEqual(events, [])
        XCTAssertEqual(current, Self.group)
    }

    // MARK: - RED: GroupId scoping

    /// RED. Catches: commands for ANOTHER group (group-2) acting on us while we
    /// are in group-1: any play/pause/seek/stop emitted would drive local playback.
    func testForeignGroupCommandsProduceNoEvents() async throws {
        let f = try await makeFixture()
        defer { f.cleanup() }
        let frames = ["Unpause", "Pause", "Seek", "Stop"].map {
            SyncPlayWireFrames.command($0, groupId: "group-2", ticks: 100_000_000)
        }
        let events = try await f.markerEvents(frames)
        XCTAssertEqual(events, [], "foreign-group commands must be dropped")
    }

    /// RED. Catches: a PlayQueue for another group loading its item/position
    /// into our player.
    func testForeignGroupPlayQueueProducesNoQueueEvent() async throws {
        let f = try await makeFixture()
        defer { f.cleanup() }
        let (events, current) = try await f.barrierThenCurrentGroup([
            SyncPlayWireFrames.playQueue(groupId: "group-2")
        ])
        XCTAssertEqual(events, [], "foreign PlayQueue must not emit queueUpdated")
        XCTAssertEqual(current, Self.group)
    }

    /// RED. Catches: another group's GroupLeft clearing our membership and
    /// emitting `.disconnected` (consumers stop outbound commands on it).
    func testForeignGroupLeftDoesNotClearMembership() async throws {
        let f = try await makeFixture()
        defer { f.cleanup() }
        let (events, current) = try await f.barrierThenCurrentGroup([
            SyncPlayWireFrames.groupUpdate(type: "GroupLeft", groupId: "group-2", data: "group-2")
        ])
        XCTAssertFalse(events.contains(.disconnected), "foreign GroupLeft emitted: \(events)")
        XCTAssertEqual(current, Self.group, "foreign GroupLeft must not clear membership")
    }

    // MARK: - Unknown / malformed

    /// Catches: junk (unknown types, bad JSON, bad UTF-8, truncated payloads,
    /// out-of-range queue index, unknown command/update names, bad dates)
    /// crashing the listener, emitting events, or touching membership.
    func testUnknownAndMalformedFramesLeaveMembershipIntact() async throws {
        let f = try await makeFixture()
        defer { f.cleanup() }

        let texts = [
            SyncPlayWireFrames.other(messageType: "ForceKeepAlive", data: 30),
            SyncPlayWireFrames.other(messageType: "KeepAlive"),
            SyncPlayWireFrames.other(messageType: "Sessions"),
            SyncPlayWireFrames.other(messageType: "SomethingNew"),
            "not json at all",
            "{\"Data\":{}}",
            "{\"MessageType\":\"SyncPlayCommand\"}",
            "{\"MessageType\":\"SyncPlayCommand\",\"Data\":{\"GroupId\":\"group-1\"}}",
            "{\"MessageType\":\"SyncPlayCommand\",\"Data\":{\"GroupId\":\"group-1\",\"Command\":\"Pause\",\"When\":\"garbage\"}}",
            SyncPlayWireFrames.command("Rewind", groupId: "group-1"),
            "{\"MessageType\":\"SyncPlayGroupUpdate\"}",
            SyncPlayWireFrames.groupUpdate(type: "BrandNewType", data: [String: Any]()),
            SyncPlayWireFrames.groupUpdate(type: "GroupJoined", data: "not-a-group-info"),
            SyncPlayWireFrames.groupUpdate(type: "UserJoined", data: 42),
            SyncPlayWireFrames.playQueue(index: 9),
            SyncPlayWireFrames.playQueue(items: nil),
            SyncPlayWireFrames.playQueue(items: [], index: 3),
            SyncPlayWireFrames.playQueue(index: nil),
        ]
        // Non-UTF-8 binary and an empty binary frame, sent first (same ordered stream).
        try await f.server.sendBinary(Data([0xFF, 0xFE, 0x00, 0x80]))
        try await f.server.sendBinary(Data())

        let (events, current) = try await f.barrierThenCurrentGroup(texts)
        XCTAssertEqual(events, [], "unknown/malformed frames must emit nothing")
        XCTAssertEqual(current, Self.group, "unknown/malformed frames must not touch membership")
    }

    // MARK: - No-current queues, robustness

    /// Valid queues without a current item emit `queueChanged` with nil
    /// item/slot, retain membership, and never emit a stop.
    func testNoCurrentQueuesDispatchAndRetainMembership() async throws {
        let f = try await makeFixture()
        defer { f.cleanup() }
        let (events, current) = try await f.barrierThenCurrentGroup([
            SyncPlayWireFrames.playQueue(reason: "RemoveItems", items: [], index: 0),
            SyncPlayWireFrames.playQueue(reason: "RemoveItems", index: -1, isPlaying: false),
        ])
        func empty(_ playing: Bool) -> SyncPlayEvent {
            .queueChanged(
                SyncPlayQueueUpdate(
                    groupId: "group-1", startPositionSeconds: 5, isPlaying: playing,
                    reason: "RemoveItems", lastUpdate: Self.wireDate))
        }
        XCTAssertEqual(events, [empty(true), empty(false)])
        XCTAssertEqual(current, Self.group)
    }

    /// Foreign NotInGroup / GroupDoesNotExist must not clear membership.
    func testForeignRejectionsDoNotClearMembership() async throws {
        let f = try await makeFixture()
        defer { f.cleanup() }
        let (events, current) = try await f.barrierThenCurrentGroup(
            ["NotInGroup", "GroupDoesNotExist"].map {
                SyncPlayWireFrames.groupUpdate(type: $0, groupId: "group-2", data: "group-2")
            })
        XCTAssertEqual(events, [])
        XCTAssertEqual(current, Self.group)
    }

    func testForeignParticipantUpdatesProduceNoEvents() async throws {
        let f = try await makeFixture()
        defer { f.cleanup() }
        let (events, current) = try await f.barrierThenCurrentGroup([
            SyncPlayWireFrames.groupUpdate(type: "UserJoined", groupId: "group-2", data: "bob"),
            SyncPlayWireFrames.groupUpdate(type: "UserLeft", groupId: "group-2", data: "bob"),
        ])
        XCTAssertEqual(events, [])
        XCTAssertEqual(current, Self.group)
    }

    func testEmptyQueueWithInvalidNegativeIndexIsIgnored() async throws {
        let f = try await makeFixture()
        defer { f.cleanup() }
        let (events, current) = try await f.barrierThenCurrentGroup([
            SyncPlayWireFrames.playQueue(reason: "RemoveItems", items: [], index: -2)
        ])
        XCTAssertEqual(events, [])
        XCTAssertEqual(current, Self.group)
    }

    /// Scalars / arrays / nulls where a dictionary is expected must not raise
    /// ObjC exceptions (NSJSONSerialization) or alter state.
    func testScalarArrayAndNullPayloadsAreIgnoredWithoutCrashing() async throws {
        let f = try await makeFixture()
        defer { f.cleanup() }
        var frames: [String] = []
        let payloads: [Any] = ["str", 42, true, NSNull(), [Any](), [1, 2], [String: Any]()]
        for type in ["GroupJoined", "PlayQueue", "StateUpdate", "LibraryAccessDenied"] {
            for p in payloads { frames.append(SyncPlayWireFrames.groupUpdate(type: type, data: p)) }
        }
        let (events, current) = try await f.barrierThenCurrentGroup(frames)
        XCTAssertEqual(events, [])
        XCTAssertEqual(current, Self.group)
    }

    /// Case differences in GroupId still match the current group.
    func testGroupScopeNormalizesCase() async throws {
        let f = try await makeFixture()
        defer { f.cleanup() }
        let events = try await f.markerEvents([
            SyncPlayWireFrames.command("Pause", groupId: "GROUP-1")
        ])
        XCTAssertEqual(events, [Self.cmd(.pause, position: 0, groupId: "GROUP-1")])
    }

    func testGroupScopeNormalizesDashedAndCompactUUIDs() async throws {
        let f = try await makeFixture()
        defer { f.cleanup() }
        let dashed = "12345678-1234-ABCD-9876-123456789ABC"
        let compact = "123456781234abcd9876123456789abc"
        let events = try await f.markerEvents([
            SyncPlayWireFrames.groupUpdate(
                type: "GroupJoined", groupId: dashed,
                data: SyncPlayWireFrames.groupInfo(id: compact, name: "UUID group")),
            SyncPlayWireFrames.command("Pause", groupId: dashed),
        ])
        XCTAssertEqual(
            events,
            [
                .groupChanged(SyncPlayGroup(id: compact, name: "UUID group")),
                Self.cmd(.pause, position: 0, groupId: dashed),
            ])
    }

    func testGroupJoinedWithMismatchedOuterAndInnerIDsIsIgnored() async throws {
        let f = try await makeFixture()
        defer { f.cleanup() }
        let (events, current) = try await f.barrierThenCurrentGroup([
            SyncPlayWireFrames.groupUpdate(
                type: "GroupJoined", groupId: "group-2",
                data: SyncPlayWireFrames.groupInfo(id: "group-3", name: "Mismatched"))
        ])
        XCTAssertEqual(events, [])
        XCTAssertEqual(current, Self.group)
    }

    func testUnscopedGroupLeftUsesItsPayloadIdentity() async throws {
        let f = try await makeFixture()
        defer { f.cleanup() }
        let (events, current) = try await f.barrierThenCurrentGroup([
            SyncPlayWireFrames.groupUpdate(type: "GroupLeft", groupId: nil, data: "group-1")
        ])
        XCTAssertEqual(events, [.disconnected])
        XCTAssertNil(current)
    }

    func testMalformedQueueTimestampDoesNotDiscardItsValidQueue() async throws {
        let f = try await makeFixture()
        defer { f.cleanup() }
        let frame = SyncPlayWireFrames.playQueue(reason: "MoveItem")
            .replacingOccurrences(of: SyncPlayWireFrames.wireDate, with: "invalid-date")
        let events = try await f.markerEvents([frame])
        XCTAssertEqual(
            events,
            [
                .queueChanged(
                    SyncPlayQueueUpdate(
                        groupId: "group-1", itemId: "item-b", playlistItemId: "pl-b",
                        startPositionSeconds: 5, isPlaying: true, reason: "MoveItem"))
            ])
    }

    /// The SDK preserves events when membership is unknown; the consumer must
    /// compare their scope to its authenticated playback/membership generation.
    func testLateFramesAfterLeavingPreserveScopeWithoutRestoringMembership() async throws {
        let f = try await makeFixture()
        defer { f.cleanup() }
        let (events, current) = try await f.barrierThenCurrentGroup([
            SyncPlayWireFrames.groupUpdate(type: "GroupLeft", data: "group-1"),
            SyncPlayWireFrames.command("Pause"),
            SyncPlayWireFrames.playQueue(),
        ])
        XCTAssertEqual(
            events,
            [
                .disconnected,
                Self.cmd(.pause, position: 0),
                .queueChanged(
                    SyncPlayQueueUpdate(
                        groupId: "group-1", itemId: "item-b", playlistItemId: "pl-b",
                        startPositionSeconds: 5, isPlaying: true, reason: "NewPlaylist",
                        lastUpdate: Self.wireDate)),
            ])
        XCTAssertNil(current)
    }

    func testUnscopedCommandPreservesMissingGroupID() async throws {
        let f = try await makeFixture()
        defer { f.cleanup() }
        let events = try await f.markerEvents([SyncPlayWireFrames.command("Pause", groupId: nil)])
        XCTAssertEqual(
            events,
            [
                .command(
                    SyncPlayCommand(
                        kind: .pause, playlistItemId: "pl-1", positionSeconds: 0,
                        when: Self.wireDate, emittedAt: Self.wireDate))
            ])
    }

    // MARK: - Zero-GUID NotInGroup (Jellyfin 12.2 rejection of a non-member command)

    private static let zeroCompact = "00000000000000000000000000000000"
    private static let zeroDashed = "00000000-0000-0000-0000-000000000000"

    private static let group2 = SyncPlayGroup(id: "group-2", name: "Other")

    private static func zeroNotInGroup(_ scope: String) -> String {
        SyncPlayWireFrames.groupUpdate(type: "NotInGroup", groupId: scope, data: "")
    }

    /// RED on unchanged source. After a local group action, the server's zero-GUID
    /// NotInGroup (compact or dashed) ends the cached membership exactly once.
    func testZeroGuidNotInGroupAfterLocalActionClearsMembership() async throws {
        for scope in [Self.zeroCompact, Self.zeroDashed] {
            let f = try await makeFixture()
            defer { f.cleanup() }
            await f.service.requestPause(positionSeconds: 0)
            let (events, current) = try await f.barrierThenCurrentGroup([
                Self.zeroNotInGroup(scope)
            ])
            XCTAssertEqual(events, [.disconnected], scope)
            XCTAssertNil(current, scope)
        }
    }

    /// RED on unchanged source. Repeated zero rejections after membership was
    /// cleared emit no further `.disconnected`.
    func testRepeatedZeroGuidNotInGroupEmitsSingleDisconnected() async throws {
        let f = try await makeFixture()
        defer { f.cleanup() }
        await f.service.requestPause(positionSeconds: 0)
        let (events, current) = try await f.barrierThenCurrentGroup([
            Self.zeroNotInGroup(Self.zeroCompact),
            Self.zeroNotInGroup(Self.zeroCompact),
            Self.zeroNotInGroup(Self.zeroDashed),
            Self.zeroNotInGroup(Self.zeroDashed),
        ])
        XCTAssertEqual(events, [.disconnected])
        XCTAssertNil(current)
    }

    /// Without any local group action a zero-GUID rejection is not ours.
    func testZeroGuidNotInGroupWithoutLocalActionIsIgnored() async throws {
        let f = try await makeFixture()
        defer { f.cleanup() }
        let (events, current) = try await f.barrierThenCurrentGroup([
            Self.zeroNotInGroup(Self.zeroCompact), Self.zeroNotInGroup(Self.zeroDashed),
        ])
        XCTAssertEqual(events, [])
        XCTAssertEqual(current, Self.group)
    }

    /// An action sent for the old membership must not let a stale zero rejection
    /// end a membership installed afterwards by a WebSocket GroupJoined.
    func testZeroGuidNotInGroupAfterWebSocketGroupJoinedIsIgnored() async throws {
        let f = try await makeFixture()
        defer { f.cleanup() }
        await f.service.requestPause(positionSeconds: 0)
        try await f.server.sendText(
            SyncPlayWireFrames.groupUpdate(
                type: "GroupJoined", groupId: "group-2",
                data: SyncPlayWireFrames.groupInfo(id: "group-2", name: "Other")))
        _ = try await f.waitForEvent(from: 1) { $0 == .groupChanged(Self.group2) }
        let (events, current) = try await f.barrierThenCurrentGroup(
            [Self.zeroNotInGroup(Self.zeroCompact), Self.zeroNotInGroup(Self.zeroDashed)],
            barrierGroupId: "group-2")
        XCTAssertEqual(events, [.groupChanged(Self.group2)])
        XCTAssertEqual(current, Self.group2)
    }

    /// Same, for a membership installed by a successful `joinGroup`.
    func testZeroGuidNotInGroupAfterSuccessfulJoinIsIgnored() async throws {
        let f = try await makeFixture()
        defer { f.cleanup() }
        await f.service.requestPause(positionSeconds: 0)
        try await f.service.joinGroup(id: "group-2")
        let (events, current) = try await f.barrierThenCurrentGroup(
            [Self.zeroNotInGroup(Self.zeroCompact), Self.zeroNotInGroup(Self.zeroDashed)],
            barrierGroupId: "group-2")
        XCTAssertEqual(events, [.groupChanged(Self.group2)])
        XCTAssertEqual(current, Self.group2)
    }

    /// Same, for a membership installed by a successful `createGroup` (the fake
    /// server answers group-1 again, so the cached group is identical).
    func testZeroGuidNotInGroupAfterSuccessfulCreateIsIgnored() async throws {
        let f = try await makeFixture()
        defer { f.cleanup() }
        await f.service.requestPause(positionSeconds: 0)
        let created = try await f.service.createGroup(name: "Fake")
        XCTAssertEqual(created, Self.group)
        let (events, current) = try await f.barrierThenCurrentGroup([
            Self.zeroNotInGroup(Self.zeroCompact), Self.zeroNotInGroup(Self.zeroDashed),
        ])
        XCTAssertEqual(events, [.groupChanged(Self.group)])
        XCTAssertEqual(current, Self.group)
    }

    /// Even with a local action recorded, zero-GUID scopes on anything other than
    /// NotInGroup stay foreign, and nonzero foreign rejections stay ignored.
    func testZeroGuidScopeOnOtherUpdatesRemainsForeignAfterLocalAction() async throws {
        let f = try await makeFixture()
        defer { f.cleanup() }
        await f.service.requestPause(positionSeconds: 0)
        var frames = [
            SyncPlayWireFrames.groupUpdate(
                type: "GroupLeft", groupId: Self.zeroCompact, data: Self.zeroCompact),
            SyncPlayWireFrames.groupUpdate(
                type: "GroupDoesNotExist", groupId: Self.zeroCompact, data: ""),
            SyncPlayWireFrames.groupUpdate(
                type: "UserJoined", groupId: Self.zeroDashed, data: "bob"),
            SyncPlayWireFrames.groupUpdate(type: "UserLeft", groupId: Self.zeroDashed, data: "bob"),
            SyncPlayWireFrames.playQueue(groupId: Self.zeroCompact),
        ]
        frames += ["Unpause", "Pause", "Seek", "Stop"].map {
            SyncPlayWireFrames.command($0, groupId: Self.zeroCompact, ticks: 100_000_000)
        }
        frames += ["NotInGroup", "GroupDoesNotExist"].map {
            SyncPlayWireFrames.groupUpdate(type: $0, groupId: "group-2", data: "group-2")
        }
        let (events, current) = try await f.barrierThenCurrentGroup(frames)
        XCTAssertEqual(events, [])
        XCTAssertEqual(current, Self.group)
    }

    /// Every public group action path records the local action.
    func testZeroGuidNotInGroupAfterEachGroupActionClearsMembership() async throws {
        let actions: [(String, @Sendable (JellyfinSyncPlayService) async throws -> Void)] = [
            ("requestPlay", { await $0.requestPlay(positionSeconds: 1) }),
            ("requestPause", { await $0.requestPause(positionSeconds: 1) }),
            ("requestSeek", { await $0.requestSeek(positionSeconds: 1) }),
            ("stopGroup", { await $0.stopGroup() }),
            ("setNewQueue", { try await $0.setNewQueue(itemIds: ["i1"], startPositionSeconds: 1) }),
            (
                "notifyReady",
                { await $0.notifyReady(positionSeconds: 1, isPlaying: true, playlistItemId: "p") }
            ),
            (
                "notifyBuffering",
                {
                    await $0.notifyBuffering(
                        positionSeconds: 1, isPlaying: true, playlistItemId: "p")
                }
            ),
        ]
        for (name, action) in actions {
            let f = try await makeFixture()
            defer { f.cleanup() }
            try await action(f.service)
            let (events, current) = try await f.barrierThenCurrentGroup([
                Self.zeroNotInGroup(Self.zeroCompact)
            ])
            XCTAssertEqual(events, [.disconnected], name)
            XCTAssertNil(current, name)
        }
    }

    /// A GroupJoined refresh of the SAME group identity in another UUID spelling
    /// keeps the recorded local action, so the zero rejection still clears.
    func testZeroGuidNotInGroupAfterSameIdentityGroupJoinedRefreshClears() async throws {
        let f = try await makeFixture()
        defer { f.cleanup() }
        let dashed = "0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9"
        let alias = "0A1B2C3D4E5F60718293A4B5C6D7E8F9"
        func joined(_ id: String, _ name: String) -> String {
            SyncPlayWireFrames.groupUpdate(
                type: "GroupJoined", groupId: id,
                data: SyncPlayWireFrames.groupInfo(id: id, name: name))
        }
        try await f.server.sendText(joined(dashed, "Real"))
        _ = try await f.waitForEvent(from: 1) {
            if case .groupChanged(let g) = $0 { return g.name == "Real" }
            return false
        }
        await f.service.requestPause(positionSeconds: 0)
        try await f.server.sendText(joined(alias, "Refreshed"))
        _ = try await f.waitForEvent(from: 1) {
            if case .groupChanged(let g) = $0 { return g.name == "Refreshed" }
            return false
        }
        let (events, current) = try await f.barrierThenCurrentGroup(
            [Self.zeroNotInGroup(Self.zeroDashed)], barrierGroupId: alias)
        XCTAssertEqual(events.filter { $0 == .disconnected }.count, 1)
        XCTAssertNil(current)
    }

    /// Weaker transport condition: `socketTask != nil` only means a transport is
    /// allocated, not that the handshake completed. The action is recorded while
    /// the upgrade is still held; a received frame afterwards confirms readiness.
    func testZeroGuidNotInGroupAfterActionWhileSocketStillConnectingClears() async throws {
        let f = try await makeFixture(holdUpgrade: true)
        defer { f.cleanup() }
        try await f.server.waitForPendingUpgrade()
        XCTAssertEqual(f.server.upgradeCount, 0, "handshake must not have completed")
        await f.service.requestPause(positionSeconds: 0)
        try f.server.releaseUpgrade()
        try await f.server.waitForSocket()
        let (events, current) = try await f.barrierThenCurrentGroup([
            Self.zeroNotInGroup(Self.zeroCompact)
        ])
        XCTAssertEqual(events, [.disconnected])
        XCTAssertNil(current)
    }

    /// RED while the local action is recorded only after the HTTP response: the
    /// Pause request has reached the server (response held), so the action was
    /// sent and a zero-GUID rejection arriving BEFORE the REST 204 must clear.
    func testZeroGuidNotInGroupBeforePauseResponseClearsMembership() async throws {
        let f = try await makeFixture(holdPauseResponse: true)
        let service = f.service
        let pause = Task { await service.requestPause(positionSeconds: 0) }
        var released = false
        defer {
            if !released { try? f.server.releasePauseResponse() }
            pause.cancel()
            f.cleanup()
        }
        try await f.server.waitForPendingPause()
        let (events, current) = try await f.barrierThenCurrentGroup([
            Self.zeroNotInGroup(Self.zeroCompact)
        ])
        XCTAssertEqual(
            events.filter { $0 == .disconnected }.count, 1,
            "zero NotInGroup before the REST response must clear")
        XCTAssertNil(current)
        try f.server.releasePauseResponse()
        released = true
        await pause.value
        let after = await f.service.currentGroup
        XCTAssertNil(after)
        XCTAssertEqual(f.log.all.filter { $0 == .disconnected }.count, 1)
    }

    /// RED while an old Pause completion can re-arm after a same-ID createGroup:
    /// the new membership context reset the intent, so the late completion of
    /// the old request must not let a zero rejection clear the new membership.
    func testOldPauseCompletionAfterSameIdCreateDoesNotRearmZeroRejection() async throws {
        let f = try await makeFixture(holdPauseResponse: true)
        let service = f.service
        let pause = Task { await service.requestPause(positionSeconds: 0) }
        var released = false
        defer {
            if !released { try? f.server.releasePauseResponse() }
            pause.cancel()
            f.cleanup()
        }
        try await f.server.waitForPendingPause()
        let created = try await f.service.createGroup(name: "Fake")
        XCTAssertEqual(created, Self.group)
        try f.server.releasePauseResponse()
        released = true
        await pause.value
        let (events, current) = try await f.barrierThenCurrentGroup([
            Self.zeroNotInGroup(Self.zeroCompact), Self.zeroNotInGroup(Self.zeroDashed),
        ])
        XCTAssertEqual(events, [.groupChanged(Self.group)])
        XCTAssertFalse(events.contains(.disconnected))
        XCTAssertEqual(current, Self.group)
    }

    /// Existing behaviour: matching, missing and empty scopes still clear.
    func testMatchingMissingAndEmptyScopeNotInGroupStillClearsMembership() async throws {
        let scopes: [String?] = ["group-1", "GROUP-1", nil, ""]
        for scope in scopes {
            let f = try await makeFixture()
            defer { f.cleanup() }
            let (events, current) = try await f.barrierThenCurrentGroup([
                SyncPlayWireFrames.groupUpdate(type: "NotInGroup", groupId: scope, data: "")
            ])
            XCTAssertEqual(events, [.disconnected], "scope \(scope ?? "nil")")
            XCTAssertNil(current, "scope \(scope ?? "nil")")
        }
    }

    // MARK: - DTO metadata characterization

    /// Characterizes decoded GroupId, PlaylistItemId, When, EmittedAt and null positions.
    func testCommandMetadataDecodesFromFullWireShape() throws {
        let frame = SyncPlayWireFrames.command(
            "Pause", groupId: "group-1", playlistItemId: "pl-9", ticks: nil)
        let message = try JellyfinJSON.decoder.decode(
            SyncPlayCommandMessageDTO.self, from: Data(frame.utf8))
        let dto = try XCTUnwrap(message.data)
        XCTAssertEqual(dto.groupId, "group-1")
        XCTAssertEqual(dto.playlistItemId, "pl-9")
        XCTAssertEqual(dto.command, "Pause")
        XCTAssertNil(dto.positionTicks)
        XCTAssertNotNil(dto.when)
        XCTAssertEqual(dto.emittedAt, dto.when)
    }

    /// Preserves LastUpdate and tolerates unused RepeatMode/ShuffleMode fields.
    func testPlayQueueMetadataDecodesAndToleratesUnmodelledFields() throws {
        let frame = SyncPlayWireFrames.playQueue(reason: "MoveItem")
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(frame.utf8)) as? [String: Any])
        let update = try XCTUnwrap(root["Data"] as? [String: Any])
        let inner = try JSONSerialization.data(withJSONObject: try XCTUnwrap(update["Data"]))
        let dto = try JellyfinJSON.decoder.decode(PlayQueueUpdateDTO.self, from: inner)
        XCTAssertEqual(dto.reason, "MoveItem")
        XCTAssertEqual(dto.playingItemIndex, 1)
        XCTAssertEqual(dto.startPositionTicks, 50_000_000)
        XCTAssertEqual(dto.isPlaying, true)
        XCTAssertEqual(dto.playlist?.map(\.playlistItemId), ["pl-a", "pl-b"])
        XCTAssertEqual(dto.lastUpdate, Self.wireDate)
    }
}
