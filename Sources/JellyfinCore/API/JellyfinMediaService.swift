import Foundation
import Alamofire

/// Real implementation of `MediaService`. Every endpoint documented in the
/// contract maps 1:1 to a Jellyfin route via a `JFRequest`; call sites here
/// are deliberately mechanical so it's easy to audit against the OpenAPI spec.
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

    // MARK: - Shelves

    public func fetchHeroFeatured() async throws -> MediaItem? {
        let uid = try userId
        let result = try await http.send(HeroFeaturedRequest(userId: uid))
        return result.items.first.map { $0.toMediaItem(server: server) }
    }

    public func fetchContinueWatching() async throws -> [MediaItem] {
        let uid = try userId
        let result = try await http.send(ContinueWatchingRequest(userId: uid))
        return result.items.map { $0.toMediaItem(server: server) }
    }

    public func fetchNextUp() async throws -> [MediaItem] {
        let uid = try userId
        let result = try await http.send(NextUpRequest(userId: uid))
        return result.items.map { $0.toMediaItem(server: server) }
    }

    public func fetchLatestMovies() async throws -> [MediaItem] {
        let uid = try userId
        let items = try await http.send(LatestItemsRequest(userId: uid, includeItemTypes: "Movie"))
        return items.map { $0.toMediaItem(server: server) }
    }

    public func fetchLatestSeries() async throws -> [MediaItem] {
        let uid = try userId
        // Series Latest is served by a plain Items query sorted by
        // DateCreated — the /Items/Latest endpoint's group-by-episode
        // path is ~40s on this library. See `LatestSeriesQueryRequest`
        // for the trade-off.
        let result = try await http.send(LatestSeriesQueryRequest(userId: uid))
        return result.items.map { $0.toMediaItem(server: server) }
    }

    public func fetchFavorites() async throws -> [MediaItem] {
        let uid = try userId
        let result = try await http.send(FavoritesRequest(userId: uid))
        return result.items.map { $0.toMediaItem(server: server) }
    }

    public func fetchRandomForRewatch() async throws -> [MediaItem] {
        let uid = try userId
        let result = try await http.send(RandomForRewatchRequest(userId: uid))
        return result.items.map { $0.toMediaItem(server: server) }
    }

    public func fetchRandomSuggestions() async throws -> [MediaItem] {
        let uid = try userId
        let result = try await http.send(RandomSuggestionsRequest(userId: uid))
        return result.items.map { $0.toMediaItem(server: server) }
    }

    // MARK: - Genres

    public func fetchGenres(for kind: MediaKind) async throws -> [String] {
        let uid = try userId
        let result = try await http.send(GenresRequest(
            userId: uid,
            includeItemTypes: Self.mapKind(kind)
        ))
        return result.items.compactMap { $0.name?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    public func fetchItems(inGenre genre: String, kind: MediaKind) async throws -> [MediaItem] {
        let uid = try userId
        let result = try await http.send(ItemsByGenreRequest(
            userId: uid,
            genre: genre,
            includeItemTypes: Self.mapKind(kind)
        ))
        return result.items.map { $0.toMediaItem(server: server) }
    }

    // MARK: - Detail / series

    public func fetchDetail(id: String) async throws -> MediaDetail {
        let uid = try userId
        let dto = try await http.send(ItemDetailRequest(userId: uid, itemId: id))
        return dto.toDetail(server: server)
    }

    public func fetchSeasons(seriesId: String) async throws -> [Season] {
        let uid = try userId
        let result = try await http.send(SeasonsRequest(seriesId: seriesId, userId: uid))
        return result.items.map { $0.toSeason(server: server, fallbackSeriesId: seriesId) }
    }

    public func fetchEpisodes(seasonId: String) async throws -> [Episode] {
        let uid = try userId
        // We need seriesId to hit /Shows/{seriesId}/Episodes; resolve via
        // the season item itself.
        let season = try await http.send(ItemLookupRequest(userId: uid, itemId: seasonId))
        guard let sid = season.seriesId else {
            throw JellyfinAPIError.missingField("SeriesId")
        }
        let result = try await http.send(EpisodesRequest(seriesId: sid, userId: uid, seasonId: seasonId))
        return result.items.map { $0.toEpisode(server: server) }
    }

    public func fetchNextEpisode(seriesId: String) async throws -> Episode? {
        let uid = try userId
        let result = try await http.send(NextUpRequest(
            userId: uid,
            seriesId: seriesId,
            limit: 1,
            fields: "Overview,PrimaryImageAspectRatio"
        ))
        return result.items.first.map { $0.toEpisode(server: server) }
    }

    // MARK: - Search

    public func search(query: String, kind: MediaKind?) async throws -> [MediaItem] {
        guard !query.isEmpty else { return [] }
        let uid = try userId
        let includeTypes = kind.map(Self.mapKind(_:)) ?? "Movie,Series,Episode"
        let result = try await http.send(SearchHintsRequest(
            userId: uid,
            searchTerm: query,
            includeItemTypes: includeTypes
        ))
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
        _ = try await http.send(SetFavoriteRequest(userId: uid, itemId: id, isFavorite: isFavorite))
    }

    public func setWatched(id: String, isWatched: Bool) async throws {
        let uid = try userId
        _ = try await http.send(SetWatchedRequest(userId: uid, itemId: id, isWatched: isWatched))
    }
}
