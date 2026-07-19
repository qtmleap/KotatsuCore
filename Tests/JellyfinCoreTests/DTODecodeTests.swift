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
                "Policy": {"IsAdministrator": true, "MaxParentalRating": null, "AccessSchedules": []}
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

    // MARK: - HDR / bit-depth / spatial fields on MediaStreamDTO

    /// Shape lifted from a real 10.11 response (2001年宇宙の旅). SDR content
    /// should decode with `videoRangeType == "SDR"` and NOT be flagged HDR.
    func testMediaStreamSDR8Bit() throws {
        let json = """
        {
            "MediaSources": [{
                "Id": "src",
                "Container": "mkv",
                "SupportsDirectPlay": true,
                "SupportsDirectStream": true,
                "MediaStreams": [
                    {
                        "Index": 0, "Type": "Video", "Codec": "hevc", "Profile": "Main",
                        "Width": 1920, "Height": 872, "BitRate": 2480882,
                        "ColorRange": "tv", "ColorSpace": "bt709",
                        "ColorTransfer": "bt709", "ColorPrimaries": "bt709",
                        "BitDepth": 8, "PixelFormat": "yuv420p",
                        "VideoRange": "SDR", "VideoRangeType": "SDR",
                        "Level": 120, "AverageFrameRate": 23.976025,
                        "DisplayTitle": "1080p HEVC SDR"
                    }
                ]
            }]
        }
        """.data(using: .utf8)!
        let response = try JellyfinJSON.decoder.decode(PlaybackInfoResponseDTO.self, from: json)
        let source = try XCTUnwrap(response.mediaSources?.first).toDomain()
        XCTAssertEqual(source.videoRangeType, "SDR")
        XCTAssertEqual(source.bitDepth, 8)
        XCTAssertEqual(source.frameRate ?? 0, 23.976025, accuracy: 0.0001)
        XCTAssertEqual(source.colorSpace, "bt709")
        XCTAssertEqual(source.pixelFormat, "yuv420p")
        XCTAssertFalse(source.isHDR, "SDR must not raise the HDR badge")
    }

    /// HDR10 10bit — HEVC Main 10 with bt2020. Should flag isHDR true.
    func testMediaStreamHDR10() throws {
        let json = """
        {
            "MediaSources": [{
                "Id": "src",
                "Container": "mkv",
                "MediaStreams": [
                    {
                        "Index": 0, "Type": "Video", "Codec": "hevc", "Profile": "Main 10",
                        "Width": 3840, "Height": 2160, "BitRate": 40000000,
                        "ColorSpace": "bt2020nc", "ColorTransfer": "smpte2084",
                        "ColorPrimaries": "bt2020", "BitDepth": 10,
                        "PixelFormat": "yuv420p10le",
                        "VideoRange": "HDR", "VideoRangeType": "HDR10",
                        "Level": 153, "AverageFrameRate": 23.976
                    }
                ]
            }]
        }
        """.data(using: .utf8)!
        let response = try JellyfinJSON.decoder.decode(PlaybackInfoResponseDTO.self, from: json)
        let source = try XCTUnwrap(response.mediaSources?.first).toDomain()
        XCTAssertEqual(source.videoRangeType, "HDR10")
        XCTAssertEqual(source.bitDepth, 10)
        XCTAssertEqual(source.videoLevel, 153)
        XCTAssertTrue(source.isHDR)
    }

    /// Dolby Vision Profile 7 dual-layer (DOVIWithHDR10) + Dolby Atmos audio.
    func testMediaStreamDoViWithAtmos() throws {
        let json = """
        {
            "MediaSources": [{
                "Id": "src",
                "Container": "mkv",
                "MediaStreams": [
                    {
                        "Index": 0, "Type": "Video", "Codec": "hevc", "Profile": "Main 10",
                        "Width": 3840, "Height": 2160, "BitDepth": 10,
                        "VideoRange": "HDR", "VideoRangeType": "DOVIWithHDR10"
                    },
                    {
                        "Index": 1, "Type": "Audio", "Codec": "eac3",
                        "Language": "eng", "Channels": 6,
                        "DisplayTitle": "English E-AC3 5.1",
                        "AudioSpatialFormat": "DolbyAtmos"
                    }
                ]
            }]
        }
        """.data(using: .utf8)!
        let response = try JellyfinJSON.decoder.decode(PlaybackInfoResponseDTO.self, from: json)
        let source = try XCTUnwrap(response.mediaSources?.first).toDomain()
        XCTAssertTrue(source.isHDR)
        XCTAssertEqual(source.videoRangeType, "DOVIWithHDR10")
        XCTAssertEqual(source.audioTracks.first?.spatialFormat, "DolbyAtmos")
    }

    /// `AudioSpatialFormat: "None"` should be dropped, not surfaced as a badge.
    func testAudioSpatialFormatNoneDropped() throws {
        let json = """
        {
            "MediaSources": [{
                "Id": "src",
                "MediaStreams": [
                    {
                        "Index": 1, "Type": "Audio", "Codec": "aac",
                        "Language": "jpn", "Channels": 2,
                        "AudioSpatialFormat": "None"
                    }
                ]
            }]
        }
        """.data(using: .utf8)!
        let response = try JellyfinJSON.decoder.decode(PlaybackInfoResponseDTO.self, from: json)
        let source = try XCTUnwrap(response.mediaSources?.first).toDomain()
        XCTAssertNil(source.audioTracks.first?.spatialFormat, "\"None\" should not surface as a spatial marker")
    }

    // MARK: - Bug fixes verified with real-server-shape fixtures

    /// Jellyfin returns `Taglines: [String]` (plural, array), not `Tagline`.
    /// This fixture mirrors the shape of the movie sample fetched from
    /// jellyfin.tkgstrator.work/10.11.11.
    func testTaglinesPluralField() throws {
        let json = """
        {
            "Id": "abc",
            "Name": "2001: A Space Odyssey",
            "Type": "Movie",
            "Taglines": ["それは、未だ究極の旅"]
        }
        """.data(using: .utf8)!
        let dto = try JellyfinJSON.decoder.decode(BaseItemDTO.self, from: json)
        XCTAssertEqual(dto.taglines, ["それは、未だ究極の旅"])
        let detail = dto.toDetail(server: server)
        XCTAssertEqual(detail.tagline, "それは、未だ究極の旅")
    }

    func testTaglinesEmptyAndMissing() throws {
        // Missing field → nil array; downstream tagline becomes nil.
        let missing = try JellyfinJSON.decoder.decode(BaseItemDTO.self, from: Data("""
        {"Id": "a", "Name": "x", "Type": "Movie"}
        """.utf8))
        XCTAssertNil(missing.taglines)
        XCTAssertNil(missing.toDetail(server: server).tagline)

        // Explicit empty array → detail tagline nil, not crash.
        let empty = try JellyfinJSON.decoder.decode(BaseItemDTO.self, from: Data("""
        {"Id": "a", "Name": "x", "Type": "Movie", "Taglines": []}
        """.utf8))
        XCTAssertEqual(empty.taglines, [])
        XCTAssertNil(empty.toDetail(server: server).tagline)
    }

    /// `IsParentalScheduleAllowed` does not exist in Jellyfin OpenAPI. Parental
    /// controls are inferred from `MaxParentalRating` and `AccessSchedules`.
    func testUserPolicyParentalControlsSchedule() throws {
        let json = """
        {
            "IsAdministrator": false,
            "AccessSchedules": [{"DayOfWeek": "Everyday", "StartHour": 16.0, "EndHour": 20.0}]
        }
        """.data(using: .utf8)!
        let policy = try JellyfinJSON.decoder.decode(UserPolicyDTO.self, from: json)
        XCTAssertTrue(policy.hasParentalControls, "schedule present → parental controls active")
    }

    func testUserPolicyParentalControlsMaxRating() throws {
        let json = """
        {"IsAdministrator": false, "MaxParentalRating": 12, "AccessSchedules": []}
        """.data(using: .utf8)!
        let policy = try JellyfinJSON.decoder.decode(UserPolicyDTO.self, from: json)
        XCTAssertTrue(policy.hasParentalControls, "max rating set → parental controls active")
    }

    func testUserPolicyParentalControlsNone() throws {
        let json = """
        {"IsAdministrator": true, "AccessSchedules": []}
        """.data(using: .utf8)!
        let policy = try JellyfinJSON.decoder.decode(UserPolicyDTO.self, from: json)
        XCTAssertFalse(policy.hasParentalControls, "no schedule / no rating → no parental controls")
    }

    /// Real `/System/Info` reponses from 10.11 have no `WanAddress`. Ensure
    /// the DTO decodes cleanly without the removed field.
    func testSystemInfoDecodesWithoutWanAddress() throws {
        let json = """
        {
            "LocalAddress": "http://172.29.0.3:8096",
            "ServerName": "DXP4800",
            "Version": "10.11.11",
            "ProductName": "Jellyfin Server",
            "Id": "85b08f3cd6b2427c96e143b55d7dfc9f",
            "HasPendingRestart": false,
            "HasUpdateAvailable": false,
            "CachePath": "/cache",
            "LogPath": "/config/log",
            "InternalMetadataPath": "/config/metadata",
            "TranscodingTempPath": "/cache/transcodes"
        }
        """.data(using: .utf8)!
        let dto = try JellyfinJSON.decoder.decode(SystemInfoDTO.self, from: json)
        let info = dto.toDomain()
        XCTAssertEqual(info.serverName, "DXP4800")
        XCTAssertEqual(info.version, "10.11.11")
        XCTAssertEqual(info.localAddress, "http://172.29.0.3:8096")
    }

    // MARK: - MediaSource parsing (from filename markers)

    func testMediaSourceDetectPrimeVideo() throws {
        let src = MediaSource.detect(fromPath: "/media/movies/Some Movie [AP][1080p].mkv")
        XCTAssertEqual(src, .primeVideo)
    }

    func testMediaSourceDetectBluRay() throws {
        let src = MediaSource.detect(fromPath: "/media/anime/Season 01 [BD]/E01.mkv")
        XCTAssertEqual(src, .bluRay)
    }

    func testMediaSourceDetectCrunchyroll() throws {
        let src = MediaSource.detect(fromPath: "Some Show [CR][WEBRip][1080p].mkv")
        XCTAssertEqual(src, .crunchyroll)
    }

    func testMediaSourceIgnoresUnknownMarker() throws {
        let src = MediaSource.detect(fromPath: "Random Movie [XX][720p].mp4")
        XCTAssertNil(src)
    }

    func testMediaSourceIgnoresPlainFilename() throws {
        XCTAssertNil(MediaSource.detect(fromPath: "movie.mkv"))
    }

    func testBaseItemDTOMediaItemPopulatesDistributionSource() throws {
        let json = """
        {
            "Id": "movie-1",
            "Name": "Sample",
            "Type": "Movie",
            "Path": "/data/movies/Sample [AP][1080p].mkv"
        }
        """.data(using: .utf8)!
        let dto = try JellyfinJSON.decoder.decode(BaseItemDTO.self, from: json)
        let item = dto.toMediaItem(server: server)
        XCTAssertEqual(item.distributionSource, .primeVideo)
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
