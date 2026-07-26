import Foundation

public enum SampleData {
    public static let server = Server(
        id: "sample-server",
        name: "リビングのJellyfin",
        url: URL(string: "https://jellyfin.example.local")!,
        version: "10.10.0"
    )

    public static let users: [StoredUser] = [
        StoredUser(
            profile: UserProfile(
                id: "user-1",
                name: "ヤチヨ",
                serverId: server.id,
                primaryImageURL: poster(seed: "user1", width: 400, height: 400)
            ),
            server: server
        ),
        StoredUser(
            profile: UserProfile(
                id: "user-2",
                name: "いろP",
                serverId: server.id,
                primaryImageURL: poster(seed: "user2", width: 400, height: 400)
            ),
            server: server
        ),
        StoredUser(
            profile: UserProfile(
                id: "user-3",
                name: "キッズ",
                serverId: server.id,
                primaryImageURL: poster(seed: "user3", width: 400, height: 400),
                hasParentalControls: true
            ),
            server: server
        )
    ]

    public static let heroFeatured: MediaItem = movies[0]

    public static let movies: [MediaItem] = [
        movie(id: "m-1", title: "星降る夜のカプチーノ", year: 2024, runtimeMin: 118, rating: "PG-13", community: 8.4, poster: "movie1"),
        movie(id: "m-2", title: "月の裏側で待ってる", year: 2023, runtimeMin: 132, rating: "R", community: 7.8, poster: "movie2"),
        movie(id: "m-3", title: "ウミウシと私", year: 2022, runtimeMin: 96, rating: "G", community: 8.9, poster: "movie3"),
        movie(id: "m-4", title: "8000年目の告白", year: 2025, runtimeMin: 145, rating: "PG-13", community: 9.1, poster: "movie4"),
        movie(id: "m-5", title: "電子の海の歌姫", year: 2024, runtimeMin: 108, rating: "PG", community: 8.2, poster: "movie5"),
        movie(id: "m-6", title: "縄文の少年", year: 2021, runtimeMin: 122, rating: "PG-13", community: 7.5, poster: "movie6"),
        movie(id: "m-7", title: "アメンボロード", year: 2023, runtimeMin: 89, rating: "G", community: 6.8, poster: "movie7"),
        movie(id: "m-8", title: "玉藻の前", year: 2022, runtimeMin: 156, rating: "R", community: 8.7, poster: "movie8"),
        movie(id: "m-9", title: "花魁への道", year: 2020, runtimeMin: 134, rating: "R", community: 8.0, poster: "movie9"),
        movie(id: "m-10", title: "焼け跡の花売り", year: 2019, runtimeMin: 110, rating: "PG-13", community: 8.5, poster: "movie10"),
    ]

    public static let series: [MediaItem] = [
        seriesItem(id: "s-1", title: "ツクヨミ管理人日誌", year: 2024, rating: "PG", community: 8.6, poster: "series1"),
        seriesItem(id: "s-2", title: "神々のみんなへ", year: 2023, rating: "PG-13", community: 9.0, poster: "series2"),
        seriesItem(id: "s-3", title: "ヤチヨカップ戦記", year: 2022, rating: "PG", community: 7.9, poster: "series3"),
        seriesItem(id: "s-4", title: "帝アキラのカッコいい一日", year: 2024, rating: "PG-13", community: 8.3, poster: "series4"),
        seriesItem(id: "s-5", title: "まみまみのグルメ探検", year: 2023, rating: "G", community: 8.8, poster: "series5"),
        seriesItem(id: "s-6", title: "ブラックオニキス", year: 2022, rating: "PG-13", community: 8.1, poster: "series6"),
    ]

    public static let continueWatching: [MediaItem] = [
        withProgress(movies[3], fraction: 0.42),
        withProgress(series[0], fraction: 0.15),
        withProgress(movies[7], fraction: 0.78),
        withProgress(series[3], fraction: 0.55)
    ]

    public static let nextUp: [MediaItem] = [
        series[0],
        series[1],
        series[4]
    ]

    public static let favorites: [MediaItem] = [
        movies[3],
        movies[7],
        series[1],
        series[4],
        movies[5]
    ].map { toggleFavorite($0) }

    public static let randomForRewatch: [MediaItem] = [
        toggleWatched(movies[2]),
        toggleWatched(movies[6]),
        toggleWatched(series[2]),
        toggleWatched(movies[8])
    ]

