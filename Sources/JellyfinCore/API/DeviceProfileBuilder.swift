import Foundation
#if canImport(VideoToolbox)
import VideoToolbox
#endif
#if canImport(CoreMedia)
import CoreMedia
#endif

/// Detected Apple TV generation used to shape the DeviceProfile sent to
/// Jellyfin's `/Items/{id}/PlaybackInfo` endpoint.
///
/// This is deliberately conservative:
///
/// * `.appleTVHD` (Apple TV HD / A8, `AppleTV5,3`) has NO hardware HEVC
///   decoder. Advertising HEVC direct play here causes green-screen / audio-
///   only playback because the A8 CPU cannot software-decode 1080p HEVC in
///   real time. This is exactly the bug that plagues Swiftfin on Apple TV HD.
///
/// * `.appleTV4K` (`AppleTV6,2` and later — A10X, A12, A15, ...) has full
///   HEVC 10-bit and (on newer models) Dolby Vision support. Direct play up
///   to 4K HEVC Main10 is safe.
///
/// * `.simulator` and `.unknown` fall through the same "assume the worst"
///   path as the A8 to avoid surprises. Simulators cannot decode HEVC via
///   VideoToolbox in the same way real hardware does.
public enum AppleTVGeneration: Sendable, Equatable {
    case appleTVHD          // AppleTV5,3 – A8
    case appleTV4K          // AppleTV6,2, AppleTV11,1 and newer
    case simulator
    case unknown(String)

    public var supportsHEVC: Bool {
        switch self {
        case .appleTV4K: return true
        case .appleTVHD, .simulator, .unknown: return false
        }
    }

    /// Maximum streaming bitrate to advertise to the server in bits/second.
    /// Kept conservative: even on 4K we cap around 80 Mbps so the server
    /// picks a sane transcode target when direct play cannot happen.
    public var maxStreamingBitrate: Int {
        switch self {
        case .appleTV4K: return 80_000_000
        case .appleTVHD, .simulator, .unknown: return 20_000_000
        }
    }

    /// Maximum resolution (long edge) we want to receive.
    public var maxResolutionWidth: Int {
        switch self {
        case .appleTV4K: return 3840
        case .appleTVHD, .simulator, .unknown: return 1920
        }
    }
}

public enum DeviceGenerationDetector {
    /// Read `hw.machine` (real hardware) or fall back to `hw.model` (simulator).
    public static func machineIdentifier() -> String {
        var size: size_t = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        if size > 0 {
            var buffer = [UInt8](repeating: 0, count: size)
            buffer.withUnsafeMutableBytes { rawBuffer in
                _ = sysctlbyname("hw.machine", rawBuffer.baseAddress, &size, nil, 0)
            }
            // Trim trailing null bytes.
            if let end = buffer.firstIndex(of: 0) {
                buffer.removeSubrange(end..<buffer.count)
            }
            let identifier = String(decoding: buffer, as: UTF8.self)
            if !identifier.isEmpty { return identifier }
        }
        // Simulator path.
        if let simModel = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return "Simulator(\(simModel))"
        }
        return "Unknown"
    }

    public static func detect(identifier: String = machineIdentifier()) -> AppleTVGeneration {
        if identifier.hasPrefix("Simulator") { return .simulator }
        // Real Apple TV identifiers
        // AppleTV5,3 = Apple TV HD (A8, 2015)
        // AppleTV6,2 = Apple TV 4K 1st gen (A10X, 2017)
        // AppleTV11,1 = Apple TV 4K 2nd gen (A12, 2021)
        // AppleTV14,1 = Apple TV 4K 3rd gen (A15, 2022)
        if identifier == "AppleTV5,3" { return .appleTVHD }
        if identifier.hasPrefix("AppleTV") {
            // Any AppleTVN,X where N >= 6 is a 4K model.
            let stripped = identifier.dropFirst("AppleTV".count)
            let major = stripped.split(separator: ",").first.map { String($0) } ?? ""
            if let n = Int(major), n >= 6 { return .appleTV4K }
        }
        return .unknown(identifier)
    }

    /// Runtime check that the hardware actually reports a HEVC decoder.
    /// Combined with the machine ID this is our belt-and-braces defence
    /// against advertising direct play on hardware that will fall back to
    /// software decoding.
    public static func hardwareSupportsHEVC() -> Bool {
        #if canImport(VideoToolbox) && canImport(CoreMedia)
        if #available(tvOS 11.0, iOS 11.0, macOS 10.13, *) {
            return VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
        }
        return false
        #else
        return false
        #endif
    }
}

