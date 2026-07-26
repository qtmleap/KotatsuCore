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
        XCTAssertTrue(containers.contains("mkv"))

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
        XCTAssertEqual(dp["Name"] as? String, "Jellyfin tvOS")
    }
}
