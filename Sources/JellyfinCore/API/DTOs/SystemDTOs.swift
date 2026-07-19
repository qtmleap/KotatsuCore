import Foundation

/// Response for `GET /System/Info`. Requires auth. Non-admin users see a
/// subset with paths / update flag omitted or null.
struct SystemInfoDTO: Codable, Sendable {
    let localAddress: String?
    let serverName: String?
    let version: String?
    let productName: String?
    let operatingSystem: String?
    let operatingSystemDisplayName: String?
    let id: String?
    let startupWizardCompleted: Bool?
    let hasUpdateAvailable: Bool?
    let hasPendingRestart: Bool?
    let cachePath: String?
    let logPath: String?
    let transcodingTempPath: String?
    let internalMetadataPath: String?

    private enum CodingKeys: String, CodingKey {
        case localAddress = "LocalAddress"
        case serverName = "ServerName"
        case version = "Version"
        case productName = "ProductName"
        case operatingSystem = "OperatingSystem"
        case operatingSystemDisplayName = "OperatingSystemDisplayName"
        case id = "Id"
        case startupWizardCompleted = "StartupWizardCompleted"
        case hasUpdateAvailable = "HasUpdateAvailable"
        case hasPendingRestart = "HasPendingRestart"
        case cachePath = "CachePath"
        case logPath = "LogPath"
        case transcodingTempPath = "TranscodingTempPath"
        case internalMetadataPath = "InternalMetadataPath"
    }

    func toDomain() -> SystemInfo {
        SystemInfo(
            serverName: serverName ?? "Jellyfin",
            version: version ?? "unknown",
            productName: productName,
            operatingSystem: operatingSystem,
            operatingSystemDisplayName: operatingSystemDisplayName,
            localAddress: localAddress,
            hasUpdateAvailable: hasUpdateAvailable,
            hasPendingRestart: hasPendingRestart,
            cachePath: cachePath,
            logPath: logPath,
            transcodingTempPath: transcodingTempPath,
            internalMetadataPath: internalMetadataPath
        )
    }
}

/// Response for `GET /System/Configuration/encoding`. All fields optional so
/// older servers with a smaller EncodingOptions still decode. Bool defaults
/// applied on domain conversion.
struct EncodingOptionsDTO: Codable, Sendable {
    let hardwareAccelerationType: String?
    let encoderAppPath: String?
    let encoderAppPathDisplay: String?
    let vaapiDevice: String?
    let qsvDevice: String?
    let enableHardwareEncoding: Bool?
    let allowHevcEncoding: Bool?
    let allowAv1Encoding: Bool?
    let enableTonemapping: Bool?
    let enableVppTonemapping: Bool?
    let enableVideoToolboxTonemapping: Bool?
    let hardwareDecodingCodecs: [String]?
    let h264Crf: Int?
    let h265Crf: Int?
    let encoderPreset: String?
    let deinterlaceMethod: String?
    let deinterlaceDoubleRate: Bool?
    let enableThrottling: Bool?
    let throttleDelaySeconds: Int?
    let enableSegmentDeletion: Bool?
    let segmentKeepSeconds: Int?
    let transcodingTempPath: String?
    let fallbackFontPath: String?
    let enableSubtitleExtraction: Bool?
    let enableAudioVbr: Bool?
    let enableIntelLowPowerH264HwEncoder: Bool?
    let enableIntelLowPowerHevcHwEncoder: Bool?
    let enableDecodingColorDepth10Hevc: Bool?
    let enableDecodingColorDepth10Vp9: Bool?
    let preferSystemNativeHwDecoder: Bool?

