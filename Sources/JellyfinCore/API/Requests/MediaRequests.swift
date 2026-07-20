import Foundation
import Alamofire

/// Common `Fields` parameter used across list-style endpoints. Match the
/// original `JellyfinMediaService.baseListFields` verbatim so migration is
/// behaviour-preserving.
private let baseListFields = "PrimaryImageAspectRatio,BasicSyncInfo,MediaSourceCount,Overview,Genres,Taglines,ChildCount,Path,Trickplay"

// MARK: - Hero / shelves (BaseItemQueryResult)

struct HeroFeaturedRequest: JFRequest {
    typealias Response = BaseItemQueryResultDTO
    let method: HTTPMethod = .get
    let userId: String
    var path: String { "/Users/\(userId)/Items" }
    var query: [String: String?] {
        [
            "SortBy": "Random",
            "Limit": "1",
            "IncludeItemTypes": "Movie",
            "Recursive": "true",
            "Fields": baseListFields,
            "ImageTypeLimit": "1",
            "EnableImageTypes": "Primary,Backdrop,Logo"
        ]
    }
}

struct ContinueWatchingRequest: JFRequest {
    typealias Response = BaseItemQueryResultDTO
    let method: HTTPMethod = .get
    let userId: String
    var path: String { "/Users/\(userId)/Items/Resume" }
    var query: [String: String?] {
        [
            "Limit": "12",
            "MediaTypes": "Video",
            "Fields": baseListFields,
            "EnableImageTypes": "Primary,Backdrop,Thumb,Logo"
        ]
    }
}

struct NextUpRequest: JFRequest {
    typealias Response = BaseItemQueryResultDTO
    let method: HTTPMethod = .get
    var path: String { "/Shows/NextUp" }
    let userId: String
    let seriesId: String?
    let limit: Int
    let fields: String

    init(userId: String, seriesId: String? = nil, limit: Int = 12, fields: String = baseListFields) {
        self.userId = userId
        self.seriesId = seriesId
        self.limit = limit
        self.fields = fields
    }

    var query: [String: String?] {
        var q: [String: String?] = [
            "UserId": userId,
            "Limit": "\(limit)",
            "Fields": fields,
            "EnableImageTypes": "Primary,Backdrop,Thumb,Logo"
        ]
        if let seriesId {
            q["SeriesId"] = seriesId
        }
        return q
    }
}

struct FavoritesRequest: JFRequest {
    typealias Response = BaseItemQueryResultDTO
    let method: HTTPMethod = .get
    let userId: String
    var path: String { "/Users/\(userId)/Items" }
    var query: [String: String?] {
        [
            "IsFavorite": "true",
            "Recursive": "true",
            "IncludeItemTypes": "Movie,Series",
            "Limit": "40",
            "SortBy": "SortName",
            "SortOrder": "Ascending",
            "Fields": baseListFields
        ]
    }
}

struct RandomForRewatchRequest: JFRequest {
    typealias Response = BaseItemQueryResultDTO
    let method: HTTPMethod = .get
    let userId: String
    var path: String { "/Users/\(userId)/Items" }
    var query: [String: String?] {
        [
            "SortBy": "Random",
            "Filters": "IsPlayed",
            "Limit": "16",
            "Recursive": "true",
            "IncludeItemTypes": "Movie,Series",
            "Fields": baseListFields
        ]
    }
}

// MARK: - Latest (returns raw array, not a QueryResult)

struct LatestItemsRequest: JFRequest {
    typealias Response = [BaseItemDTO]
    let method: HTTPMethod = .get
    let userId: String
    let includeItemTypes: String
    let limit: Int

    init(userId: String, includeItemTypes: String, limit: Int = 30) {
        self.userId = userId
        self.includeItemTypes = includeItemTypes
        self.limit = limit
    }

    var path: String { "/Users/\(userId)/Items/Latest" }
    var query: [String: String?] {
        [
            "IncludeItemTypes": includeItemTypes,
            "Limit": "\(limit)",
            "Fields": baseListFields,
            "EnableImageTypes": "Primary,Backdrop,Logo"
        ]
    }
}

/// Random discovery shelf — same shape as `RandomForRewatchRequest` but
/// without the `IsPlayed` filter so it works for fresh accounts that
/// haven't accumulated a watch history yet.
struct RandomSuggestionsRequest: JFRequest {
    typealias Response = BaseItemQueryResultDTO
    let method: HTTPMethod = .get
    let userId: String
    var path: String { "/Users/\(userId)/Items" }
    var query: [String: String?] {
        [
            "SortBy": "Random",
            "Limit": "30",
            "Recursive": "true",
            "IncludeItemTypes": "Movie,Series",
            "Fields": baseListFields
        ]
    }
}

// MARK: - Genres

/// `/Genres` returns one BaseItemDTO per genre (Type = "Genre", Name = the
/// genre label). Callers only need the names, so implementations map to
/// `[String]`.
struct GenresRequest: JFRequest {
    typealias Response = BaseItemQueryResultDTO
    let method: HTTPMethod = .get
    var path: String { "/Genres" }
    let userId: String
    let includeItemTypes: String

