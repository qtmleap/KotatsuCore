import Foundation
import Kingfisher

/// Auth context handed to Kingfisher's request modifier. Kept minimal so
/// the modifier never captures the whole HTTP client actor.
public struct JellyfinImageAuth: Sendable {
    /// Host of the Jellyfin server. The modifier only attaches the auth
    /// header when the requested image URL matches this host — so
    /// third-party image URLs (e.g. TMDB fallbacks) never leak the token.
    public let host: String
    /// The `Authorization: MediaBrowser …` header value.
    public let headerValue: String

    public init(host: String, headerValue: String) {
        self.host = host
        self.headerValue = headerValue
    }
}

/// Wires Kingfisher for Jellyfin: injects the `Authorization` header for
/// requests that hit the Jellyfin host (and only that host — TMDB fallbacks
/// stay anonymous), and sizes the memory/disk caches so a full home refresh
/// survives an app relaunch without OOMing an Apple TV HD.
public enum JellyfinKingfisher {
    /// Reflect the current auth context onto Kingfisher's shared downloader
    /// and cache. Called on every `ServiceContainer` rebuild (login, profile
    /// switch, sign-out) so image requests always carry the right token — or
    /// no token at all when we've dropped back to discovery mode.
    ///
    /// Cache tuning is applied once on the first call; subsequent calls only
    /// swap the request modifier so we don't churn the cache on every
    /// container swap.
    public static func configure(auth: JellyfinImageAuth?) {
        applyCacheDefaultsOnce()

        let downloader = ImageDownloader.default
        downloader.sessionConfiguration.timeoutIntervalForRequest = 30
        downloader.sessionConfiguration.timeoutIntervalForResource = 300

        var options: KingfisherOptionsInfo = [
            .backgroundDecode,
            .diskCacheExpiration(.days(30)),
            .memoryCacheExpiration(.seconds(600)),
        ]
        if let auth {
            options.append(.requestModifier(makeAuthModifier(auth: auth)))
        }
        KingfisherManager.shared.defaultOptions = options
    }

    /// Wipe both cache tiers. Call on sign-out or when the user switches to
    /// a different Jellyfin server so previous artwork can't leak into the
    /// new session's poster shelves.
    public static func clearAllCaches() {
        ImageCache.default.clearMemoryCache()
        ImageCache.default.clearDiskCache()
    }

    // MARK: - Auth modifier

    private static func makeAuthModifier(auth: JellyfinImageAuth) -> AnyModifier {
        let host = auth.host
        let header = auth.headerValue
        return AnyModifier { request in
            guard let requestHost = request.url?.host, requestHost == host else {
                return request
            }
            var modified = request
            modified.setValue(header, forHTTPHeaderField: "Authorization")
            return modified
        }
    }

    // MARK: - One-shot cache tuning

    private static let applyOnce: Void = {
        let cache = ImageCache.default
        // Apple TV HD has 2GB total RAM — keep memory footprint conservative.
        cache.memoryStorage.config.totalCostLimit = 96 * 1024 * 1024   // ~96MB
        cache.memoryStorage.config.countLimit = 200
        // Disk lives under Library/Caches/ on tvOS, so the OS is free to
        // reclaim it under storage pressure — the right home for regenerable
        // artwork. 300MB is generous enough that a typical library's posters
        // + backdrops all fit through a session.
        cache.diskStorage.config.sizeLimit = 300 * 1024 * 1024
        cache.diskStorage.config.expiration = .days(30)
    }()

    private static func applyCacheDefaultsOnce() {
        _ = applyOnce
    }
}