    public static let latestMovies: [MediaItem] = Array(movies.prefix(6))
    public static let latestSeries: [MediaItem] = Array(series.prefix(5))

    public static func detail(for item: MediaItem) -> MediaDetail {
        MediaDetail(
            item: item,
            overview: overviewText(for: item),
            genres: ["ドラマ", "ファンタジー", "SF"],
            tagline: "8000年待った、この夜のために。",
            mediaSources: [
                MediaSourceInfo(
                    id: "src-\(item.id)",
                    container: "mkv",
                    videoCodec: "hevc",
                    videoProfile: "Main 10",
                    width: 3840,
                    height: 2160,
                    videoBitrate: 25_000_000,
                    audioTracks: [
                        AudioTrackDescriptor(
                            id: 1,
                            language: "jpn",
                            codec: "eac3",
                            channels: 6,
                            displayTitle: "日本語 · Dolby Digital+ 5.1",
                            spatialFormat: "DolbyAtmos"
                        ),
                        AudioTrackDescriptor(id: 2, language: "eng", codec: "aac", channels: 2, displayTitle: "English · AAC 2.0")
                    ],
                    subtitleTracks: [
                        SubtitleTrackDescriptor(id: 1, language: "jpn", codec: "srt", displayTitle: "日本語"),
                        SubtitleTrackDescriptor(id: 2, language: "eng", codec: "srt", displayTitle: "English"),
                        SubtitleTrackDescriptor(id: 3, language: "jpn", codec: "pgssub", isImageBased: true, displayTitle: "日本語（画像字幕）")
                    ],
                    videoRange: "HDR",
                    videoRangeType: "DOVIWithHDR10",
                    bitDepth: 10,
                    colorSpace: "bt2020nc",
                    pixelFormat: "yuv420p10le",
                    frameRate: 23.976,
                    videoLevel: 153
                )
            ]
        )
    }

    public static func seasons(for seriesId: String) -> [Season] {
        (1...3).map { number in
            Season(
                id: "season-\(seriesId)-\(number)",
                seriesId: seriesId,
                number: number,
                name: "シーズン \(number)",
                episodeCount: 10,
                posterURL: poster(seed: "season-\(seriesId)-\(number)", width: 300, height: 450)
            )
        }
    }

    public static func episodes(for seasonId: String) -> [Episode] {
        (1...10).map { number in
            Episode(
                id: "\(seasonId)-ep\(number)",
                seriesId: "series-from-\(seasonId)",
                seasonId: seasonId,
                seasonNumber: 1,
                episodeNumber: number,
                title: "第\(number)話 きみと出会った日",
                overview: "ある日、ツクヨミにやってきたゲストと出会う。全てはそこから始まった…",
                runtimeSeconds: 45 * 60,
                thumbnailURL: poster(seed: "\(seasonId)-\(number)", width: 480, height: 270),
                progressFraction: number == 1 ? 0.85 : nil,
                isWatched: number == 1
            )
        }
    }

    public static let syncPlayGroups: [SyncPlayGroup] = [
        SyncPlayGroup(
            id: "grp-1",
            name: "金曜映画会",
            currentItemId: movies[3].id,
            participants: [
                SyncPlayParticipant(id: "user-2", userName: "いろP", isOnline: true),
                SyncPlayParticipant(id: "user-4", userName: "まみまみ", isOnline: true),
                SyncPlayParticipant(id: "user-5", userName: "ROKA", isOnline: false)
            ]
        )
    ]

    // MARK: - Helpers

    private static func movie(id: String, title: String, year: Int, runtimeMin: Int, rating: String, community: Double, poster posterSeed: String) -> MediaItem {
        MediaItem(
            id: id,
            kind: .movie,
            title: title,
            year: year,
            runtimeSeconds: runtimeMin * 60,
            officialRating: rating,
            communityRating: community,
            posterURL: poster(seed: posterSeed, width: 400, height: 600),
            backdropURL: poster(seed: "\(posterSeed)-bd", width: 1920, height: 1080),
            logoURL: nil,
            overview: sampleOverview(seed: id),
            genres: sampleGenres(seed: id, kind: .movie)
        )
    }

