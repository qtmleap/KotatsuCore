import Foundation

public struct ServiceContainer: Sendable {
    public let auth: any AuthService
    public let media: any MediaService
    public let playback: any PlaybackService
    public let syncPlay: any SyncPlayService
    public let system: any SystemService

    public init(
        auth: any AuthService,
        media: any MediaService,
        playback: any PlaybackService,
        syncPlay: any SyncPlayService,
        system: any SystemService
    ) {
        self.auth = auth
        self.media = media
        self.playback = playback
        self.syncPlay = syncPlay
        self.system = system
    }

    public static func mock() -> ServiceContainer {
        ServiceContainer(
            auth: MockAuthService(),
            media: MockMediaService(),
            playback: MockPlaybackService(),
            syncPlay: MockSyncPlayService(),
            system: MockSystemService()
        )
    }

    /// Real backend wired against a live Jellyfin server. The caller is
    /// expected to have already obtained an `accessToken` (via Quick Connect
    /// or by restoring a keychained user).
    ///
    /// As a side effect, applies the current auth context to Kingfisher's
    /// shared downloader so `/Users/{id}/Images/Primary` and friends are
    /// fetched with the same `Authorization` header as the API client.
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
        configureKingfisher(for: http)
        return ServiceContainer(
            auth: JellyfinAuthService(http: http),
            media: JellyfinMediaService(http: http),
            playback: JellyfinPlaybackService(http: http, deviceProfileBuilder: deviceProfileBuilder),
            syncPlay: JellyfinSyncPlayService(http: http),
            system: JellyfinSystemService(http: http)
        )
    }

    /// Real backend for the sign-in flow, before we have a token. Only the
    /// `auth` service is usable until a user completes Quick Connect.
    public static func realDiscovery() -> ServiceContainer {
        let placeholderServer = Server(id: "", name: "", url: URL(string: "about:blank")!)
        let http = JellyfinHTTPClient(server: placeholderServer)
        // No credentials yet — reset Kingfisher to anonymous mode so a stale
        // token from a previous session can't slip into fresh requests.
        JellyfinKingfisher.configure(auth: nil)
        return ServiceContainer(
            auth: JellyfinAuthService(http: http),
            media: JellyfinMediaService(http: http),
            playback: JellyfinPlaybackService(http: http),
            syncPlay: JellyfinSyncPlayService(http: http),
            system: JellyfinSystemService(http: http)
        )
    }

    private static func configureKingfisher(for http: JellyfinHTTPClient) {
        guard let host = http.server.url.host, !host.isEmpty else {
            JellyfinKingfisher.configure(auth: nil)
            return
        }
        let auth = JellyfinImageAuth(host: host, headerValue: http.authorizationHeaderValue)
        JellyfinKingfisher.configure(auth: auth)
    }
}