    private enum CodingKeys: String, CodingKey {
        case hardwareAccelerationType = "HardwareAccelerationType"
        case encoderAppPath = "EncoderAppPath"
        case encoderAppPathDisplay = "EncoderAppPathDisplay"
        case vaapiDevice = "VaapiDevice"
        case qsvDevice = "QsvDevice"
        case enableHardwareEncoding = "EnableHardwareEncoding"
        case allowHevcEncoding = "AllowHevcEncoding"
        case allowAv1Encoding = "AllowAv1Encoding"
        case enableTonemapping = "EnableTonemapping"
        case enableVppTonemapping = "EnableVppTonemapping"
        case enableVideoToolboxTonemapping = "EnableVideoToolboxTonemapping"
        case hardwareDecodingCodecs = "HardwareDecodingCodecs"
        case h264Crf = "H264Crf"
        case h265Crf = "H265Crf"
        case encoderPreset = "EncoderPreset"
        case deinterlaceMethod = "DeinterlaceMethod"
        case deinterlaceDoubleRate = "DeinterlaceDoubleRate"
        case enableThrottling = "EnableThrottling"
        case throttleDelaySeconds = "ThrottleDelaySeconds"
        case enableSegmentDeletion = "EnableSegmentDeletion"
        case segmentKeepSeconds = "SegmentKeepSeconds"
        case transcodingTempPath = "TranscodingTempPath"
        case fallbackFontPath = "FallbackFontPath"
        case enableSubtitleExtraction = "EnableSubtitleExtraction"
        case enableAudioVbr = "EnableAudioVbr"
        case enableIntelLowPowerH264HwEncoder = "EnableIntelLowPowerH264HwEncoder"
        case enableIntelLowPowerHevcHwEncoder = "EnableIntelLowPowerHevcHwEncoder"
        case enableDecodingColorDepth10Hevc = "EnableDecodingColorDepth10Hevc"
        case enableDecodingColorDepth10Vp9 = "EnableDecodingColorDepth10Vp9"
        case preferSystemNativeHwDecoder = "PreferSystemNativeHwDecoder"
    }

    func toDomain() -> EncodingConfiguration {
        EncodingConfiguration(
            hardwareAccelerationType: hardwareAccelerationType ?? "none",
            encoderAppPath: encoderAppPath,
            encoderAppPathDisplay: encoderAppPathDisplay,
            vaapiDevice: vaapiDevice,
            qsvDevice: qsvDevice,
            enableHardwareEncoding: enableHardwareEncoding ?? false,
            allowHevcEncoding: allowHevcEncoding ?? false,
            allowAv1Encoding: allowAv1Encoding ?? false,
            enableTonemapping: enableTonemapping ?? false,
            enableVppTonemapping: enableVppTonemapping,
            enableVideoToolboxTonemapping: enableVideoToolboxTonemapping,
            hardwareDecodingCodecs: hardwareDecodingCodecs ?? [],
            h264Crf: h264Crf,
            h265Crf: h265Crf,
            encoderPreset: encoderPreset,
            deinterlaceMethod: deinterlaceMethod,
            deinterlaceDoubleRate: deinterlaceDoubleRate,
            enableThrottling: enableThrottling ?? false,
            throttleDelaySeconds: throttleDelaySeconds,
            enableSegmentDeletion: enableSegmentDeletion,
            segmentKeepSeconds: segmentKeepSeconds,
            transcodingTempPath: transcodingTempPath,
            fallbackFontPath: fallbackFontPath,
            enableSubtitleExtraction: enableSubtitleExtraction,
            enableAudioVbr: enableAudioVbr,
            enableIntelLowPowerH264HwEncoder: enableIntelLowPowerH264HwEncoder,
            enableIntelLowPowerHevcHwEncoder: enableIntelLowPowerHevcHwEncoder,
            enableDecodingColorDepth10Hevc: enableDecodingColorDepth10Hevc,
            enableDecodingColorDepth10Vp9: enableDecodingColorDepth10Vp9,
            preferSystemNativeHwDecoder: preferSystemNativeHwDecoder
        )
    }
}

