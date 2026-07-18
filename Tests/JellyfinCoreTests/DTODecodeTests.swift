import XCTest
@testable import JellyfinCore

final class DTODecodeTests: XCTestCase {

    private let server = Server(
        id: "srv",
        name: "Test",
        url: URL(string: "https://jellyfin.example.com")!,
        version: "10.10.0"
    )

    func testMovieBaseItemDecodesToMediaItem() throws {
        let json = """
        {
            "Id": "abc",
            "Name": "Sample Movie",
            "Type": "Movie",
            "ProductionYear": 2024,
            "RunTimeTicks": 70800000000,
            "OfficialRating": "PG-13",
            "CommunityRating": 8.4,
            "ImageTags": {"Primary": "tag123", "Logo": "logotag"},
            "BackdropImageTags": ["backdroptag"],
            "UserData": {"Played": false, "IsFavorite": true, "PlayedPercentage": 42.0}
        }
        """.data(using: .utf8)!
        let dto = try JellyfinJSON.decoder.decode(BaseItemDTO.self, from: json)
        let item = dto.toMediaItem(server: server)
        XCTAssertEqual(item.id, "abc")
        XCTAssertEqual(item.kind, .movie)
        XCTAssertEqual(item.title, "Sample Movie")
        XCTAssertEqual(item.year, 2024)
        XCTAssertEqual(item.runtimeSeconds, 7080)
        XCTAssertTrue(item.isFavorite)
        XCTAssertEqual((item.progressFraction ?? 0), 0.42, accuracy: 0.0001)
        XCTAssertTrue(item.posterURL?.absoluteString.contains("Images/Primary") ?? false)
        XCTAssertTrue(item.backdropURL?.absoluteString.contains("Backdrop") ?? false)
    }

    func testEpisodeBaseItem() throws {
        let json = """
        {
            "Id": "ep-1",
            "Name": "Episode One",
            "Type": "Episode",
            "SeriesId": "series-1",
            "SeasonId": "season-1",
            "ParentIndexNumber": 1,
            "IndexNumber": 1,
            "RunTimeTicks": 27000000000
        }
        """.data(using: .utf8)!
        let dto = try JellyfinJSON.decoder.decode(BaseItemDTO.self, from: json)
        let ep = dto.toEpisode(server: server)
        XCTAssertEqual(ep.seriesId, "series-1")
        XCTAssertEqual(ep.seasonId, "season-1")
        XCTAssertEqual(ep.episodeNumber, 1)
        XCTAssertEqual(ep.seasonNumber, 1)
        XCTAssertEqual(ep.runtimeSeconds, 2700)
    }

    func testPlaybackInfoDirect() throws {
        let json = """
        {
            "MediaSources": [{
                "Id": "src-1",
                "Container": "mp4",
                "SupportsDirectPlay": true,
                "SupportsDirectStream": true,
                "SupportsTranscoding": true,
                "MediaStreams": [
                    {"Index": 0, "Type": "Video", "Codec": "h264", "Profile": "High", "Width": 1920, "Height": 1080, "BitRate": 8000000},
                    {"Index": 1, "Type": "Audio", "Codec": "aac", "Language": "jpn", "Channels": 2, "DisplayTitle": "Japanese AAC 2.0"},
                    {"Index": 2, "Type": "Subtitle", "Codec": "srt", "Language": "jpn", "IsTextSubtitleStream": true, "DisplayTitle": "Japanese"}
                ]
            }],
            "PlaySessionId": "play-abc"
        }
        """.data(using: .utf8)!
        let response = try JellyfinJSON.decoder.decode(PlaybackInfoResponseDTO.self, from: json)
        XCTAssertEqual(response.playSessionId, "play-abc")
        let source = try XCTUnwrap(response.mediaSources?.first)
        XCTAssertEqual(source.supportsDirectPlay, true)
        XCTAssertEqual(source.videoStream?.codec, "h264")
        XCTAssertEqual(source.audioStreams.count, 1)
        XCTAssertEqual(source.subtitleStreams.count, 1)
        let subtitle = source.subtitleStreams[0].toSubtitle()
        XCTAssertFalse(subtitle.isImageBased)
    }

