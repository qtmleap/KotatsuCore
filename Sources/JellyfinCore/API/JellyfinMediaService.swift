import Foundation
import Alamofire

/// Real implementation of `MediaService`. Every endpoint documented in the
/// contract maps 1:1 to a Jellyfin route; this file is deliberately
/// mechanical so it's easy to audit against the OpenAPI spec.
public struct JellyfinMediaService: MediaService {
    private let http: JellyfinHTTPClient

    public init(http: JellyfinHTTPClient) {
        self.http = http
    }

    private var userId: String {
        get throws {
            guard let id = http.userId, !id.isEmpty else { throw JellyfinAPIError.unauthorized }
            return id
        }
    }

    private var server: Server { http.server }

    /// Standard set of fields we want returned for list-style responses. The
    /// UI shelves need artwork tags + user data (progress, isFavorite,
    /// isWatched); everything else is optional.
    private let baseListFields = "PrimaryImageAspectRatio,BasicSyncInfo,MediaSourceCount,Overview,Genres,Tagline,ChildCount"

    // MARK: - Shelves

    public func fetchHeroFeatured() async throws -> MediaItem? {
        let uid = try userId
        let result: BaseItemQueryResultDTO = try await http.request(
            .get,
            path: "/Users/\(uid)/Items",
            query: [
                "SortBy": "Random",
                "Limit": "1",
                "IncludeItemTypes": "Movie",
                "Recursive": "true",
                "Fields": baseListFields,
                "ImageTypeLimit": "1",
                "EnableImageTypes": "Primary,Backdrop,Logo"
            ]
        )
        return result.items.first.map { $0.toMediaItem(server: server) }
    }

    public func fetchContinueWatching() async throws -> [MediaItem] {
        let uid = try userId
        let result: BaseItemQueryResultDTO = try await http.request(
            .get,
            path: "/Users/\(uid)/Items/Resume",
            query: [
                "Limit": "12",
                "MediaTypes": "Video",
                "Fields": baseListFields,
                "EnableImageTypes": "Primary,Backdrop,Thumb"
            ]
        )
        return result.items.map { $0.toMediaItem(server: server) }
    }

    public func fetchNextUp() async throws -> [MediaItem] {
        let uid = try userId
        let result: BaseItemQueryResultDTO = try await http.request(
            .get,
            path: "/Shows/NextUp",
            query: [
                "UserId": uid,
                "Limit": "12",
                "Fields": baseListFields,
                "EnableImageTypes": "Primary,Backdrop,Thumb"
            ]
        )
        return result.items.map { $0.toMediaItem(server: server) }
    }

    public func fetchLatestMovies() async throws -> [MediaItem] {
        let uid = try userId
        // /Users/{id}/Items/Latest returns a raw array, not a QueryResult.
        let items: [BaseItemDTO] = try await http.request(
            .get,
            path: "/Users/\(uid)/Items/Latest",
            query: [
                "IncludeItemTypes": "Movie",
                "Limit": "16",
                "Fields": baseListFields,
                "EnableImageTypes": "Primary,Backdrop"
            ]
        )
        return items.map { $0.toMediaItem(server: server) }
    }

    public func fetchLatestSeries() async throws -> [MediaItem] {
        let uid = try userId
        let items: [BaseItemDTO] = try await http.request(
            .get,
            path: "/Users/\(uid)/Items/Latest",
            query: [
                "IncludeItemTypes": "Series",
                "Limit": "16",
                "Fields": baseListFields,
                "EnableImageTypes": "Primary,Backdrop"
            ]
        )
        return items.map { $0.toMediaItem(server: server) }
    }

    public func fetchFavorites() async throws -> [MediaItem] {
        let uid = try userId
        let result: BaseItemQueryResultDTO = try await http.request(
            .get,
            path: "/Users/\(uid)/Items",
            query: [
                "IsFavorite": "true",
                "Recursive": "true",
                "IncludeItemTypes": "Movie,Series",
                "Limit": "40",
                "SortBy": "SortName",
                "SortOrder": "Ascending",
                "Fields": baseListFields
            ]
        )
        return result.items.map { $0.toMediaItem(server: server) }
    }