    var query: [String: String?] {
        [
            "UserId": userId,
            "IncludeItemTypes": includeItemTypes,
            "Recursive": "true",
            "SortBy": "SortName",
            "SortOrder": "Ascending",
            "EnableTotalRecordCount": "false"
        ]
    }
}

/// One-genre shelf fetch — `/Items?Genres={name}` filtered to the same
/// `IncludeItemTypes` used to list the genres. Random sort so the shelf
/// varies between visits instead of always leading with the same title.
struct ItemsByGenreRequest: JFRequest {
    typealias Response = BaseItemQueryResultDTO
    let method: HTTPMethod = .get
    let userId: String
    let genre: String
    let includeItemTypes: String
    let limit: Int

    init(userId: String, genre: String, includeItemTypes: String, limit: Int = 20) {
        self.userId = userId
        self.genre = genre
        self.includeItemTypes = includeItemTypes
        self.limit = limit
    }

    var path: String { "/Users/\(userId)/Items" }
    var query: [String: String?] {
        [
            "Genres": genre,
            "IncludeItemTypes": includeItemTypes,
            "Recursive": "true",
            "SortBy": "SortName",
            "SortOrder": "Ascending",
            "Limit": "\(limit)",
            "Fields": baseListFields,
            "ImageTypeLimit": "1",
            "EnableImageTypes": "Primary,Backdrop,Logo"
        ]
    }
}

// MARK: - Detail

struct ItemDetailRequest: JFRequest {
    typealias Response = BaseItemDTO
    let method: HTTPMethod = .get
    let userId: String
    let itemId: String
    var path: String { "/Users/\(userId)/Items/\(itemId)" }
    var query: [String: String?] {
        [
            "Fields": "Overview,Genres,Taglines,MediaSources,MediaStreams,People,Studios,ProductionYear,CommunityRating,OfficialRating,Trickplay,ChildCount,RecursiveItemCount"
        ]
    }
}

/// Lightweight lookup used to resolve `SeriesId` from a season id (Jellyfin's
/// `/Shows/{seriesId}/Episodes` endpoint requires the series id, but callers
/// often only have the season id).
struct ItemLookupRequest: JFRequest {
    typealias Response = BaseItemDTO
    let method: HTTPMethod = .get
    let userId: String
    let itemId: String
    var path: String { "/Users/\(userId)/Items/\(itemId)" }
}

// MARK: - Series / seasons / episodes

struct SeasonsRequest: JFRequest {
    typealias Response = BaseItemQueryResultDTO
    let method: HTTPMethod = .get
    let seriesId: String
    let userId: String
    var path: String { "/Shows/\(seriesId)/Seasons" }
    var query: [String: String?] {
        [
            "UserId": userId,
            "Fields": "ChildCount,PrimaryImageAspectRatio"
        ]
    }
}

struct EpisodesRequest: JFRequest {
    typealias Response = BaseItemQueryResultDTO
    let method: HTTPMethod = .get
    let seriesId: String
    let userId: String
    let seasonId: String
    var path: String { "/Shows/\(seriesId)/Episodes" }
    var query: [String: String?] {
        [
            "UserId": userId,
            "SeasonId": seasonId,
            "Fields": "Overview,PrimaryImageAspectRatio,Path,MediaSources,MediaStreams,Trickplay"
        ]
    }
}

// MARK: - Search

struct SearchHintsRequest: JFRequest {
    typealias Response = SearchHintResultDTO
    let method: HTTPMethod = .get
    var path: String { "/Search/Hints" }
    let userId: String
    let searchTerm: String
    let includeItemTypes: String
    let limit: Int

    init(userId: String, searchTerm: String, includeItemTypes: String = "Movie,Series,Episode", limit: Int = 50) {
        self.userId = userId
        self.searchTerm = searchTerm
        self.includeItemTypes = includeItemTypes
        self.limit = limit
    }

    var query: [String: String?] {
        [
            "SearchTerm": searchTerm,
            "Limit": "\(limit)",
            "UserId": userId,
            "IncludeItemTypes": includeItemTypes
        ]
    }
}

// MARK: - Favourites / played state (void endpoints)

struct SetFavoriteRequest: JFRequest {
    typealias Response = JFEmptyResponse
    let userId: String
    let itemId: String
    let isFavorite: Bool
    var method: HTTPMethod { isFavorite ? .post : .delete }
    var path: String { "/Users/\(userId)/FavoriteItems/\(itemId)" }
}

struct SetWatchedRequest: JFRequest {
    typealias Response = JFEmptyResponse
    let userId: String
    let itemId: String
    let isWatched: Bool
    var method: HTTPMethod { isWatched ? .post : .delete }
    var path: String { "/Users/\(userId)/PlayedItems/\(itemId)" }
}