    func testPlaybackInfoTranscodeOnly() throws {
        let json = """
        {
            "MediaSources": [{
                "Id": "src-2",
                "Container": "mkv",
                "SupportsDirectPlay": false,
                "SupportsDirectStream": false,
                "SupportsTranscoding": true,
                "TranscodingUrl": "/videos/abc/main.m3u8?PlaySessionId=xyz",
                "TranscodingSubProtocol": "hls",
                "TranscodingContainer": "ts",
                "MediaStreams": []
            }],
            "PlaySessionId": "play-def"
        }
        """.data(using: .utf8)!
        let response = try JellyfinJSON.decoder.decode(PlaybackInfoResponseDTO.self, from: json)
        let source = try XCTUnwrap(response.mediaSources?.first)
        XCTAssertEqual(source.supportsDirectPlay, false)
        XCTAssertEqual(source.transcodingUrl, "/videos/abc/main.m3u8?PlaySessionId=xyz")
    }

    func testAuthResult() throws {
        let json = """
        {
            "User": {
                "Id": "u1",
                "Name": "Test User",
                "ServerId": "s1",
                "PrimaryImageTag": "primaryTag",
                "Policy": {"IsAdministrator": true, "IsParentalScheduleAllowed": false}
            },
            "AccessToken": "token-abc",
            "ServerId": "s1"
        }
        """.data(using: .utf8)!
        let result = try JellyfinJSON.decoder.decode(AuthenticationResultDTO.self, from: json)
        XCTAssertEqual(result.accessToken, "token-abc")
        let profile = try XCTUnwrap(result.user).toDomain(server: server)
        XCTAssertEqual(profile.id, "u1")
        XCTAssertEqual(profile.name, "Test User")
        XCTAssertTrue(profile.primaryImageURL?.absoluteString.contains("Users/u1/Images/Primary") ?? false)
    }

    func testQuickConnectResult() throws {
        let json = """
        {
            "Authenticated": false,
            "Secret": "s3cr3t",
            "Code": "482913",
            "DeviceId": "dev-abc",
            "DeviceName": "Apple TV",
            "AppName": "Jellyfin-tvOS",
            "AppVersion": "1.0.0",
            "DateAdded": "2026-07-18T10:00:00Z"
        }
        """.data(using: .utf8)!
        let result = try JellyfinJSON.decoder.decode(QuickConnectResultDTO.self, from: json)
        let session = result.toDomain()
        XCTAssertEqual(session.secret, "s3cr3t")
        XCTAssertEqual(session.code, "482913")
        XCTAssertGreaterThan(session.expiresAt.timeIntervalSince1970, 0)
    }

    func testSystemInfo() throws {
        let json = """
        {"LocalAddress":"http://192.168.1.10:8096","ServerName":"Living Room","Version":"10.10.0","Id":"srv-1","StartupWizardCompleted":true}
        """.data(using: .utf8)!
        let info = try JellyfinJSON.decoder.decode(SystemInfoPublicDTO.self, from: json)
        let s = info.toDomain(serverURL: URL(string: "https://jellyfin.example.com")!)
        XCTAssertEqual(s.name, "Living Room")
        XCTAssertEqual(s.version, "10.10.0")
        XCTAssertEqual(s.id, "srv-1")
    }

    func testSearchHint() throws {
        let json = """
        {
            "SearchHints": [
                {"ItemId": "m-1", "Id": "m-1", "Name": "Dark Side of the Moon", "Type": "Movie", "ProductionYear": 2023, "RunTimeTicks": 79200000000, "PrimaryImageTag": "tag"}
            ],
            "TotalRecordCount": 1
        }
        """.data(using: .utf8)!
        let result = try JellyfinJSON.decoder.decode(SearchHintResultDTO.self, from: json)
        let items = result.searchHints.compactMap { $0.toMediaItem(server: server) }
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "Dark Side of the Moon")
        XCTAssertEqual(items[0].kind, .movie)
        XCTAssertEqual(items[0].runtimeSeconds, 7920)
    }
}