/// Builds a DeviceProfile dictionary that mirrors the schema Jellyfin expects
/// at `/Items/{id}/PlaybackInfo`. Output is a plain `[String: Any]` because
/// the Jellyfin schema is large and mostly optional; sending only the fields
/// we care about is intentional.
public struct DeviceProfileBuilder: Sendable {
    public var generation: AppleTVGeneration
    /// Runtime VideoToolbox HEVC check result. Injectable for tests.
    public var hardwareHEVC: Bool
    public var deviceName: String
    public var deviceId: String
    public var applicationVersion: String

    public init(
        generation: AppleTVGeneration = DeviceGenerationDetector.detect(),
        hardwareHEVC: Bool = DeviceGenerationDetector.hardwareSupportsHEVC(),
        deviceName: String = "Apple TV",
        deviceId: String = DeviceProfileBuilder.persistentDeviceId(),
        applicationVersion: String = "1.0.0"
    ) {
        self.generation = generation
        self.hardwareHEVC = hardwareHEVC
        self.deviceName = deviceName
        self.deviceId = deviceId
        self.applicationVersion = applicationVersion
    }

    /// A stable device identifier persisted in UserDefaults. Jellyfin uses
    /// this for session tracking and "This device" style UI in the server
    /// dashboard.
    public static func persistentDeviceId() -> String {
        let key = "app.jellyfin.tvos.deviceId"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }

    /// Final HEVC gate — both the machine ID AND the VideoToolbox check must
    /// agree. Belt AND braces.
    public var advertisesHEVC: Bool { generation.supportsHEVC && hardwareHEVC }

    public var maxStreamingBitrate: Int { generation.maxStreamingBitrate }
    public var maxResolutionWidth: Int { generation.maxResolutionWidth }

    // MARK: - Build

    public func build() -> [String: Any] {
        var profile: [String: Any] = [
            "Name": "Jellyfin tvOS",
            "MaxStreamingBitrate": maxStreamingBitrate,
            "MaxStaticBitrate": maxStreamingBitrate,
            "MusicStreamingTranscodingBitrate": 384_000,
            "TimelineOffsetSeconds": 5,
            "TranscodingProfiles": transcodingProfiles(),
            "DirectPlayProfiles": directPlayProfiles(),
            "ContainerProfiles": [],
            "CodecProfiles": codecProfiles(),
            "SubtitleProfiles": subtitleProfiles(),
            "ResponseProfiles": [],
        ]
        // Some server versions want this alias too.
        profile["MaxStreamingBitrate"] = maxStreamingBitrate
        return profile
    }

    // MARK: - DirectPlayProfiles

    private func directPlayProfiles() -> [[String: Any]] {
        var profiles: [[String: Any]] = []

        // H.264 / AVC direct play — always supported.
        let h264Containers = advertisesHEVC ? "mp4,m4v,mov,mkv,ts" : "mp4,m4v,mov,ts"
        profiles.append([
            "Type": "Video",
            "Container": h264Containers,
            "VideoCodec": "h264",
            "AudioCodec": "aac,mp3,ac3,eac3"
        ])

        // HEVC direct play — 4K models only.
        if advertisesHEVC {
            profiles.append([
                "Type": "Video",
                "Container": "mp4,m4v,mov,mkv,ts",
                "VideoCodec": "hevc",
                // FLAC/ALAC/OPUS only on newer OS; tvOS AVPlayer handles all
                // of these since tvOS 11.
                "AudioCodec": "aac,mp3,ac3,eac3,flac,alac,opus"
            ])
        }

        // Audio-only.
        profiles.append([
            "Type": "Audio",
            "Container": "mp3,aac,m4a,m4b,flac,alac,wav,mp4"
        ])

        return profiles
    }

    // MARK: - CodecProfiles