/// Response entry for `GET /Sessions`. Named differently from the tiny
/// `SessionInfoDTO` in AuthDTOs so both can coexist.
struct ActiveSessionDTO: Codable, Sendable {
    let id: String?
    let userId: String?
    let userName: String?
    let client: String?
    let deviceName: String?
    let deviceId: String?
    let applicationVersion: String?
    let remoteEndPoint: String?
    let lastActivityDate: Date?
    let nowPlayingItem: SessionNowPlayingItemDTO?
    let playState: PlayerStateInfoDTO?
    let transcodingInfo: TranscodingInfoDTO?

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case userId = "UserId"
        case userName = "UserName"
        case client = "Client"
        case deviceName = "DeviceName"
        case deviceId = "DeviceId"
        case applicationVersion = "ApplicationVersion"
        case remoteEndPoint = "RemoteEndPoint"
        case lastActivityDate = "LastActivityDate"
        case nowPlayingItem = "NowPlayingItem"
        case playState = "PlayState"
        case transcodingInfo = "TranscodingInfo"
    }

    func toDomain() -> ActiveSession {
        let nowPlaying: SessionNowPlaying? = {
            guard let item = nowPlayingItem, let state = playState else { return nil }
            let method = SessionNowPlaying.PlayMethod(rawValue: state.playMethod ?? "DirectPlay") ?? .directPlay
            let runtime = item.runTimeTicks.map { Double($0) / 10_000_000 }
            let position = state.positionTicks.map { Double($0) / 10_000_000 }
            return SessionNowPlaying(
                itemId: item.id ?? "",
                itemName: item.name ?? "",
                seriesName: item.seriesName,
                mediaType: item.mediaType,
                positionSeconds: position,
                runtimeSeconds: runtime,
                isPaused: state.isPaused ?? false,
                playMethod: method,
                transcode: transcodingInfo?.toDomain()
            )
        }()
        return ActiveSession(
            id: id ?? UUID().uuidString,
            userName: userName,
            deviceName: deviceName,
            client: client,
            applicationVersion: applicationVersion,
            remoteEndpoint: remoteEndPoint,
            lastActivityDate: lastActivityDate,
            nowPlaying: nowPlaying
        )
    }
}

struct SessionNowPlayingItemDTO: Codable, Sendable {
    let id: String?
    let name: String?
    let seriesName: String?
    let mediaType: String?
    let runTimeTicks: Int64?

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case seriesName = "SeriesName"
        case mediaType = "MediaType"
        case runTimeTicks = "RunTimeTicks"
    }
}

struct PlayerStateInfoDTO: Codable, Sendable {
    let positionTicks: Int64?
    let isPaused: Bool?
    let playMethod: String?

    private enum CodingKeys: String, CodingKey {
        case positionTicks = "PositionTicks"
        case isPaused = "IsPaused"
        case playMethod = "PlayMethod"
    }
}

struct TranscodingInfoDTO: Codable, Sendable {
    let audioCodec: String?
    let videoCodec: String?
    let container: String?
    let isVideoDirect: Bool?
    let isAudioDirect: Bool?
    let bitrate: Int?
    let framerate: Double?
    let completionPercentage: Double?
    let width: Int?
    let height: Int?
    let audioChannels: Int?
    let hardwareAccelerationType: String?
    let transcodeReasons: [String]?

    private enum CodingKeys: String, CodingKey {
        case audioCodec = "AudioCodec"
        case videoCodec = "VideoCodec"
        case container = "Container"
        case isVideoDirect = "IsVideoDirect"
        case isAudioDirect = "IsAudioDirect"
        case bitrate = "Bitrate"
        case framerate = "Framerate"
        case completionPercentage = "CompletionPercentage"
        case width = "Width"
        case height = "Height"
        case audioChannels = "AudioChannels"
        case hardwareAccelerationType = "HardwareAccelerationType"
        case transcodeReasons = "TranscodeReasons"
    }

    func toDomain() -> TranscodeInfo {
        TranscodeInfo(
            audioCodec: audioCodec,
            videoCodec: videoCodec,
            container: container,
            isVideoDirect: isVideoDirect ?? false,
            isAudioDirect: isAudioDirect ?? false,
            bitrate: bitrate,
            framerate: framerate,
            completionPercentage: completionPercentage,
            width: width,
            height: height,
            audioChannels: audioChannels,
            hardwareAccelerationType: hardwareAccelerationType,
            transcodeReasons: transcodeReasons ?? []
        )
    }
}
