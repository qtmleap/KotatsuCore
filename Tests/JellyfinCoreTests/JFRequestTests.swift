import XCTest
import Alamofire
@testable import JellyfinCore

/// Verifies that each `JFRequest` composes the correct method, URL, and body
/// against the OpenAPI-documented Jellyfin endpoints. Pure unit tests — no
/// network access; they inspect the request struct directly.
final class JFRequestTests: XCTestCase {

    private let baseURL = URL(string: "https://jellyfin.example.com")!

    // MARK: - Helpers

    private func url<R: JFRequest>(_ request: R) throws -> URL {
        try request.buildURL(baseURL: baseURL)
    }

    private func queryPairs(_ url: URL) -> [String: String] {
        var out: [String: String] = [:]
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .forEach { out[$0.name] = $0.value ?? "" }
        return out
    }

    private func decodeBody(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Auth

    func testQuickConnectInitiate() throws {
        let req = QuickConnectInitiateRequest()
        XCTAssertEqual(req.method, .post)
        XCTAssertEqual(try url(req).path, "/QuickConnect/Initiate")
        XCTAssertTrue(req.query.isEmpty)
        XCTAssertNil(try req.bodyData())
    }

    func testQuickConnectPoll() throws {
        let req = QuickConnectPollRequest(secret: "abc123")
        XCTAssertEqual(req.method, .get)
        let u = try url(req)
        XCTAssertEqual(u.path, "/QuickConnect/Connect")
        XCTAssertEqual(queryPairs(u), ["Secret": "abc123"])
    }

    func testAuthenticateWithQuickConnect() throws {
        let req = AuthenticateWithQuickConnectRequest(secret: "s3cr3t")
        XCTAssertEqual(req.method, .post)
        XCTAssertEqual(try url(req).path, "/Users/AuthenticateWithQuickConnect")
        let data = try XCTUnwrap(try req.bodyData())
        let obj = try decodeBody(data)
        XCTAssertEqual(obj["Secret"] as? String, "s3cr3t")
    }

    func testGetUser() throws {
        let req = GetUserRequest(userId: "u1")
        XCTAssertEqual(req.method, .get)
        XCTAssertEqual(try url(req).path, "/Users/u1")
    }

    func testLogout() throws {
        let req = LogoutRequest()
        XCTAssertEqual(req.method, .post)
        XCTAssertEqual(try url(req).path, "/Sessions/Logout")
        XCTAssertTrue(R.Response.self == JFEmptyResponse.self)
    }
    // Local helper for the metatype check above.
    private enum R { typealias Response = LogoutRequest.Response }

    // MARK: - Media (shelves)

    func testHeroFeatured() throws {
        let req = HeroFeaturedRequest(userId: "u1")
        XCTAssertEqual(req.method, .get)
        let u = try url(req)
        XCTAssertEqual(u.path, "/Users/u1/Items")
        let q = queryPairs(u)
        XCTAssertEqual(q["SortBy"], "Random")
        XCTAssertEqual(q["Limit"], "1")
        XCTAssertEqual(q["IncludeItemTypes"], "Movie")
        XCTAssertEqual(q["Recursive"], "true")
        XCTAssertNotNil(q["Fields"])
        XCTAssertEqual(q["EnableImageTypes"], "Primary,Backdrop,Logo")
    }

    func testContinueWatching() throws {
        let req = ContinueWatchingRequest(userId: "u1")
        let u = try url(req)
        XCTAssertEqual(u.path, "/Users/u1/Items/Resume")
        let q = queryPairs(u)
        XCTAssertEqual(q["Limit"], "12")
        XCTAssertEqual(q["MediaTypes"], "Video")
    }

    func testNextUpDefault() throws {
        let req = NextUpRequest(userId: "u1")
        let u = try url(req)
        XCTAssertEqual(u.path, "/Shows/NextUp")
        let q = queryPairs(u)
        XCTAssertEqual(q["UserId"], "u1")
        XCTAssertEqual(q["Limit"], "12")
        XCTAssertNil(q["SeriesId"])
    }

    func testNextUpWithSeriesFilter() throws {
        let req = NextUpRequest(userId: "u1", seriesId: "series-42", limit: 1, fields: "Overview")
        let q = queryPairs(try url(req))
        XCTAssertEqual(q["SeriesId"], "series-42")
        XCTAssertEqual(q["Limit"], "1")
        XCTAssertEqual(q["Fields"], "Overview")
    }

    func testFavorites() throws {
        let req = FavoritesRequest(userId: "u1")
        let u = try url(req)
        XCTAssertEqual(u.path, "/Users/u1/Items")
        let q = queryPairs(u)
        XCTAssertEqual(q["IsFavorite"], "true")
        XCTAssertEqual(q["IncludeItemTypes"], "Movie,Series")
        XCTAssertEqual(q["SortBy"], "SortName")
        XCTAssertEqual(q["SortOrder"], "Ascending")
    }

    func testRandomForRewatch() throws {
        let req = RandomForRewatchRequest(userId: "u1")
        let q = queryPairs(try url(req))
        XCTAssertEqual(q["SortBy"], "Random")
        XCTAssertEqual(q["Filters"], "IsPlayed")
    }

    func testLatestMovies() throws {
        let req = LatestItemsRequest(userId: "u1", includeItemTypes: "Movie")
        let u = try url(req)
        XCTAssertEqual(u.path, "/Users/u1/Items/Latest")
        let q = queryPairs(u)
        XCTAssertEqual(q["IncludeItemTypes"], "Movie")
        XCTAssertEqual(q["Limit"], "30")
    }

    func testLatestSeriesWithCustomLimit() throws {
        let req = LatestItemsRequest(userId: "u1", includeItemTypes: "Series", limit: 5)
        let q = queryPairs(try url(req))
        XCTAssertEqual(q["IncludeItemTypes"], "Series")
        XCTAssertEqual(q["Limit"], "5")
    }

    // MARK: - Media (detail)

    func testItemDetail() throws {
        let req = ItemDetailRequest(userId: "u1", itemId: "item-1")
        let u = try url(req)
        XCTAssertEqual(u.path, "/Users/u1/Items/item-1")
        let q = queryPairs(u)
        let fields = try XCTUnwrap(q["Fields"])
        XCTAssertTrue(fields.contains("MediaSources"))
        XCTAssertTrue(fields.contains("MediaStreams"))
    }

    func testItemLookup() throws {
        let req = ItemLookupRequest(userId: "u1", itemId: "season-1")
        XCTAssertEqual(try url(req).path, "/Users/u1/Items/season-1")
        XCTAssertTrue(req.query.isEmpty)
    }

    func testSeasons() throws {
        let req = SeasonsRequest(seriesId: "s-1", userId: "u1")
        let u = try url(req)
        XCTAssertEqual(u.path, "/Shows/s-1/Seasons")
        XCTAssertEqual(queryPairs(u)["UserId"], "u1")
    }

    func testEpisodes() throws {
        let req = EpisodesRequest(seriesId: "s-1", userId: "u1", seasonId: "sn-1")
        let u = try url(req)
        XCTAssertEqual(u.path, "/Shows/s-1/Episodes")
        let q = queryPairs(u)
        XCTAssertEqual(q["UserId"], "u1")
        XCTAssertEqual(q["SeasonId"], "sn-1")
    }

    // MARK: - Search

    func testSearchHints() throws {
        let req = SearchHintsRequest(userId: "u1", searchTerm: "matrix")
        let u = try url(req)
        XCTAssertEqual(u.path, "/Search/Hints")
        let q = queryPairs(u)
        XCTAssertEqual(q["UserId"], "u1")
        XCTAssertEqual(q["SearchTerm"], "matrix")
        XCTAssertEqual(q["Limit"], "50")
        XCTAssertEqual(q["IncludeItemTypes"], "Movie,Series,Episode")
    }

    func testSearchHintsKindFilter() throws {
        let req = SearchHintsRequest(userId: "u1", searchTerm: "x", includeItemTypes: "Episode", limit: 20)
        let q = queryPairs(try url(req))
        XCTAssertEqual(q["IncludeItemTypes"], "Episode")
        XCTAssertEqual(q["Limit"], "20")
    }

    // MARK: - Favourites / watched

    func testSetFavoriteOn() throws {
        let req = SetFavoriteRequest(userId: "u1", itemId: "i1", isFavorite: true)
        XCTAssertEqual(req.method, .post)
        XCTAssertEqual(try url(req).path, "/Users/u1/FavoriteItems/i1")
    }

    func testSetFavoriteOff() throws {
        let req = SetFavoriteRequest(userId: "u1", itemId: "i1", isFavorite: false)
        XCTAssertEqual(req.method, .delete)
    }

    func testSetWatchedOn() throws {
        let req = SetWatchedRequest(userId: "u1", itemId: "i1", isWatched: true)
        XCTAssertEqual(req.method, .post)
        XCTAssertEqual(try url(req).path, "/Users/u1/PlayedItems/i1")
    }

    func testSetWatchedOff() throws {
        let req = SetWatchedRequest(userId: "u1", itemId: "i1", isWatched: false)
        XCTAssertEqual(req.method, .delete)
    }

    // MARK: - Playback

    func testPlaybackInfoRequestShape() throws {
        let req = PlaybackInfoRequest(
            itemId: "item-1",
            userId: "u1",
            maxStreamingBitrate: 20_000_000,
            deviceProfile: ["Name": "Apple TV"],
            audioStreamIndex: 2,
            subtitleStreamIndex: nil
        )
        XCTAssertEqual(req.method, .post)
        let u = try url(req)
        XCTAssertEqual(u.path, "/Items/item-1/PlaybackInfo")
        let q = queryPairs(u)
        XCTAssertEqual(q["UserId"], "u1")
        XCTAssertEqual(q["AutoOpenLiveStream"], "true")
        XCTAssertEqual(q["MaxStreamingBitrate"], "20000000")

        let data = try XCTUnwrap(try req.bodyData())
        let obj = try decodeBody(data)
        XCTAssertEqual(obj["UserId"] as? String, "u1")
        XCTAssertEqual(obj["MaxStreamingBitrate"] as? Int, 20_000_000)
        XCTAssertEqual(obj["StartTimeTicks"] as? Int, 0)
        XCTAssertEqual(obj["AutoOpenLiveStream"] as? Bool, true)
        XCTAssertEqual(obj["EnableDirectPlay"] as? Bool, true)
        XCTAssertEqual(obj["EnableDirectStream"] as? Bool, true)
        XCTAssertEqual(obj["EnableTranscoding"] as? Bool, true)
        XCTAssertEqual(obj["AllowVideoStreamCopy"] as? Bool, true)
        XCTAssertEqual(obj["AllowAudioStreamCopy"] as? Bool, true)
        XCTAssertEqual(obj["AudioStreamIndex"] as? Int, 2)
        XCTAssertNil(obj["SubtitleStreamIndex"])
        let profile = try XCTUnwrap(obj["DeviceProfile"] as? [String: Any])
        XCTAssertEqual(profile["Name"] as? String, "Apple TV")
    }

    func testReportPlaybackStartEncodesPascalCase() throws {
        let payload = PlaybackStartInfoDTO(
            itemId: "item-1",
            mediaSourceId: "src-1",
            playSessionId: "ps-1",
            audioStreamIndex: 1,
            subtitleStreamIndex: nil,
            playMethod: "DirectPlay",
            canSeek: true,
            positionTicks: 0
        )
        let req = ReportPlaybackStartRequest(payload: payload)
        XCTAssertEqual(try url(req).path, "/Sessions/Playing")
        let data = try XCTUnwrap(try req.bodyData())
        let obj = try decodeBody(data)
        XCTAssertEqual(obj["ItemId"] as? String, "item-1")
        XCTAssertEqual(obj["MediaSourceId"] as? String, "src-1")
        XCTAssertEqual(obj["PlaySessionId"] as? String, "ps-1")
        XCTAssertEqual(obj["PlayMethod"] as? String, "DirectPlay")
        XCTAssertEqual(obj["CanSeek"] as? Bool, true)
        XCTAssertEqual(obj["AudioStreamIndex"] as? Int, 1)
    }

    func testReportPlaybackProgress() throws {
        let payload = PlaybackProgressInfoDTO(
            itemId: "item-1",
            mediaSourceId: "src-1",
            playSessionId: "ps-1",
            positionTicks: 12345,
            isPaused: true,
            isMuted: false,
            playMethod: "Transcode",
            canSeek: true,
            eventName: "TimeUpdate"
        )
        let req = ReportPlaybackProgressRequest(payload: payload)
        XCTAssertEqual(try url(req).path, "/Sessions/Playing/Progress")
        let obj = try decodeBody(try XCTUnwrap(try req.bodyData()))
        XCTAssertEqual(obj["IsPaused"] as? Bool, true)
        XCTAssertEqual(obj["PositionTicks"] as? Int, 12345)
        XCTAssertEqual(obj["EventName"] as? String, "TimeUpdate")
        XCTAssertEqual(obj["PlayMethod"] as? String, "Transcode")
    }

    func testReportPlaybackStop() throws {
        let payload = PlaybackStopInfoDTO(
            itemId: "item-1",
            mediaSourceId: "src-1",
            playSessionId: "ps-1",
            positionTicks: 999,
            failed: false
        )
        let req = ReportPlaybackStopRequest(payload: payload)
        XCTAssertEqual(try url(req).path, "/Sessions/Playing/Stopped")
        let obj = try decodeBody(try XCTUnwrap(try req.bodyData()))
        XCTAssertEqual(obj["Failed"] as? Bool, false)
        XCTAssertEqual(obj["PositionTicks"] as? Int, 999)
    }

    // MARK: - SyncPlay

    func testSyncPlayList() throws {
        let req = SyncPlayListRequest()
        XCTAssertEqual(req.method, .get)
        XCTAssertEqual(try url(req).path, "/SyncPlay/List")
    }

    func testSyncPlayNewGroup() throws {
        let req = SyncPlayNewGroupRequest(groupName: "Movie Night")
        XCTAssertEqual(req.method, .post)
        let u = try url(req)
        XCTAssertEqual(u.path, "/SyncPlay/New")
        XCTAssertEqual(queryPairs(u)["GroupName"], "Movie Night")
    }

    func testSyncPlayJoin() throws {
        let req = SyncPlayJoinRequest(groupId: "g1")
        let u = try url(req)
        XCTAssertEqual(u.path, "/SyncPlay/Join")
        XCTAssertEqual(queryPairs(u)["GroupId"], "g1")
    }

    func testSyncPlayLeave() throws {
        XCTAssertEqual(try url(SyncPlayLeaveRequest()).path, "/SyncPlay/Leave")
    }

    func testSyncPlayUnpause() throws {
        XCTAssertEqual(try url(SyncPlayUnpauseRequest()).path, "/SyncPlay/Unpause")
    }

    func testSyncPlayPause() throws {
        XCTAssertEqual(try url(SyncPlayPauseRequest()).path, "/SyncPlay/Pause")
    }

    func testSyncPlaySeek() throws {
        let req = SyncPlaySeekRequest(positionTicks: 123456789)
        let u = try url(req)
        XCTAssertEqual(u.path, "/SyncPlay/Seek")
        XCTAssertEqual(queryPairs(u)["PositionTicks"], "123456789")
    }

    // MARK: - System

    func testSystemInfoPublic() throws {
        XCTAssertEqual(try url(SystemInfoPublicRequest()).path, "/System/Info/Public")
    }

    func testSystemInfo() throws {
        XCTAssertEqual(try url(SystemInfoRequest()).path, "/System/Info")
    }

    func testEncodingOptions() throws {
        XCTAssertEqual(try url(EncodingOptionsRequest()).path, "/System/Configuration/encoding")
    }

    func testActiveSessionsDefault() throws {
        let req = ActiveSessionsRequest()
        let u = try url(req)
        XCTAssertEqual(u.path, "/Sessions")
        XCTAssertNil(u.query)
    }

    func testActiveSessionsWithFilter() throws {
        let req = ActiveSessionsRequest(activeWithinSeconds: 600)
        let u = try url(req)
        XCTAssertEqual(queryPairs(u)["ActiveWithinSeconds"], "600")
    }

    // MARK: - buildURL edge cases

    func testBuildURLWithBasePath() throws {
        let base = URL(string: "https://jellyfin.example.com/media")!
        let req = SystemInfoRequest()
        let u = try req.buildURL(baseURL: base)
        XCTAssertEqual(u.path, "/media/System/Info")
    }

    func testBuildURLDropsTrailingSlashOnBasePath() throws {
        let base = URL(string: "https://jellyfin.example.com/media/")!
        let req = SystemInfoRequest()
        let u = try req.buildURL(baseURL: base)
        XCTAssertEqual(u.path, "/media/System/Info")
    }

    func testBuildURLDropsNilQueryValues() throws {
        struct ProbeRequest: JFRequest {
            typealias Response = JFEmptyResponse
            let method: HTTPMethod = .get
            var path: String { "/probe" }
            var query: [String: String?] { ["Keep": "yes", "Drop": nil] }
        }
        let u = try ProbeRequest().buildURL(baseURL: baseURL)
        let q = queryPairs(u)
        XCTAssertEqual(q["Keep"], "yes")
        XCTAssertNil(q["Drop"])
    }

    // MARK: - HTTPClient wiring

    func testHTTPClientMakeURLRequestWithBody() throws {
        let server = Server(id: "s", name: "T", url: baseURL, version: "10.11.11")
        let client = JellyfinHTTPClient(server: server)
        let req = AuthenticateWithQuickConnectRequest(secret: "hello")
        let urlRequest = try client.makeURLRequest(for: req)
        XCTAssertEqual(urlRequest.httpMethod, "POST")
        XCTAssertEqual(urlRequest.url?.path, "/Users/AuthenticateWithQuickConnect")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(urlRequest.httpBody)
        let obj = try decodeBody(body)
        XCTAssertEqual(obj["Secret"] as? String, "hello")
    }

    func testHTTPClientMakeURLRequestWithoutBodyOmitsContentType() throws {
        let server = Server(id: "s", name: "T", url: baseURL, version: "10.11.11")
        let client = JellyfinHTTPClient(server: server)
        let urlRequest = try client.makeURLRequest(for: HeroFeaturedRequest(userId: "u1"))
        XCTAssertEqual(urlRequest.httpMethod, "GET")
        XCTAssertNil(urlRequest.httpBody)
        XCTAssertNil(urlRequest.value(forHTTPHeaderField: "Content-Type"))
    }
}
