import Foundation

public struct ServiceContainer: Sendable {
    public let auth: any AuthService
    public let media: any MediaService
    public let playback: any PlaybackService
    public let syncPlay: any SyncPlayService
    public let imageLoader: any ImageLoader

    public init(
        auth: any AuthService,
        media: any MediaService,
        playback: any PlaybackService,
        syncPlay: any SyncPlayService,
        imageLoader: any ImageLoader
    ) {
        self.auth = auth
        self.media = media
        self.playback = playback
        self.syncPlay = syncPlay
        self.imageLoader = imageLoader
    }

    public static func mock() -> ServiceContainer {
        ServiceContainer(
            auth: MockAuthService(),
            media: MockMediaService(),
            playback: MockPlaybackService(),
            syncPlay: MockSyncPlayService(),
            imageLoader: MockImageLoader()
        )
    }

    /// Real backend wired against a live Jellyfin server. The caller is
    /// expected to have already obtained an `accessToken` (via Quick Connect
    /// or by restoring a keychained user).
    public static func real(
        server: Server,
        accessToken: String,
        userId: String,
        deviceProfileBuilder: DeviceProfileBuilder = DeviceProfileBuilder()
    ) -> ServiceContainer {
        let http = JellyfinHTTPClient(
            server: server,
            accessToken: accessToken,
            userId: userId
        )
        return ServiceContainer(
            auth: JellyfinAuthService(http: http),
            media: JellyfinMediaService(http: http),
            playback: JellyfinPlaybackService(http: http, deviceProfileBuilder: deviceProfileBuilder),
            syncPlay: JellyfinSyncPlayService(http: http),
            imageLoader: JellyfinImageLoader()
        )
    }

    /// Real backend for the sign-in flow, before we have a token. Only the
    /// `auth` service is usable until a user completes Quick Connect.
    public static func realDiscovery() -> ServiceContainer {
        let placeholderServer = Server(id: "", name: "", url: URL(string: "about:blank")!)
        let http = JellyfinHTTPClient(server: placeholderServer)
        return ServiceContainer(
            auth: JellyfinAuthService(http: http),
            media: JellyfinMediaService(http: http),
            playback: JellyfinPlaybackService(http: http),
            syncPlay: JellyfinSyncPlayService(http: http),
            imageLoader: JellyfinImageLoader()
        )
    }
}
