import Foundation
import XCTest

@testable import KotatsuCore

/// Modern Jellyfin servers authenticate URL-borne tokens with `ApiKey`
/// (the legacy `api_key` spelling is dropped). Covers the two URL-auth sites:
/// the SyncPlay WebSocket and direct play/stream URLs. Transcode URLs are
/// server-provided and intentionally untouched.
final class ModernApiKeyURLTests: XCTestCase {
  private let token = "synthetic+token&a=b%25?/_01~x"
  private let deviceId = "apikey-test-device"
  private let basePath = "/jf"

  private func query(_ pathAndQuery: String) throws -> (path: String, items: [String: String]) {
    let comps = try XCTUnwrap(URLComponents(string: "http://127.0.0.1" + pathAndQuery))
    var items: [String: String] = [:]
    for item in comps.queryItems ?? [] { items[item.name] = item.value ?? "" }
    return (comps.path, items)
  }

  private func waitForRequest(
    _ server: ScriptedHTTPServer, where predicate: (ScriptedHTTPServer.Request) -> Bool
  ) async throws -> ScriptedHTTPServer.Request {
    for _ in 0..<100 {
      if let r = server.requests.first(where: predicate) { return r }
      try await Task.sleep(nanoseconds: 50_000_000)
    }
    throw URLError(.timedOut)
  }

  func testSyncPlayWebSocketUsesApiKeyNotLegacyApiKey() async throws {
    let server = try ScriptedHTTPServer { request in
      request.path.contains("/SyncPlay/List")
        ? .json([]) : ScriptedHTTPServer.Response(status: 400)
    }
    let port = try await server.start()
    let configuration = URLSessionConfiguration.ephemeral
    let session = URLSession(configuration: configuration)
    defer {
      session.invalidateAndCancel()
      server.stop()
    }
    let base = Server(
      id: "s", name: "s", url: URL(string: "http://127.0.0.1:\(port)\(basePath)")!)
    let http = JellyfinHTTPClient(
      server: base, accessToken: token, userId: "user", deviceId: deviceId)
    let service = JellyfinSyncPlayService(http: http, urlSession: session)

    let listing = Task { try? await service.availableGroups() }
    defer { listing.cancel() }
    _ = await listing.value

    let socket = try await waitForRequest(server) { $0.path.contains("/socket") }
    XCTAssertEqual(socket.method, "GET")
    let parsed = try query(socket.path)
    XCTAssertEqual(parsed.path, basePath + "/socket")
    XCTAssertEqual(parsed.items["ApiKey"], token)
    XCTAssertEqual(parsed.items["deviceId"], deviceId)
    XCTAssertNil(parsed.items["api_key"])
    XCTAssertFalse(socket.path.contains("api_key"))
  }

  func testDirectPlayURLUsesApiKeyAndKeepsStatic() async throws {
    let url = try await playbackURL(
      source: #"{"Id":"src","Container":"mp4","SupportsDirectPlay":true}"#)
    let parsed = try query(url.path + "?" + (url.query ?? ""))
    assertModernQuery(parsed, itemId: "item1")
    XCTAssertEqual(parsed.items["Static"], "true")
  }

  func testDirectStreamURLUsesApiKeyAndOmitsStatic() async throws {
    let url = try await playbackURL(
      source: #"{"Id":"src","Container":"mov","SupportsDirectStream":true}"#)
    let parsed = try query(url.path + "?" + (url.query ?? ""))
    assertModernQuery(parsed, itemId: "item1")
    XCTAssertNil(parsed.items["Static"])
  }

  private func assertModernQuery(
    _ parsed: (path: String, items: [String: String]), itemId: String,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertEqual(parsed.path, basePath + "/Videos/\(itemId)/stream", file: file, line: line)
    XCTAssertEqual(parsed.items["ApiKey"], token, file: file, line: line)
    XCTAssertNil(parsed.items["api_key"], file: file, line: line)
    XCTAssertEqual(parsed.items["MediaSourceId"], "src", file: file, line: line)
    XCTAssertEqual(parsed.items["PlaySessionId"], "play-1", file: file, line: line)
    XCTAssertEqual(parsed.items["DeviceId"], deviceId, file: file, line: line)
  }

  private func playbackURL(source: String) async throws -> URL {
    let body = #"{"PlaySessionId":"play-1","MediaSources":[\#(source)]}"#
    let server = try ScriptedHTTPServer { _ in
      ScriptedHTTPServer.Response(body: Data(body.utf8))
    }
    let port = try await server.start()
    defer { server.stop() }
    let base = Server(
      id: "s", name: "s", url: URL(string: "http://127.0.0.1:\(port)\(basePath)/")!)
    let http = JellyfinHTTPClient(
      server: base, accessToken: token, userId: "user", deviceId: deviceId)
    let service = JellyfinPlaybackService(
      http: http, deviceProfileBuilder: DeviceProfileBuilder(generation: .iPad, hardwareHEVC: true))
    let session = try await service.requestPlayback(
      itemId: "item1", audioTrackId: nil, subtitleTrackId: nil, startPositionSeconds: 0)
    XCTAssertFalse(session.isTranscoded)
    return session.streamURL
  }
}
