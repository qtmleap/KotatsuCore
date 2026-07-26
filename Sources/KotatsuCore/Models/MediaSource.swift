import Foundation

/// Distribution source parsed from an item's file name — the `[AP]` /
/// `[BD]` markers commonly used by Japanese anime scenes to note the
/// original release channel.
///
/// Only sources we actively bucket into UI folders are listed; unknown
/// markers fall through to `nil` on the item so grouping ignores them.
public enum MediaSource: String, Sendable, Codable, CaseIterable, Hashable {
    case primeVideo
    case bluRay
    case abema
    case crunchyroll
    case hulu

    /// Human-readable label shown on the filter chip and item detail.
    public var displayName: String {
        switch self {
        case .primeVideo:  return "Prime Video"
        case .bluRay:      return "Blu-ray"
        case .abema:       return "Abema"
        case .crunchyroll: return "Crunchyroll"
        case .hulu:        return "Hulu"
        }
    }

    /// Two-letter marker embedded in filenames.
    public var code: String {
        switch self {
        case .primeVideo:  return "AP"
        case .bluRay:      return "BD"
        case .abema:       return "AB"
        case .crunchyroll: return "CR"
        case .hulu:        return "HL"
        }
    }

    /// Scan a full path (any component may carry the tag — Blu-ray
    /// releases often mark the season folder rather than the individual
    /// episode file) for a bracketed `[XX]` marker and map it to a known
    /// source. Returns nil when nothing recognisable is present.
    ///
    /// Example: `.../Season 01 [BD]/E01.mkv` → `.bluRay`.
    public static func detect(fromPath path: String) -> MediaSource? {
        for source in MediaSource.allCases {
            if path.contains("[\(source.code)]") {
                return source
            }
        }
        return nil
    }

    /// Extract the "release variant" name from a path — the folder title
    /// sitting immediately after the `[XX]` marker. Distinguishes
    /// alternate editions of the same show that Jellyfin groups under
    /// one series item (FLCL / FLCL Alternative / FLCL Progressive all
    /// share a tmdbid but live in different folders on disk).
    ///
    /// `.../[AP] FLCL Alternative (2018) [tmdbid-…]/S01E01.mkv` → `"FLCL Alternative"`
    /// `.../[BD] Some Movie (2020)/movie.mkv` → `"Some Movie"`
    public static func detectVariant(fromPath path: String, source: MediaSource) -> String? {
        let marker = "[\(source.code)] "
        guard let range = path.range(of: marker) else { return nil }
        let after = path[range.upperBound...]

        var end = after.endIndex
        // Prefer cutting at ` (nnnn)` (year suffix); fall back to first `/`.
        if let yearRange = after.range(of: #" \(\d{4}\)"#, options: .regularExpression) {
            end = yearRange.lowerBound
        } else if let slashRange = after.range(of: "/") {
            end = slashRange.lowerBound
        }
        let variant = String(after[..<end]).trimmingCharacters(in: .whitespaces)
        return variant.isEmpty ? nil : variant
    }
}
