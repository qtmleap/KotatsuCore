import Foundation

public protocol MediaService: Sendable {
    func fetchHeroFeatured() async throws -> MediaItem?
    func fetchContinueWatching() async throws -> [MediaItem]
    func fetchNextUp() async throws -> [MediaItem]
    func fetchLatestMovies() async throws -> [MediaItem]
    func fetchLatestSeries() async throws -> [MediaItem]
    func fetchFavorites() async throws -> [MediaItem]
    func fetchRandomForRewatch() async throws -> [MediaItem]

    func fetchDetail(id: String) async throws -> MediaDetail
    func fetchSeasons(seriesId: String) async throws -> [Season]
    func fetchEpisodes(seasonId: String) async throws -> [Episode]
    func fetchNextEpisode(seriesId: String) async throws -> Episode?

    func search(query: String, kind: MediaKind?) async throws -> [MediaItem]

    func setFavorite(id: String, isFavorite: Bool) async throws
    func setWatched(id: String, isWatched: Bool) async throws
}
