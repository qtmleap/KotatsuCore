import Foundation
import XCTest

@testable import KotatsuCore

final class JellyfinPlaybackServiceTests: XCTestCase {
  private let server = Server(
    id: "server", name: "Server", url: URL(string: "https://example.com")!)

  func testChoosesCompatibleDirectPlayAcrossAllSources() throws {
    let service = makeService()
    let selection = try service.selectPlayback(
      from: try sources(
        """
        [
          {"Id":"mkv","Container":"mkv","SupportsDirectPlay":true,"TranscodingUrl":"/mkv.m3u8"},
          {"Id":"mp4","Container":"mp4","SupportsDirectPlay":true}
        ]
        """))

    XCTAssertEqual(selection.source.id, "mp4")
    XCTAssertEqual(selection.route, .directPlay)
  }

  func testChoosesTranscodeBeforeCompatibleDirectStream() throws {
    let service = makeService()
    let selection = try service.selectPlayback(
      from: try sources(
        """
        [
          {"Id":"stream","Container":"mp4","SupportsDirectStream":true},
          {"Id":"transcode","Container":"mkv","TranscodingUrl":"/videos/item/main.m3u8?x=1"}
        ]
        """))

    XCTAssertEqual(selection.source.id, "transcode")
    XCTAssertEqual(selection.route, .transcode("/videos/item/main.m3u8?x=1"))
  }

  func testRejectsStaleMatroskaDirectPlayDecisionWithoutFallback() throws {
    let service = makeService()

    XCTAssertThrowsError(
      try service.selectPlayback(
        from: try sources(
          """
          [{"Id":"mkv","Container":"mkv","SupportsDirectPlay":true}]
          """))
    ) { error in
      guard case JellyfinAPIError.server(let status, _) = error else {
        return XCTFail("Unexpected error: \(error)")
      }
      XCTAssertEqual(status, 415)
    }
  }

  func testSkipsEmptyTranscodeURLAndUsesLaterRoute() throws {
    let service = makeService()
    let selection = try service.selectPlayback(
      from: try sources(
        """
        [
          {"Id":"empty","Container":"mkv","TranscodingUrl":"  "},
          {"Id":"stream","Container":"mov","SupportsDirectStream":true}
        ]
        """))

    XCTAssertEqual(selection.source.id, "stream")
    XCTAssertEqual(selection.route, .directStream)
  }

  func testEmptySourcesReportsMissingField() {
    XCTAssertThrowsError(try makeService().selectPlayback(from: [])) { error in
      guard case JellyfinAPIError.missingField(let field) = error else {
        return XCTFail("Unexpected error: \(error)")
      }
      XCTAssertEqual(field, "MediaSources")
    }
  }

  private func makeService() -> JellyfinPlaybackService {
    JellyfinPlaybackService(
      http: JellyfinHTTPClient(server: server, accessToken: "token", userId: "user"),
      deviceProfileBuilder: DeviceProfileBuilder(generation: .iPad, hardwareHEVC: true)
    )
  }

  private func sources(_ json: String) throws -> [MediaSourceDTO] {
    try JellyfinJSON.decoder.decode([MediaSourceDTO].self, from: Data(json.utf8))
  }
}
