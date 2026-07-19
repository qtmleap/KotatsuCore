import Foundation

/// Jellyfin's trickplay = tiled sprite sheets of periodic video thumbnails
/// (Netflix-style scrubber previews). The server generates one tile grid per
/// (mediaSource, width) pair.
///
/// A single tile image contains up to `tileWidth × tileHeight` thumbnails.
/// Given a playback position we can locate the exact frame:
///
///     n     = position_ms / interval          // thumbnail index
///     tile  = n / (tileWidth × tileHeight)     // which sprite tile
///     within= n % (tileWidth × tileHeight)     // slot inside the tile
///     row   = within / tileWidth
///     col   = within % tileWidth
///
/// Tile image URL: `/Videos/{mediaSourceId}/Trickplay/{width}/{tile}.jpg`
public struct MediaTrickplayInfo: Sendable, Codable, Hashable {
    /// The media source this sprite belongs to. Jellyfin stores trickplay
    /// keyed by media-source ID, and the same ID goes into the tile URL —
    /// **not** the parent item ID for multi-source items.
    public let mediaSourceId: String
    /// Width bucket the server rendered (Jellyfin defaults to 320). Feeds
    /// directly into the URL path.
    public let width: Int
    public let height: Int
    public let tileWidth: Int
    public let tileHeight: Int
    /// Number of tile images generated. Not the number of individual
    /// thumbnails — see `thumbnailsPerTile`.
    public let tileCount: Int
    /// Millisecond gap between consecutive thumbnails.
    public let intervalMs: Int

    public init(
        mediaSourceId: String,
        width: Int,
        height: Int,
        tileWidth: Int,
        tileHeight: Int,
        tileCount: Int,
        intervalMs: Int
    ) {
        self.mediaSourceId = mediaSourceId
        self.width = width
        self.height = height
        self.tileWidth = tileWidth
        self.tileHeight = tileHeight
        self.tileCount = tileCount
        self.intervalMs = intervalMs
    }

    public var thumbnailsPerTile: Int { tileWidth * tileHeight }

    /// Locate the sprite tile + slot for a given playback position.
    public func frame(atSeconds seconds: TimeInterval) -> Frame? {
        guard intervalMs > 0, thumbnailsPerTile > 0 else { return nil }
        let n = max(0, Int((seconds * 1000) / TimeInterval(intervalMs)))
        let tile = n / thumbnailsPerTile
        guard tile < tileCount else { return nil }
        let within = n % thumbnailsPerTile
        let row = within / tileWidth
        let col = within % tileWidth
        return Frame(tileIndex: tile, row: row, col: col)
    }

    public struct Frame: Sendable, Hashable {
        public let tileIndex: Int
        public let row: Int
        public let col: Int
    }
}

/// Wire-format representation of `Trickplay: { {msid}: { {width}: {...} } }`
/// used only during DTO decoding.
struct TrickplayInfoDTO: Codable, Sendable, Hashable {
    let width: Int
    let height: Int
    let tileWidth: Int
    let tileHeight: Int
    let thumbnailCount: Int
    let interval: Int

    private enum CodingKeys: String, CodingKey {
        case width = "Width"
        case height = "Height"
        case tileWidth = "TileWidth"
        case tileHeight = "TileHeight"
        case thumbnailCount = "ThumbnailCount"
        case interval = "Interval"
    }
}
