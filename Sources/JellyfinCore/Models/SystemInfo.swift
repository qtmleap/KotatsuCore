import Foundation

/// Server-wide facts returned by `/System/Info`. Non-admin users see a
/// subset; admin-only fields (paths, update flag) are optional so we don't
/// force callers to check role first.
public struct SystemInfo: Sendable, Codable, Hashable {
    public let serverName: String
    public let version: String
    public let productName: String?
    public let operatingSystem: String?
    public let operatingSystemDisplayName: String?
    public let localAddress: String?
    public let hasUpdateAvailable: Bool?
    public let hasPendingRestart: Bool?
    public let cachePath: String?
    public let logPath: String?
    public let transcodingTempPath: String?
    public let internalMetadataPath: String?

    public init(
        serverName: String,
        version: String,
        productName: String? = nil,
        operatingSystem: String? = nil,
        operatingSystemDisplayName: String? = nil,
        localAddress: String? = nil,
        hasUpdateAvailable: Bool? = nil,
        hasPendingRestart: Bool? = nil,
        cachePath: String? = nil,
        logPath: String? = nil,
        transcodingTempPath: String? = nil,
        internalMetadataPath: String? = nil
    ) {
        self.serverName = serverName
        self.version = version
        self.productName = productName
        self.operatingSystem = operatingSystem
        self.operatingSystemDisplayName = operatingSystemDisplayName
        self.localAddress = localAddress
        self.hasUpdateAvailable = hasUpdateAvailable
        self.hasPendingRestart = hasPendingRestart
        self.cachePath = cachePath
        self.logPath = logPath
        self.transcodingTempPath = transcodingTempPath
        self.internalMetadataPath = internalMetadataPath
    }
}

/// Snapshot of `/System/Configuration/encoding` — the transcoding pipeline
/// settings. All fields optional so a partial DTO (e.g. older server) still
/// decodes. Admin-only endpoint; expect a 403 on non-admin sessions.
public struct EncodingConfiguration: Sendable, Codable, Hashable {
    public let hardwareAccelerationType: String
    public let encoderAppPath: String?
    public let encoderAppPathDisplay: String?
    public let vaapiDevice: String?
    public let qsvDevice: String?
    public let enableHardwareEncoding: Bool
    public let allowHevcEncoding: Bool
    public let allowAv1Encoding: Bool
    public let enableTonemapping: Bool
    public let enableVppTonemapping: Bool?
    public let enableVideoToolboxTonemapping: Bool?
    public let hardwareDecodingCodecs: [String]
    public let h264Crf: Int?
    public let h265Crf: Int?
    public let encoderPreset: String?
    public let deinterlaceMethod: String?
    public let deinterlaceDoubleRate: Bool?
    public let enableThrottling: Bool
    public let throttleDelaySeconds: Int?
    public let enableSegmentDeletion: Bool?
    public let segmentKeepSeconds: Int?
    public let transcodingTempPath: String?
    public let fallbackFontPath: String?
    public let enableSubtitleExtraction: Bool?
    public let enableAudioVbr: Bool?
    public let enableIntelLowPowerH264HwEncoder: Bool?
    public let enableIntelLowPowerHevcHwEncoder: Bool?
    public let enableDecodingColorDepth10Hevc: Bool?
    public let enableDecodingColorDepth10Vp9: Bool?
    public let preferSystemNativeHwDecoder: Bool?

    public init(
        hardwareAccelerationType: String,
        encoderAppPath: String? = nil,
        encoderAppPathDisplay: String? = nil,
        vaapiDevice: String? = nil,
        qsvDevice: String? = nil,
        enableHardwareEncoding: Bool = false,
        allowHevcEncoding: Bool = false,
        allowAv1Encoding: Bool = false,
        enableTonemapping: Bool = false,
        enableVppTonemapping: Bool? = nil,
        enableVideoToolboxTonemapping: Bool? = nil,
        hardwareDecodingCodecs: [String] = [],
        h264Crf: Int? = nil,
        h265Crf: Int? = nil,
        encoderPreset: String? = nil,
        deinterlaceMethod: String? = nil,
        deinterlaceDoubleRate: Bool? = nil,
        enableThrottling: Bool = false,
        throttleDelaySeconds: Int? = nil,
        enableSegmentDeletion: Bool? = nil,
        segmentKeepSeconds: Int? = nil,
        transcodingTempPath: String? = nil,
        fallbackFontPath: String? = nil,
        enableSubtitleExtraction: Bool? = nil,
        enableAudioVbr: Bool? = nil,
        enableIntelLowPowerH264HwEncoder: Bool? = nil,
        enableIntelLowPowerHevcHwEncoder: Bool? = nil,
        enableDecodingColorDepth10Hevc: Bool? = nil,
        enableDecodingColorDepth10Vp9: Bool? = nil,
        preferSystemNativeHwDecoder: Bool? = nil
    ) {
        self.hardwareAccelerationType = hardwareAccelerationType
        self.encoderAppPath = encoderAppPath
        self.encoderAppPathDisplay = encoderAppPathDisplay
        self.vaapiDevice = vaapiDevice
        self.qsvDevice = qsvDevice
        self.enableHardwareEncoding = enableHardwareEncoding
        self.allowHevcEncoding = allowHevcEncoding
        self.allowAv1Encoding = allowAv1Encoding
        self.enableTonemapping = enableTonemapping
        self.enableVppTonemapping = enableVppTonemapping
        self.enableVideoToolboxTonemapping = enableVideoToolboxTonemapping
        self.hardwareDecodingCodecs = hardwareDecodingCodecs
        self.h264Crf = h264Crf
        self.h265Crf = h265Crf
        self.encoderPreset = encoderPreset
        self.deinterlaceMethod = deinterlaceMethod
        self.deinterlaceDoubleRate = deinterlaceDoubleRate
        self.enableThrottling = enableThrottling
        self.throttleDelaySeconds = throttleDelaySeconds
        self.enableSegmentDeletion = enableSegmentDeletion
        self.segmentKeepSeconds = segmentKeepSeconds
        self.transcodingTempPath = transcodingTempPath
        self.fallbackFontPath = fallbackFontPath
        self.enableSubtitleExtraction = enableSubtitleExtraction
        self.enableAudioVbr = enableAudioVbr
        self.enableIntelLowPowerH264HwEncoder = enableIntelLowPowerH264HwEncoder
        self.enableIntelLowPowerHevcHwEncoder = enableIntelLowPowerHevcHwEncoder
        self.enableDecodingColorDepth10Hevc = enableDecodingColorDepth10Hevc
        self.enableDecodingColorDepth10Vp9 = enableDecodingColorDepth10Vp9
        self.preferSystemNativeHwDecoder = preferSystemNativeHwDecoder
    }
}

