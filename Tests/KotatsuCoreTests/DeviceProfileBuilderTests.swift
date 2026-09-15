import XCTest
@testable import KotatsuCore

final class DeviceProfileBuilderTests: XCTestCase {

    // MARK: - Generation detection

    func testDetectsAppleTVHD() {
        XCTAssertEqual(DeviceGenerationDetector.detect(identifier: "AppleTV5,3"), .appleTVHD)
    }

    func testDetectsAppleTV4K() {
        XCTAssertEqual(DeviceGenerationDetector.detect(identifier: "AppleTV6,2"), .appleTV4K)
        XCTAssertEqual(DeviceGenerationDetector.detect(identifier: "AppleTV11,1"), .appleTV4K)
        XCTAssertEqual(DeviceGenerationDetector.detect(identifier: "AppleTV14,1"), .appleTV4K)
    }

    func testDetectsSimulator() {
        XCTAssertEqual(DeviceGenerationDetector.detect(identifier: "Simulator(AppleTV6,2)"), .simulator)
    }

    func testDetectsIPad() {
        XCTAssertEqual(DeviceGenerationDetector.detect(identifier: "iPad14,3"), .iPad)
        XCTAssertEqual(DeviceGenerationDetector.detect(identifier: "iPad16,6"), .iPad)
    }

    func testDetectsIPhone() {
        XCTAssertEqual(DeviceGenerationDetector.detect(identifier: "iPhone17,1"), .iPhone)
    }

    /// Regression: iOS identifiers used to fall through to `.unknown`, which
    /// reports `supportsHEVC == false`. Nothing visibly broke — the server just
    /// transcoded HEVC to H.264 for a device that decodes it in hardware, and
    /// capped the result at 1080p / 20 Mbps. Assert the shape of the bug, not
    /// only the fix, so a future `detect` rewrite cannot quietly restore it.
    func testIOSIdentifiersDoNotFallThroughToUnknown() {
        for identifier in ["iPad14,3", "iPhone17,1"] {
            let generation = DeviceGenerationDetector.detect(identifier: identifier)
            if case .unknown = generation {
                XCTFail("\(identifier) fell through to .unknown — HEVC would be disabled")
            }
            XCTAssertTrue(generation.supportsHEVC, "\(identifier) must advertise HEVC")
        }
    }

    // MARK: - Apple TV HD — HEVC MUST NOT appear anywhere

    func testAppleTVHDDirectPlayHasNoHEVC() throws {
        let builder = DeviceProfileBuilder(
            generation: .appleTVHD,
            hardwareHEVC: false,
            deviceName: "Apple TV HD",
            deviceId: "test",
            applicationVersion: "1.0.0"
        )
        let profile = builder.build()

        let directPlay = try XCTUnwrap(profile["DirectPlayProfiles"] as? [[String: Any]])
        let codecs = directPlay.compactMap { $0["VideoCodec"] as? String }
        XCTAssertTrue(codecs.contains("h264"))
        XCTAssertFalse(codecs.contains(where: { $0.lowercased().contains("hevc") }),
                       "Apple TV HD must NOT advertise HEVC direct play")

        let h264Entry = try XCTUnwrap(directPlay.first(where: { ($0["VideoCodec"] as? String) == "h264" }))
        let containers = try XCTUnwrap(h264Entry["Container"] as? String)
        XCTAssertFalse(containers.contains("mkv"), "Apple TV HD should avoid MKV containers")
    }

    func testAppleTVHDCodecProfilesHaveNoHEVC() throws {
        let builder = DeviceProfileBuilder(generation: .appleTVHD, hardwareHEVC: false)
        let profile = builder.build()
        let codecProfiles = try XCTUnwrap(profile["CodecProfiles"] as? [[String: Any]])
        let codecs = codecProfiles.compactMap { $0["Codec"] as? String }
        XCTAssertTrue(codecs.contains("h264"))
        XCTAssertFalse(codecs.contains(where: { $0.lowercased().contains("hevc") }))
    }

    func testAppleTVHDBitrateIsCapped() {
        let builder = DeviceProfileBuilder(generation: .appleTVHD, hardwareHEVC: false)
        let profile = builder.build()
        XCTAssertEqual(profile["MaxStreamingBitrate"] as? Int, 20_000_000)
    }

    func testAppleTVHDResolutionCap() throws {
        let builder = DeviceProfileBuilder(generation: .appleTVHD, hardwareHEVC: false)
        let profile = builder.build()
        let codecProfiles = try XCTUnwrap(profile["CodecProfiles"] as? [[String: Any]])
        let h264 = try XCTUnwrap(codecProfiles.first { ($0["Codec"] as? String) == "h264" })
        let conditions = try XCTUnwrap(h264["Conditions"] as? [[String: Any]])
        let widthCondition = try XCTUnwrap(conditions.first { ($0["Property"] as? String) == "Width" })
        XCTAssertEqual(widthCondition["Value"] as? String, "1920")
    }