    private static func seriesItem(id: String, title: String, year: Int, rating: String, community: Double, poster posterSeed: String) -> MediaItem {
        MediaItem(
            id: id,
            kind: .series,
            title: title,
            year: year,
            runtimeSeconds: nil,
            officialRating: rating,
            communityRating: community,
            posterURL: poster(seed: posterSeed, width: 400, height: 600),
            backdropURL: poster(seed: "\(posterSeed)-bd", width: 1920, height: 1080),
            logoURL: nil,
            overview: sampleOverview(seed: id),
            genres: sampleGenres(seed: id, kind: .series)
        )
    }

    private static func withProgress(_ item: MediaItem, fraction: Double) -> MediaItem {
        MediaItem(
            id: item.id, kind: item.kind, title: item.title, year: item.year,
            runtimeSeconds: item.runtimeSeconds, officialRating: item.officialRating,
            communityRating: item.communityRating, posterURL: item.posterURL,
            backdropURL: item.backdropURL, logoURL: item.logoURL,
            overview: item.overview, genres: item.genres,
            progressFraction: fraction, isFavorite: item.isFavorite, isWatched: item.isWatched
        )
    }

    private static func toggleFavorite(_ item: MediaItem) -> MediaItem {
        MediaItem(
            id: item.id, kind: item.kind, title: item.title, year: item.year,
            runtimeSeconds: item.runtimeSeconds, officialRating: item.officialRating,
            communityRating: item.communityRating, posterURL: item.posterURL,
            backdropURL: item.backdropURL, logoURL: item.logoURL,
            overview: item.overview, genres: item.genres,
            progressFraction: item.progressFraction, isFavorite: true, isWatched: item.isWatched
        )
    }

    private static func toggleWatched(_ item: MediaItem) -> MediaItem {
        MediaItem(
            id: item.id, kind: item.kind, title: item.title, year: item.year,
            runtimeSeconds: item.runtimeSeconds, officialRating: item.officialRating,
            communityRating: item.communityRating, posterURL: item.posterURL,
            backdropURL: item.backdropURL, logoURL: item.logoURL,
            overview: item.overview, genres: item.genres,
            progressFraction: item.progressFraction, isFavorite: item.isFavorite, isWatched: true
        )
    }

    private static let overviewBank: [String] = [
        "8000年ぶりに動き出した歯車が、ある夜、ひとりの少女と少年の運命を交差させる。過去と現在、電子と現実、その境界で語られる、忘れられない物語。",
        "眠らない街のはずれ、月が沈む時間だけに開くカフェ。訪れる者たちが抱える秘密が、湯気の向こうでゆっくりと解けていく。",
        "静かな海辺の町を舞台に、失われた記憶と、それでもなお残り続ける温度を描く、静かで確かな喪失のドラマ。",
        "仮想空間ツクヨミの深部で起こった小さな異変。それは、遠い星から届いたひとつの信号がきっかけだった。",
        "誰にも言えなかった夏の日の約束。10年越しに交差する4人の視点で紡がれる、群像青春譚。"
    ]

    private static let movieGenreBank: [[String]] = [
        ["ドラマ", "ロマンス"],
        ["SF", "ミステリー"],
        ["アクション", "スリラー"],
        ["ヒューマン", "ドキュメンタリー"],
        ["ファンタジー", "冒険"]
    ]

    private static let seriesGenreBank: [[String]] = [
        ["ドラマ", "コメディ"],
        ["SF", "ミステリー"],
        ["リアリティ", "バラエティ"],
        ["アニメ", "ファンタジー"]
    ]

    private static func stableIndex(_ seed: String, modulo: Int) -> Int {
        let sum = seed.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return abs(sum) % modulo
    }

    private static func sampleOverview(seed: String) -> String {
        overviewBank[stableIndex(seed, modulo: overviewBank.count)]
    }

    private static func sampleGenres(seed: String, kind: MediaKind) -> [String] {
        let bank = kind == .movie ? movieGenreBank : seriesGenreBank
        return bank[stableIndex(seed, modulo: bank.count)]
    }

    private static func poster(seed: String, width: Int, height: Int) -> URL {
        URL(string: "https://picsum.photos/seed/\(seed)/\(width)/\(height)")!
    }

    private static func overviewText(for item: MediaItem) -> String {
        "\(item.title)。8000年ぶりに動き出した歯車が、ある夜、ひとりの少女と少年の運命を交差させる。過去と現在、電子と現実、その境界で語られる、忘れられない物語。"
    }
}
