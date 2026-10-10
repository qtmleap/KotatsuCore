import XCTest

@testable import KotatsuCore

/// A SyncPlay WebSocket transport failure is not a membership change: the
/// server-side group membership survives a dropped socket, so the service must
/// keep `currentGroup` and must not emit `.disconnected` (which consumers treat
/// as "left the group" and use to stop outbound commands). Only an explicit
/// leave (or GroupLeft / NotInGroup) clears the group and emits it.
///
/// The WebSocket handshake is forced to fail (HTTP 400) against a loopback
/// `ScriptedHTTPServer` through a real ephemeral `URLSession`; no WS server.
/// Ordering is proven with a later `.groupChanged` marker on the same ordered
/// stream, so there are no unbounded negative sleeps.
final class SyncPlayTransportMembershipTests: XCTestCase {
  /// Signals once when the first task on the session fails, i.e. our own
  /// socket has failed before the test proceeds.
  private final class FailureDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    let failed: XCTestExpectation
    init(_ failed: XCTestExpectation) { self.failed = failed }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?)
    {
      guard error != nil else { return }
      lock.lock()
      let first = !fired
      fired = true
      lock.unlock()
      if first { failed.fulfill() }
    }
  }

  private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int {
      lock.lock()
      defer { lock.unlock() }
      return value
    }
    func next() -> Int {
      lock.lock()
      defer { lock.unlock() }
      value += 1
      return value
    }
  }

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
    let service: JellyfinSyncPlayService
    let log: EventLog
    let socketFailed: XCTestExpectation
    let socketRequests: Counter
    let cleanup: () -> Void
  }

  private func makeFixture() async throws -> Fixture {
    let sockets = Counter()
    let server = try ScriptedHTTPServer { request in
      if request.path.contains("/socket") {
        // First socket fails its handshake; any reconnect just hangs so it
        // cannot add noise to the event order.
        return sockets.next() == 1
          ? ScriptedHTTPServer.Response(status: 400)
          : ScriptedHTTPServer.Response(status: 400, delay: 60)
      }
      if request.path.contains("/SyncPlay/List") {
        return .json([["GroupId": "group-2", "GroupName": "Other"]])
      }
      if request.path.contains("/SyncPlay/New") {
        return .json(["GroupId": "group-1", "GroupName": "Fake"])
      }
      return ScriptedHTTPServer.Response(status: 204, body: Data())
    }
    let port = try await server.start()
    let failed = expectation(description: "own socket failed")
    let session = URLSession(
      configuration: .ephemeral, delegate: FailureDelegate(failed), delegateQueue: nil)
    let base = Server(id: "s", name: "s", url: URL(string: "http://127.0.0.1:\(port)")!)
    let http = JellyfinHTTPClient(
      server: base, accessToken: "synthetic-token", userId: "user", deviceId: "device")
    let service = JellyfinSyncPlayService(http: http, urlSession: session)

    let log = EventLog()
    let consumer = Task {
      for await event in service.events { log.append(event) }
    }
    return Fixture(
      service: service, log: log, socketFailed: failed, socketRequests: sockets,
      cleanup: {
        consumer.cancel()
        session.invalidateAndCancel()
        server.stop()
      })
  }

  /// A second attempted socket proves the first listenLoop catch cleared
  /// socketTask. Its delayed response stays pending through the join marker.
  private func waitForFailureProcessing(_ fixture: Fixture) async throws {
    for _ in 0..<100 {
      _ = try await fixture.service.availableGroups()
      if fixture.socketRequests.count >= 2 { return }
      try await Task.sleep(nanoseconds: 50_000_000)
    }
    throw URLError(.timedOut)
  }

  /// Waits (bounded) for the marker `.groupChanged` of the later join, then
  /// returns every event emitted before it.
  private func eventsBeforeJoinMarker(
    _ fixture: Fixture, join id: String = "group-2"
  ) async throws -> [SyncPlayEvent] {
    try await fixture.service.joinGroup(id: id)
    for _ in 0..<100 {
      let events = fixture.log.all
      if let marker = events.firstIndex(where: {
        if case .groupChanged(let g) = $0 { return g.id == id }
        return false
      }) {
        return Array(events[..<marker])
      }
      try await Task.sleep(nanoseconds: 50_000_000)
    }
    throw URLError(.timedOut)
  }

  func testTransportFailureWhileMemberKeepsGroupAndEmitsNoDisconnected() async throws {
    let f = try await makeFixture()
    defer { f.cleanup() }

    let group = try await f.service.createGroup(name: "Fake")
    await fulfillment(of: [f.socketFailed], timeout: 10)
    try await waitForFailureProcessing(f)

    let current = await f.service.currentGroup
    XCTAssertEqual(current, group)

    let before = try await eventsBeforeJoinMarker(f)
    XCTAssertEqual(before.first, .groupChanged(group))
    XCTAssertFalse(
      before.contains(.disconnected),
      "socket-only failure must not look like a membership leave: \(before)")
  }

  func testExplicitLeaveStillEmitsExactlyOneDisconnectedAndClearsGroup() async throws {
    let f = try await makeFixture()
    defer { f.cleanup() }

    _ = try await f.service.createGroup(name: "Fake")
    await fulfillment(of: [f.socketFailed], timeout: 10)
    try await waitForFailureProcessing(f)

    try await f.service.leaveGroup()
    let afterLeave = await f.service.currentGroup
    XCTAssertNil(afterLeave)

    let before = try await eventsBeforeJoinMarker(f)
    XCTAssertEqual(
      before.filter { $0 == .disconnected }.count, 1,
      "only the explicit leave may emit .disconnected: \(before)")
  }
}
