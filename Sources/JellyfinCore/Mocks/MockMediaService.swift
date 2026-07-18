import Foundation

public struct MockMediaService: MediaService {
    public init() {}

    private func delay() async throws {
        try await Task.sleep(for: .milliseconds(200))
    }

    public func fetchHeroFeatured() async throws -> MediaItem? {
        try await delay(); return SampleData.heroFeatured
    }

    public func fetchContinueWatching() async throws -> [MediaItem] {
        try await delay(); return SampleData.continueWatching
    }

    public func fetchNextUp() async throws -> [MediaItem] {
        try await delay(); return SampleData.nextUp
    }

    public func fetchLatestMovies() async throws -> [MediaItem] {
        try await delay(); return SampleData.latestMovies
    }

    public func fetchLatestSeries() async throws -> [MediaItem] {
        try await delay(); return SampleData.latestSeries
    }

    public func fetchFavorites() async throws -> [MediaItem] {
        try await delay(); return SampleData.favorites
    }

    public func fetchRandomForRewatch() async throws -> [MediaItem] {
        try await delay(); return SampleData.randomForRewatch
    }

    public func fetchDetail(id: String) async throws -> MediaDetail {
        try await delay()
        let item = (SampleData.movies + SampleData.series).first { $0.id == id } ?? SampleData.movies[0]
        return SampleData.detail(for: item)
    }

    public func fetchSeasons(seriesId: String) async throws -> [Season] {
        try await delay(); return SampleData.seasons(for: seriesId)
    }

    public func fetchEpisodes(seasonId: String) async throws -> [Episode] {
        try await delay(); return SampleData.episodes(for: seasonId)
    }

    public func fetchNextEpisode(seriesId: String) async throws -> Episode? {
        try await delay()
        let seasons = SampleData.seasons(for: seriesId)
        guard let first = seasons.first else { return nil }
        return SampleData.episodes(for: first.id).first { !$0.isWatched }
    }

    public func search(query: String, kind: MediaKind?) async throws -> [MediaItem] {
        try await delay()
        let pool = SampleData.movies + SampleData.series
        let filtered = kind.map { k in pool.filter { $0.kind == k } } ?? pool
        guard !query.isEmpty else { return filtered }
        return filtered.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    public func setFavorite(id: String, isFavorite: Bool) async throws { try await delay() }
    public func setWatched(id: String, isWatched: Bool) async throws { try await delay() }
}
