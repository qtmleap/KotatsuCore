import Foundation

public protocol MediaService: Sendable {
    func fetchHeroFeatured() async throws -> MediaItem?
    func fetchContinueWatching() async throws -> [MediaItem]
    func fetchNextUp() async throws -> [MediaItem]
    func fetchLatestMovies() async throws -> [MediaItem]
    func fetchLatestSeries() async throws -> [MediaItem]
    func fetchFavorites() async throws -> [MediaItem]
    func fetchRandomForRewatch() async throws -> [MediaItem]
    /// Random items with **no** played-state filter — useful for fresh
    /// accounts where Continue Watching / Rewatch shelves would be empty.
    func fetchRandomSuggestions() async throws -> [MediaItem]

    /// Genre names available under the given item type (Series / Movie).
    /// Ordering follows the server (SortName ASC).
    func fetchGenres(for kind: MediaKind) async throws -> [String]
    /// Items belonging to `genre`, restricted to `kind`. Bounded — used to
    /// populate one shelf row, not a full library grid.
    func fetchItems(inGenre genre: String, kind: MediaKind) async throws -> [MediaItem]

    func fetchDetail(id: String) async throws -> MediaDetail
    func fetchSeasons(seriesId: String) async throws -> [Season]
    func fetchEpisodes(seasonId: String) async throws -> [Episode]
    func fetchNextEpisode(seriesId: String) async throws -> Episode?

    func search(query: String, kind: MediaKind?) async throws -> [MediaItem]

    func setFavorite(id: String, isFavorite: Bool) async throws
    func setWatched(id: String, isWatched: Bool) async throws
}
