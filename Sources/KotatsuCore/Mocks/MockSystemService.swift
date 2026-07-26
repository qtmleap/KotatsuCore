import Foundation

public actor MockSystemService: SystemService {
    public init() {}

    public func fetchSystemInfo() async throws -> SystemInfo {
        SystemInfo(
            serverName: "Home Jellyfin",
            version: "10.10.6",
            productName: "Jellyfin Server",
            operatingSystem: "Linux",
            operatingSystemDisplayName: "Ubuntu 24.04",
            localAddress: "http://192.168.1.20:8096",
            hasUpdateAvailable: false,
            hasPendingRestart: false,
            cachePath: "/var/cache/jellyfin",
            logPath: "/var/log/jellyfin",
            transcodingTempPath: "/tmp/jellyfin-transcode",
            internalMetadataPath: "/var/lib/jellyfin/metadata"
        )
    }

    public func fetchEncodingConfiguration() async throws -> EncodingConfiguration {
        EncodingConfiguration(
            hardwareAccelerationType: "vaapi",
            encoderAppPath: "/usr/lib/jellyfin-ffmpeg/ffmpeg",
            encoderAppPathDisplay: "jellyfin-ffmpeg 7.0.2-4",
            vaapiDevice: "/dev/dri/renderD128",
            qsvDevice: nil,
            enableHardwareEncoding: true,
            allowHevcEncoding: true,
            allowAv1Encoding: false,
            enableTonemapping: true,
            enableVppTonemapping: true,
            enableVideoToolboxTonemapping: nil,
            hardwareDecodingCodecs: ["h264", "hevc", "vp9", "av1"],
            h264Crf: 23,
            h265Crf: 28,
            encoderPreset: "auto",
            deinterlaceMethod: "yadif",
            deinterlaceDoubleRate: false,
            enableThrottling: true,
            throttleDelaySeconds: 180,
            enableSegmentDeletion: true,
            segmentKeepSeconds: 720,
            transcodingTempPath: "/tmp/jellyfin-transcode",
            fallbackFontPath: nil,
            enableSubtitleExtraction: true,
            enableAudioVbr: false,
            enableIntelLowPowerH264HwEncoder: false,
            enableIntelLowPowerHevcHwEncoder: false,
            enableDecodingColorDepth10Hevc: true,
            enableDecodingColorDepth10Vp9: true,
            preferSystemNativeHwDecoder: true
        )
    }

    public func fetchActiveSessions() async throws -> [ActiveSession] {
        [
            ActiveSession(
                id: "sess-1",
                userName: "とおる",
                deviceName: "Apple TV HD",
                client: "Jellyfin-tvOS",
                applicationVersion: "1.0.0",
                remoteEndpoint: "192.168.1.30",
                lastActivityDate: Date(),
                nowPlaying: SessionNowPlaying(
                    itemId: "item-1",
                    itemName: "Witch Hat Atelier S1E4",
                    seriesName: "Witch Hat Atelier",
                    mediaType: "Video",
                    positionSeconds: 640,
                    runtimeSeconds: 1440,
                    isPaused: false,
                    playMethod: .transcode,
                    transcode: TranscodeInfo(
                        audioCodec: "aac",
                        videoCodec: "h264",
                        container: "ts",
                        isVideoDirect: false,
                        isAudioDirect: false,
                        bitrate: 8_000_000,
                        framerate: 23.976,
                        completionPercentage: 42.5,
                        width: 1920,
                        height: 1080,
                        audioChannels: 2,
                        hardwareAccelerationType: "vaapi",
                        transcodeReasons: ["VideoCodecNotSupported", "AudioCodecNotSupported"]
                    )
                )
            ),
            ActiveSession(
                id: "sess-2",
                userName: "ゆか",
                deviceName: "iPhone 15",
                client: "Jellyfin Mobile",
                applicationVersion: "1.4.0",
                remoteEndpoint: "192.168.1.31",
                lastActivityDate: Date(),
                nowPlaying: SessionNowPlaying(
                    itemId: "item-2",
                    itemName: "Perfect Blue",
                    seriesName: nil,
                    mediaType: "Video",
                    positionSeconds: 2400,
                    runtimeSeconds: 5040,
                    isPaused: true,
                    playMethod: .directPlay,
                    transcode: nil
                )
            ),
            ActiveSession(
                id: "sess-3",
                userName: "ゲスト",
                deviceName: "Chrome",
                client: "Jellyfin Web",
                applicationVersion: "10.10.6",
                remoteEndpoint: "192.168.1.40",
                lastActivityDate: Date(),
                nowPlaying: nil
            )
        ]
    }
}
