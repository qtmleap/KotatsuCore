import Foundation
import CoreGraphics
import ImageIO

/// Auth context handed to `JellyfinImageLoader` at construction. Kept minimal
/// so the loader never captures the whole HTTP client actor.
public struct JellyfinImageAuth: Sendable {
    /// Host of the Jellyfin server. The loader only attaches the auth header
    /// when the requested image URL matches this host — so third-party
    /// image URLs (e.g. TMDB fallbacks) never leak the token.
    public let host: String
    /// The `Authorization: MediaBrowser …` header value.
    public let headerValue: String

    public init(host: String, headerValue: String) {
        self.host = host
        self.headerValue = headerValue
    }
}

/// Downsampling image loader. Fetches the raw bytes with `URLSession`, then
/// asks ImageIO for a thumbnail sized to the caller's requested pixel size.
/// This is a big deal on Apple TV HD (A8, 2 GB RAM) where SwiftUI's default
/// `AsyncImage` decodes full-resolution 4K posters into memory and OOM-kills
/// the process on the second row of the home shelf.
public actor JellyfinImageLoader: ImageLoader {
    private let urlSession: URLSession
    private var cache: [CacheKey: Data] = [:]
    private var order: [CacheKey] = []
    private let maxEntries: Int
    private let authProvider: (@Sendable () -> JellyfinImageAuth?)?

    private struct CacheKey: Hashable {
        let url: URL
        let width: Int
        let height: Int
    }

    public init(
        urlSession: URLSession = .shared,
        maxEntries: Int = 128,
        authProvider: (@Sendable () -> JellyfinImageAuth?)? = nil
    ) {
        self.urlSession = urlSession
        self.maxEntries = maxEntries
        self.authProvider = authProvider
    }

    public func loadImageData(from url: URL, targetPixelSize: CGSize) async throws -> Data {
        let key = CacheKey(url: url, width: Int(targetPixelSize.width.rounded()), height: Int(targetPixelSize.height.rounded()))
        if let cached = cache[key] {
            return cached
        }

        var request = URLRequest(url: url)
        if let auth = authProvider?(), let host = url.host, host == auth.host {
            request.setValue(auth.headerValue, forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await urlSession.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            AppLogger.warning("Image \(http.statusCode) for \(url.absoluteString)")
            throw JellyfinAPIError.fromStatus(http.statusCode, body: nil)
        }
        let processed = downsample(data: data, targetSize: targetPixelSize) ?? data
        insert(processed, for: key)
        return processed
    }

    // MARK: - Downsampling

    private nonisolated func downsample(data: Data, targetSize: CGSize) -> Data? {
        let maxDim = max(targetSize.width, targetSize.height)
        guard maxDim > 0 else { return nil }
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return nil
        }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxDim)
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
            return nil
        }
        return encodePNG(image: image)
    }

    private nonisolated func encodePNG(image: CGImage) -> Data? {
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
    }

    // MARK: - Cache

    private func insert(_ data: Data, for key: CacheKey) {
        cache[key] = data
        order.append(key)
        while order.count > maxEntries {
            let evicted = order.removeFirst()
            cache.removeValue(forKey: evicted)
        }
    }
}
