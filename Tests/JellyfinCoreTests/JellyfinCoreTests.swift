import Testing
@testable import JellyfinCore

@Test func mockContainerBuildsSuccessfully() async throws {
    let container = ServiceContainer.mock()
    let users = await container.auth.storedUsers()
    #expect(!users.isEmpty)

    let hero = try await container.media.fetchHeroFeatured()
    #expect(hero != nil)

    let continueWatching = try await container.media.fetchContinueWatching()
    #expect(!continueWatching.isEmpty)
}

@Test func sampleDataHasExpectedShelves() async throws {
    let service = MockMediaService()
    #expect(try await service.fetchLatestMovies().count == 6)
    #expect(try await service.fetchLatestSeries().count == 5)
    #expect(try await service.fetchFavorites().allSatisfy { $0.isFavorite })
}