/// One entry from `/Sessions`. Non-admins only see their own; admins see
/// everyone currently connected. `nowPlaying` is nil when the client is
/// idle (still holding a session but not playing).
public struct ActiveSession: Sendable, Identifiable, Codable, Hashable {
    public let id: String
    public let userName: String?
    public let deviceName: String?
    public let client: String?
    public let applicationVersion: String?
    public let remoteEndpoint: String?
    public let lastActivityDate: Date?
    public let nowPlaying: SessionNowPlaying?

    public init(
        id: String,
        userName: String? = nil,
        deviceName: String? = nil,
        client: String? = nil,
        applicationVersion: String? = nil,
        remoteEndpoint: String? = nil,
        lastActivityDate: Date? = nil,
        nowPlaying: SessionNowPlaying? = nil
    ) {
        self.id = id
        self.userName = userName
        self.deviceName = deviceName
        self.client = client
        self.applicationVersion = applicationVersion
        self.remoteEndpoint = remoteEndpoint
        self.lastActivityDate = lastActivityDate
        self.nowPlaying = nowPlaying
    }
}

public struct SessionNowPlaying: Sendable, Codable, Hashable {
    public enum PlayMethod: String, Sendable, Codable, Hashable {
        case directPlay = "DirectPlay"
        case directStream = "DirectStream"
        case transcode = "Transcode"
    }

    public let itemId: String
    public let itemName: String
    public let seriesName: String?
    public let mediaType: String?
    public let positionSeconds: TimeInterval?
    public let runtimeSeconds: TimeInterval?
    public let isPaused: Bool
    public let playMethod: PlayMethod
    public let transcode: TranscodeInfo?

    public init(
        itemId: String,
        itemName: String,
        seriesName: String? = nil,
        mediaType: String? = nil,
        positionSeconds: TimeInterval? = nil,
        runtimeSeconds: TimeInterval? = nil,
        isPaused: Bool = false,
        playMethod: PlayMethod,
        transcode: TranscodeInfo? = nil
    ) {
        self.itemId = itemId
        self.itemName = itemName
        self.seriesName = seriesName
        self.mediaType = mediaType
        self.positionSeconds = positionSeconds
        self.runtimeSeconds = runtimeSeconds
        self.isPaused = isPaused
        self.playMethod = playMethod
        self.transcode = transcode
    }
}

/// TranscodingInfo mirror — what the server is actually re-encoding to right
/// now. `transcodeReasons` explains why the pipeline kicked in (unsupported
/// codec, container, resolution, bitrate, subtitle, etc.).
public struct TranscodeInfo: Sendable, Codable, Hashable {
    public let audioCodec: String?
    public let videoCodec: String?
    public let container: String?
    public let isVideoDirect: Bool
    public let isAudioDirect: Bool
    public let bitrate: Int?
    public let framerate: Double?
    public let completionPercentage: Double?
    public let width: Int?
    public let height: Int?
    public let audioChannels: Int?
    public let hardwareAccelerationType: String?
    public let transcodeReasons: [String]

    public init(
        audioCodec: String? = nil,
        videoCodec: String? = nil,
        container: String? = nil,
        isVideoDirect: Bool = false,
        isAudioDirect: Bool = false,
        bitrate: Int? = nil,
        framerate: Double? = nil,
        completionPercentage: Double? = nil,
        width: Int? = nil,
        height: Int? = nil,
        audioChannels: Int? = nil,
        hardwareAccelerationType: String? = nil,
        transcodeReasons: [String] = []
    ) {
        self.audioCodec = audioCodec
        self.videoCodec = videoCodec
        self.container = container
        self.isVideoDirect = isVideoDirect
        self.isAudioDirect = isAudioDirect
        self.bitrate = bitrate
        self.framerate = framerate
        self.completionPercentage = completionPercentage
        self.width = width
        self.height = height
        self.audioChannels = audioChannels
        self.hardwareAccelerationType = hardwareAccelerationType
        self.transcodeReasons = transcodeReasons
    }
}