    /// Constraints Jellyfin uses to decide whether direct play is actually
    /// possible for a given media source. These are the guardrails that
    /// prevent the server from handing us content the hardware can't decode.
    private func codecProfiles() -> [[String: Any]] {
        var profiles: [[String: Any]] = []

        // H.264 constraints: Main / High profile, up to Level 4.2 on A8
        // (1080p60), Level 5.1 on 4K models (4K30 in H.264).
        let h264Level = advertisesHEVC ? "51" : "42"
        profiles.append([
            "Type": "Video",
            "Codec": "h264",
            "Conditions": [
                [
                    "Condition": "NotEquals",
                    "Property": "IsAnamorphic",
                    "Value": "true",
                    "IsRequired": false
                ],
                [
                    "Condition": "EqualsAny",
                    "Property": "VideoProfile",
                    "Value": "high|main|baseline|constrained baseline",
                    "IsRequired": false
                ],
                [
                    "Condition": "LessThanEqual",
                    "Property": "VideoLevel",
                    "Value": h264Level,
                    "IsRequired": false
                ],
                [
                    "Condition": "LessThanEqual",
                    "Property": "Width",
                    "Value": "\(maxResolutionWidth)",
                    "IsRequired": false
                ],
                [
                    "Condition": "LessThanEqual",
                    "Property": "VideoBitDepth",
                    "Value": "8",
                    "IsRequired": false
                ],
            ]
        ])

        if advertisesHEVC {
            profiles.append([
                "Type": "Video",
                "Codec": "hevc",
                "Conditions": [
                    [
                        "Condition": "NotEquals",
                        "Property": "IsAnamorphic",
                        "Value": "true",
                        "IsRequired": false
                    ],
                    [
                        "Condition": "EqualsAny",
                        "Property": "VideoProfile",
                        "Value": "main|main 10",
                        "IsRequired": false
                    ],
                    [
                        "Condition": "LessThanEqual",
                        "Property": "VideoLevel",
                        "Value": "153", // HEVC L5.1 (5*30 + 3 = 153) — 4K60
                        "IsRequired": false
                    ],
                    [
                        "Condition": "LessThanEqual",
                        "Property": "Width",
                        "Value": "\(maxResolutionWidth)",
                        "IsRequired": false
                    ],
                    [
                        "Condition": "LessThanEqual",
                        "Property": "VideoBitDepth",
                        "Value": "10",
                        "IsRequired": false
                    ],
                ]
            ])
        }
        // NOTE: We intentionally do NOT add profiles for AV1 or VP9 —
        // tvOS AVPlayer does not hardware-decode them on any current
        // Apple TV. Jellyfin will then transcode as needed.

        return profiles
    }

    // MARK: - TranscodingProfiles

    private func transcodingProfiles() -> [[String: Any]] {
        var profiles: [[String: Any]] = []

        // HLS + H.264/AAC — universally safe fallback.
        profiles.append([
            "Type": "Video",
            "Container": "ts",
            "Protocol": "hls",
            "VideoCodec": "h264",
            "AudioCodec": "aac,mp3,ac3,eac3",
            "Context": "Streaming",
            "EstimateContentLength": false,
            "EnableMpegtsM2TsMode": false,
            "TranscodeSeekInfo": "Auto",
            "CopyTimestamps": false,
            "MinSegments": 2,
            "BreakOnNonKeyFrames": true,
            "MaxAudioChannels": "6"
        ])

        // HEVC transcode target for 4K models only — cheaper on bandwidth
        // when the server has HEVC encoding available.
        if advertisesHEVC {
            profiles.append([
                "Type": "Video",
                "Container": "ts",
                "Protocol": "hls",
                "VideoCodec": "hevc,h264",
                "AudioCodec": "aac,mp3,ac3,eac3,flac,alac",
                "Context": "Streaming",
                "EstimateContentLength": false,
                "EnableMpegtsM2TsMode": false,
                "TranscodeSeekInfo": "Auto",
                "CopyTimestamps": false,
                "MinSegments": 2,
                "BreakOnNonKeyFrames": true,
                "MaxAudioChannels": "6"
            ])
        }

        // Music transcode fallback.
        profiles.append([
            "Type": "Audio",
            "Container": "aac",
            "AudioCodec": "aac",
            "Context": "Streaming",
            "Protocol": "http"
        ])

        return profiles
    }

    // MARK: - SubtitleProfiles

    private func subtitleProfiles() -> [[String: Any]] {
        // AVPlayer handles WebVTT natively via HLS sidecar tracks; text-based
        // subs (srt, ass, ssa) get converted to VTT by the server. Image-based
        // subs (PGS, DVBSUB, DVDSUB) require burn-in.
        return [
            ["Format": "vtt", "Method": "External"],
            ["Format": "vtt", "Method": "Hls"],
            ["Format": "srt", "Method": "External"],
            ["Format": "ass", "Method": "Encode"],
            ["Format": "ssa", "Method": "Encode"],
            ["Format": "pgssub", "Method": "Encode"],
            ["Format": "dvbsub", "Method": "Encode"],
            ["Format": "dvdsub", "Method": "Encode"],
        ]
    }
}