    /// Belt-and-braces: even if the machine identifier says 4K, if
    /// `VTIsHardwareDecodeSupported` returned false we must not advertise HEVC.
    func testHardwareCheckOverridesGeneration() throws {
        let builder = DeviceProfileBuilder(generation: .appleTV4K, hardwareHEVC: false)
        XCTAssertFalse(builder.advertisesHEVC)
        let profile = builder.build()
        let directPlay = try XCTUnwrap(profile["DirectPlayProfiles"] as? [[String: Any]])
        let codecs = directPlay.compactMap { $0["VideoCodec"] as? String }
        XCTAssertFalse(codecs.contains(where: { $0.lowercased().contains("hevc") }))
    }

    // MARK: - Apple TV 4K — HEVC 10-bit direct play

    func testAppleTV4KDirectPlayHasHEVC() throws {
        let builder = DeviceProfileBuilder(generation: .appleTV4K, hardwareHEVC: true)
        let profile = builder.build()
        let directPlay = try XCTUnwrap(profile["DirectPlayProfiles"] as? [[String: Any]])
        let codecs = directPlay.compactMap { $0["VideoCodec"] as? String }
        XCTAssertTrue(codecs.contains("h264"))
        XCTAssertTrue(codecs.contains("hevc"))

        let hevcEntry = try XCTUnwrap(directPlay.first(where: { ($0["VideoCodec"] as? String) == "hevc" }))
        let containers = try XCTUnwrap(hevcEntry["Container"] as? String)
        XCTAssertTrue(containers.split(separator: ",").contains("mp4"))
        XCTAssertFalse(containers.split(separator: ",").contains("mkv"))

        let codecProfiles = try XCTUnwrap(profile["CodecProfiles"] as? [[String: Any]])
        let hevcCodec = try XCTUnwrap(codecProfiles.first { ($0["Codec"] as? String) == "hevc" })
        let conditions = try XCTUnwrap(hevcCodec["Conditions"] as? [[String: Any]])
        let profileValues = try XCTUnwrap((conditions.first { ($0["Property"] as? String) == "VideoProfile" })?["Value"] as? String)
        XCTAssertTrue(profileValues.contains("main 10"))
        let bitDepth = try XCTUnwrap((conditions.first { ($0["Property"] as? String) == "VideoBitDepth" })?["Value"] as? String)
        XCTAssertEqual(bitDepth, "10")
        let width = try XCTUnwrap((conditions.first { ($0["Property"] as? String) == "Width" })?["Value"] as? String)
        XCTAssertEqual(width, "3840")
    }

    func testAppleTV4KBitrate() {
        let builder = DeviceProfileBuilder(generation: .appleTV4K, hardwareHEVC: true)
        let profile = builder.build()
        XCTAssertEqual(profile["MaxStreamingBitrate"] as? Int, 80_000_000)
    }

    // MARK: - iPad / iPhone

    func testIPadDirectPlayHasHEVC() throws {
        let builder = DeviceProfileBuilder(generation: .iPad, hardwareHEVC: true)
        XCTAssertTrue(builder.advertisesHEVC)
        let profile = builder.build()

        let directPlay = try XCTUnwrap(profile["DirectPlayProfiles"] as? [[String: Any]])
        let codecs = directPlay.compactMap { $0["VideoCodec"] as? String }
        XCTAssertTrue(codecs.contains("hevc"), "iPad decodes HEVC in hardware")

        let codecProfiles = try XCTUnwrap(profile["CodecProfiles"] as? [[String: Any]])
        let hevc = try XCTUnwrap(codecProfiles.first { ($0["Codec"] as? String) == "hevc" })
        let conditions = try XCTUnwrap(hevc["Conditions"] as? [[String: Any]])
        let width = try XCTUnwrap((conditions.first { ($0["Property"] as? String) == "Width" })?["Value"] as? String)
        XCTAssertEqual(width, "3840")
    }

    func testDirectPlayProfilesNeverAdvertiseMatroska() throws {
        for generation in [
            DeviceGeneration.appleTVHD, .appleTV4K, .iPad, .iPhone, .simulator,
        ] {
            let builder = DeviceProfileBuilder(generation: generation, hardwareHEVC: true)
            XCTAssertFalse(builder.directPlayContainers.contains("mkv"))

            let profile = builder.build()
            let directPlay = try XCTUnwrap(profile["DirectPlayProfiles"] as? [[String: Any]])
            for video in directPlay where video["Type"] as? String == "Video" {
                let containers = try XCTUnwrap(video["Container"] as? String)
                XCTAssertFalse(
                    containers.split(separator: ",").contains("mkv"),
                    "\(generation) must let Jellyfin remux or transcode Matroska")
            }
        }
    }

    func testDirectPlayContainerValidationRejectsMatroska() {
        let builder = DeviceProfileBuilder(generation: .iPad, hardwareHEVC: true)
        XCTAssertTrue(builder.supportsDirectPlay(container: "mp4"))
        XCTAssertTrue(builder.supportsDirectPlay(container: "MP4,m4v"))
        XCTAssertFalse(builder.supportsDirectPlay(container: "mkv"))
        XCTAssertFalse(builder.supportsDirectPlay(container: "matroska"))
    }

