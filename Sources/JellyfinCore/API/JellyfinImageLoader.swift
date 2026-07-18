import Foundation
import CoreGraphics
import ImageIO
import os

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
    private let logger = Logger(subsystem: "app.jellyfin.tvos", category: "image")

    private struct CacheKey: Hashable {
        let url: URL
        let width: Int
        let height: Int
    }

    public init(urlSession: URLSession = .shared, maxEntries: Int = 128) {
        self.urlSession = urlSession
        self.maxEntries = maxEntries
    }

    public func loadImageData(from url: URL, targetPixelSize: CGSize) async throws -> Data {
        let key = CacheKey(url: url, width: Int(targetPixelSize.width.rounded()), height: Int(targetPixelSize.height.rounded()))
        if let cached = cache[key] {
            return cached
        }
        let (data, response) = try await urlSession.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
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
