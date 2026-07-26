import XCTest
@testable import KotatsuCore

final class KotatsuCoreTests: XCTestCase {
    func testMockContainerBuildsSuccessfully() async throws {
        let container = ServiceContainer.mock()
        let users = await container.auth.storedUsers()
        XCTAssertFalse(users.isEmpty)

        let hero = try await container.media.fetchHeroFeatured()
        XCTAssertNotNil(hero)

        let continueWatching = try await container.media.fetchContinueWatching()
        XCTAssertFalse(continueWatching.isEmpty)
    }

    func testSampleDataHasExpectedShelves() async throws {
        let service = MockMediaService()
        let latestMovies = try await service.fetchLatestMovies()
        XCTAssertEqual(latestMovies.count, 6)
        let latestSeries = try await service.fetchLatestSeries()
        XCTAssertEqual(latestSeries.count, 5)
        let favs = try await service.fetchFavorites()
        XCTAssertTrue(favs.allSatisfy { $0.isFavorite })
    }
}