    func testIPadHEVCDirectPlayRemainsAvailableInMP4() throws {
        let profile = DeviceProfileBuilder(generation: .iPad, hardwareHEVC: true).build()
        let directPlay = try XCTUnwrap(profile["DirectPlayProfiles"] as? [[String: Any]])
        let hevc = try XCTUnwrap(
            directPlay.first { ($0["VideoCodec"] as? String) == "hevc" })
        let containers = try XCTUnwrap(hevc["Container"] as? String)
        XCTAssertTrue(containers.split(separator: ",").contains("mp4"))
        XCTAssertFalse(containers.split(separator: ",").contains("mkv"))
    }

    func testIPadBitrateMatchesAppleTV4K() {
        // The cap doubles as a direct-play gate: dropping it below the Apple TV
        // figure would transcode high-bitrate files the iPad can play as-is.
        let iPad = DeviceProfileBuilder(generation: .iPad, hardwareHEVC: true)
        let tv = DeviceProfileBuilder(generation: .appleTV4K, hardwareHEVC: true)
        XCTAssertEqual(iPad.maxStreamingBitrate, tv.maxStreamingBitrate)
        XCTAssertEqual(iPad.maxStreamingBitrate, 80_000_000)
    }

    func testIPhoneKeepsHEVCButCapsResolution() {
        let builder = DeviceProfileBuilder(generation: .iPhone, hardwareHEVC: true)
        XCTAssertTrue(builder.advertisesHEVC)
        XCTAssertEqual(builder.maxResolutionWidth, 1920)
        XCTAssertEqual(builder.maxStreamingBitrate, 20_000_000)
    }

    /// The hardware gate applies on iOS exactly as it does on Apple TV.
    func testIOSStillHonoursTheHardwareCheck() {
        XCTAssertFalse(DeviceProfileBuilder(generation: .iPad, hardwareHEVC: false).advertisesHEVC)
    }

    func testDeviceNameDefaultsPerGeneration() {
        XCTAssertEqual(DeviceProfileBuilder(generation: .iPad, hardwareHEVC: true).deviceName, "iPad")
        XCTAssertEqual(DeviceProfileBuilder(generation: .iPhone, hardwareHEVC: true).deviceName, "iPhone")
        XCTAssertEqual(DeviceProfileBuilder(generation: .appleTV4K, hardwareHEVC: true).deviceName, "Apple TV")
        // Apple TV HD shares the label so existing sessions are not renamed.
        XCTAssertEqual(DeviceProfileBuilder(generation: .appleTVHD, hardwareHEVC: false).deviceName, "Apple TV")
    }

    func testExplicitDeviceNameOverridesTheDefault() {
        let builder = DeviceProfileBuilder(generation: .iPad, hardwareHEVC: true, deviceName: "Devon の iPad")
        XCTAssertEqual(builder.deviceName, "Devon の iPad")
    }

    // MARK: - Subtitle profiles

    func testSubtitleProfileMethods() throws {
        let profile = DeviceProfileBuilder(generation: .appleTV4K, hardwareHEVC: true).build()
        let subs = try XCTUnwrap(profile["SubtitleProfiles"] as? [[String: Any]])
        let vtt = try XCTUnwrap(subs.first { ($0["Format"] as? String) == "vtt" })
        XCTAssertEqual(vtt["Method"] as? String, "External")
        let pgs = try XCTUnwrap(subs.first { ($0["Format"] as? String) == "pgssub" })
        XCTAssertEqual(pgs["Method"] as? String, "Encode")
    }

    // MARK: - PlaybackInfo request body

    func testPlaybackInfoBodySerialises() throws {
        let builder = DeviceProfileBuilder(generation: .appleTV4K, hardwareHEVC: true)
        let profile = builder.build()
        let body: [String: Any] = [
            "DeviceProfile": profile,
            "UserId": "u",
            "MaxStreamingBitrate": builder.maxStreamingBitrate,
            "StartTimeTicks": 0,
            "AutoOpenLiveStream": true
        ]
        let data = try JSONSerialization.data(withJSONObject: body, options: [])
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["MaxStreamingBitrate"] as? Int, 80_000_000)
        let dp = try XCTUnwrap(obj["DeviceProfile"] as? [String: Any])
        // Asserted against the builder rather than a literal: the default is
        // platform-derived ("Jellyfin tvOS" / "Jellyfin iOS"), and this suite
        // also runs on macOS. What matters is that it reaches the payload.
        XCTAssertEqual(dp["Name"] as? String, builder.profileName)
    }

    func testExplicitProfileNameReachesTheProfile() {
        let builder = DeviceProfileBuilder(
            generation: .iPad, hardwareHEVC: true, profileName: "Jellyfin iOS")
        XCTAssertEqual(builder.build()["Name"] as? String, "Jellyfin iOS")
    }
}
