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
}
