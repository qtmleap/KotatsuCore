import Foundation
#if canImport(VideoToolbox)
import VideoToolbox
#endif
#if canImport(CoreMedia)
import CoreMedia
#endif

/// Detected hardware family used to shape the DeviceProfile sent to
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
/// * `.iPad` / `.iPhone` always decode HEVC in silicon. The deployment target
///   is iOS 26, which no A8/A9/A10 device can run, so there is no Apple-TV-HD
///   shaped trap on this side — every iOS device that can install the app has
///   a hardware HEVC decoder. Letting them fall through to `.unknown` instead
///   is a silent regression rather than a visible one: playback still works,
///   but the server burns CPU on a pointless H.264 transcode and caps the
///   result at 1080p / 20 Mbps.
///
/// * `.simulator` and `.unknown` fall through the same "assume the worst"
///   path as the A8 to avoid surprises. Simulators cannot decode HEVC via
///   VideoToolbox in the same way real hardware does.
public enum DeviceGeneration: Sendable, Equatable {
    case appleTVHD          // AppleTV5,3 – A8
    case appleTV4K          // AppleTV6,2, AppleTV11,1 and newer
    case iPad               // iPadN,X running iOS 26 — A12 or newer
    case iPhone             // iPhoneN,X running iOS 26 — A13 or newer
    case simulator
    case unknown(String)

    public var supportsHEVC: Bool {
        switch self {
        case .appleTV4K, .iPad, .iPhone: return true
        case .appleTVHD, .simulator, .unknown: return false
        }
    }

    /// Maximum streaming bitrate to advertise to the server in bits/second.
    /// Kept conservative: even on 4K we cap around 80 Mbps so the server
    /// picks a sane transcode target when direct play cannot happen.
    ///
    /// iPad sits at the Apple TV 4K figure on purpose. This number doubles as
    /// a direct-play gate — a file above the cap gets transcoded even when the
    /// codec itself is supported — so lowering it "to be kind to the battery"
    /// would hand back the very transcode this type exists to avoid. iPhone is
    /// capped lower because a 1080p-class panel cannot show the difference.
    public var maxStreamingBitrate: Int {
        switch self {
        case .appleTV4K, .iPad: return 80_000_000
        case .iPhone: return 20_000_000
        case .appleTVHD, .simulator, .unknown: return 20_000_000
        }
    }

    /// Maximum resolution (long edge) we want to receive.
    public var maxResolutionWidth: Int {
        switch self {
        case .appleTV4K, .iPad: return 3840
        case .iPhone: return 1920
        case .appleTVHD, .simulator, .unknown: return 1920
        }
    }

    /// Label sent as `Device=` in the Jellyfin auth header — the name the
    /// server dashboard shows for this session.
    ///
    /// Both Apple TV models deliberately share one label. Every existing
    /// install has already registered itself as "Apple TV", and splitting the
    /// label by generation would rename all of those sessions in place for no
    /// functional gain.
    public var defaultDeviceName: String {
        switch self {
        case .appleTVHD, .appleTV4K: return "Apple TV"
        case .iPad: return "iPad"
        case .iPhone: return "iPhone"
        case .simulator, .unknown:
            #if os(tvOS)
            return "Apple TV"
            #elseif os(iOS)
            return "iOS Device"
            #else
            return "Apple Device"
            #endif
        }
    }
}