    public func fetchRandomForRewatch() async throws -> [MediaItem] {
        let uid = try userId
        let result: BaseItemQueryResultDTO = try await http.request(
            .get,
            path: "/Users/\(uid)/Items",
            query: [
                "SortBy": "Random",
                "Filters": "IsPlayed",
                "Limit": "16",
                "Recursive": "true",
                "IncludeItemTypes": "Movie,Series",
                "Fields": baseListFields
            ]
        )
        return result.items.map { $0.toMediaItem(server: server) }
    }

    // MARK: - Detail / series

    public func fetchDetail(id: String) async throws -> MediaDetail {
        let uid = try userId
        let dto: BaseItemDTO = try await http.request(
            .get,
            path: "/Users/\(uid)/Items/\(id)",
            query: [
                "Fields": "Overview,Genres,Tagline,MediaSources,MediaStreams,People,Studios,ProductionYear,CommunityRating,OfficialRating"
            ]
        )
        return dto.toDetail(server: server)
    }

    public func fetchSeasons(seriesId: String) async throws -> [Season] {
        let uid = try userId
        let result: BaseItemQueryResultDTO = try await http.request(
            .get,
            path: "/Shows/\(seriesId)/Seasons",
            query: [
                "UserId": uid,
                "Fields": "ChildCount,PrimaryImageAspectRatio"
            ]
        )
        return result.items.map { $0.toSeason(server: server, fallbackSeriesId: seriesId) }
    }

    public func fetchEpisodes(seasonId: String) async throws -> [Episode] {
        let uid = try userId
        // We need seriesId to hit /Shows/{seriesId}/Episodes; resolve via
        // the season item itself.
        let season: BaseItemDTO = try await http.request(
            .get,
            path: "/Users/\(uid)/Items/\(seasonId)"
        )
        guard let sid = season.seriesId else {
            throw JellyfinAPIError.missingField("SeriesId")
        }
        let result: BaseItemQueryResultDTO = try await http.request(
            .get,
            path: "/Shows/\(sid)/Episodes",
            query: [
                "UserId": uid,
                "SeasonId": seasonId,
                "Fields": "Overview,PrimaryImageAspectRatio"
            ]
        )
        return result.items.map { $0.toEpisode(server: server) }
    }

    public func fetchNextEpisode(seriesId: String) async throws -> Episode? {
        let uid = try userId
        let result: BaseItemQueryResultDTO = try await http.request(
            .get,
            path: "/Shows/NextUp",
            query: [
                "UserId": uid,
                "SeriesId": seriesId,
                "Limit": "1",
                "Fields": "Overview,PrimaryImageAspectRatio"
            ]
        )
        return result.items.first.map { $0.toEpisode(server: server) }
    }

    // MARK: - Search

    public func search(query: String, kind: MediaKind?) async throws -> [MediaItem] {
        guard !query.isEmpty else { return [] }
        let uid = try userId
        let q: [String: String?] = [
            "SearchTerm": query,
            "Limit": "50",
            "UserId": uid,
            "IncludeItemTypes": kind.map(Self.mapKind(_:)) ?? "Movie,Series,Episode"
        ]
        let result: SearchHintResultDTO = try await http.request(
            .get,
            path: "/Search/Hints",
            query: q
        )
        return result.searchHints.compactMap { $0.toMediaItem(server: server) }
    }

    private static func mapKind(_ kind: MediaKind) -> String {
        switch kind {
        case .movie: return "Movie"
        case .series: return "Series"
        case .episode: return "Episode"
        }
    }

    // MARK: - Favourites / watched

    public func setFavorite(id: String, isFavorite: Bool) async throws {
        let uid = try userId
        let path = "/Users/\(uid)/FavoriteItems/\(id)"
        try await http.send(isFavorite ? .post : .delete, path: path)
    }

    public func setWatched(id: String, isWatched: Bool) async throws {
        let uid = try userId
        let path = "/Users/\(uid)/PlayedItems/\(id)"
        try await http.send(isWatched ? .post : .delete, path: path)
    }
}