@available(*, deprecated, renamed: "DeviceGeneration")
public typealias AppleTVGeneration = DeviceGeneration

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

    public static func detect(identifier: String = machineIdentifier()) -> DeviceGeneration {
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
        // iOS hardware. No generation gate is needed the way it is on Apple TV:
        // the iOS 26 deployment target already excludes every model that lacks
        // a hardware HEVC decoder, so anything reaching this line can decode it.
        // `hardwareSupportsHEVC()` still has the final say in `advertisesHEVC`.
        if identifier.hasPrefix("iPad") { return .iPad }
        if identifier.hasPrefix("iPhone") { return .iPhone }
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
    public var generation: DeviceGeneration
    /// Runtime VideoToolbox HEVC check result. Injectable for tests.
    public var hardwareHEVC: Bool
    public var deviceName: String
    public var deviceId: String
    public var applicationVersion: String
    /// The DeviceProfile's `Name`, which is how the server labels this client
    /// in its playback logs.
    public var profileName: String

    public init(
        generation: DeviceGeneration = DeviceGenerationDetector.detect(),
        hardwareHEVC: Bool = DeviceGenerationDetector.hardwareSupportsHEVC(),
        deviceName: String? = nil,
        deviceId: String = DeviceProfileBuilder.persistentDeviceId(),
        applicationVersion: String = "1.0.0",
        profileName: String = DeviceProfileBuilder.defaultProfileName
    ) {
        self.generation = generation
        self.hardwareHEVC = hardwareHEVC
        self.deviceName = deviceName ?? generation.defaultDeviceName
        self.deviceId = deviceId
        self.applicationVersion = applicationVersion
        self.profileName = profileName
    }

    /// Default DeviceProfile `Name` for the running build.
    ///
    /// The compile-time platform is the right signal here, and the only place
    /// in this type where it is. HEVC support depends on the actual silicon and
    /// so has to be sniffed at runtime; which OS the binary targets is settled
    /// at build time and stays correct in the simulator, where `hw.machine`
    /// reports the host Mac rather than the simulated device.
    public static var defaultProfileName: String {
        #if os(tvOS)
        return "Jellyfin tvOS"
        #elseif os(iOS)
        return "Jellyfin iOS"
        #else
        return "Jellyfin"
        #endif
    }

    /// A stable device identifier persisted in UserDefaults. Jellyfin uses
    /// this for session tracking and "This device" style UI in the server
    /// dashboard.
    ///
    /// The key still says `tvos` for a reason: changing it would orphan the
    /// identifier every existing Apple TV install has already registered, and
    /// each one would reappear in the server dashboard as a second device. The
    /// iOS build gets its own value regardless — app containers do not share
    /// UserDefaults — so there is nothing to disambiguate here.
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

    // MARK: - Public capability views

    /// Video codecs this client will Direct Play without asking the server
    /// to transcode. HEVC is added only when the machine ID + the runtime
    /// VideoToolbox check both confirm hardware decode.
    public var directPlayVideoCodecs: [String] {
        var out = ["h264"]
        if advertisesHEVC { out.append("hevc") }
        return out
    }

    /// Audio codecs paired with the above video codecs.
    public var directPlayAudioCodecs: [String] {
        advertisesHEVC
            ? ["aac", "mp3", "ac3", "eac3", "flac", "alac", "opus"]
            : ["aac", "mp3", "ac3", "eac3"]
    }

    /// Containers AVPlayer can consume directly. Matroska is intentionally
    /// absent even when the device decodes HEVC: AVFoundation supports the
    /// codec in MP4-family containers, but not the MKV container itself.
    public var directPlayContainers: [String] {
        ["mp4", "m4v", "mov", "ts"]
    }

    /// Subtitle formats declared in the DeviceProfile paired with the method
    /// AVPlayer needs (external sidecar / HLS in-band / server-side burn-in).
    public var subtitleSupport: [SubtitleProfileDescriptor] {
        [
            .init(format: "vtt", method: .external),
            .init(format: "vtt", method: .hls),
            .init(format: "srt", method: .external),
            .init(format: "ass", method: .encode),
            .init(format: "ssa", method: .encode),
            .init(format: "pgssub", method: .encode),
            .init(format: "dvbsub", method: .encode),
            .init(format: "dvdsub", method: .encode),
        ]
    }

    // MARK: - Build

    public func build() -> [String: Any] {
        var profile: [String: Any] = [
            "Name": profileName,
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
        let videoContainers = directPlayContainers.joined(separator: ",")
        profiles.append([
            "Type": "Video",
            "Container": videoContainers,
            "VideoCodec": "h264",
            "AudioCodec": "aac,mp3,ac3,eac3"
        ])

        // HEVC direct play — Apple TV 4K, iPad and iPhone.
        if advertisesHEVC {
            profiles.append([
                "Type": "Video",
                "Container": videoContainers,
                "VideoCodec": "hevc",
                // FLAC/ALAC/OPUS only on newer OS; AVPlayer handles all of
                // these since tvOS 11 / iOS 11.
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
        // (1080p60), Level 5.1 everywhere else (4K30 in H.264).
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
        // NOTE: We intentionally do NOT add profiles for AV1 or VP9. No
        // current Apple TV hardware-decodes either, and the iOS models that
        // do (A17 Pro / M3 and later, AV1 only) are too narrow a slice to
        // advertise from a static profile. Jellyfin transcodes as needed.

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

        // HEVC transcode target for HEVC-capable devices — cheaper on
        // bandwidth when the server has HEVC encoding available.
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

/// A single row in `DeviceProfileBuilder.subtitleSupport` — the subtitle
/// format we advertise plus the delivery method AVPlayer needs for it.
public struct SubtitleProfileDescriptor: Sendable, Hashable {
    public enum Method: String, Sendable, Hashable {
        case external = "External"
        case hls = "Hls"
        case encode = "Encode"

        public var displayName: String {
            switch self {
            case .external: return "外部"
            case .hls: return "HLS"
            case .encode: return "焼き込み"
            }
        }
    }
    public let format: String
    public let method: Method
    public init(format: String, method: Method) {
        self.format = format
        self.method = method
    }
}
