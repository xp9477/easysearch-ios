import Combine
import Foundation
import Security

private extension String {
    var cloudNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum HiddenCloudMerge {
    static func albums(primary: [HiddenAlbum], secondary: [HiddenAlbum]) -> [HiddenAlbum] {
        var seen = Set<String>()
        var merged: [HiddenAlbum] = []

        for album in primary + secondary {
            if seen.insert(album.id).inserted {
                merged.append(album)
            }
        }

        return merged
    }

    static func imageURLs(primary: [URL], secondary: [URL]) -> [URL] {
        var seen = Set<String>()
        var merged: [URL] = []

        for url in (primary + secondary).map(Hidden4KHDURLNormalizer.normalizeImageURL) {
            if seen.insert(url.absoluteString).inserted {
                merged.append(url)
            }
        }

        return merged
    }

    static func movies(primary: [HiddenJavDBMovie], secondary: [HiddenJavDBMovie]) -> [HiddenJavDBMovie] {
        var seen = Set<String>()
        var merged: [HiddenJavDBMovie] = []

        for movie in primary + secondary {
            if seen.insert(movie.id).inserted {
                merged.append(movie)
            }
        }

        return merged
    }

    static func playbacks(
        primary: [HiddenJavDBFavoritePlayback],
        secondary: [HiddenJavDBFavoritePlayback]
    ) -> [HiddenJavDBFavoritePlayback] {
        let candidates = (primary + secondary).sorted { $0.createdAt > $1.createdAt }
        var merged: [HiddenJavDBFavoritePlayback] = []
        var seenIDs = Set<UUID>()

        for playback in candidates {
            if !seenIDs.insert(playback.id).inserted {
                continue
            }

            if merged.contains(where: { $0.matchesSamePlayback(as: playback) }) {
                continue
            }

            merged.append(playback)
        }

        if merged.count > 120 {
            return Array(merged.prefix(120))
        }
        return merged
    }

    static func utEntries(primary: [UTEntry], secondary: [UTEntry]) -> [UTEntry] {
        let calendar = Calendar.utTracker
        let candidates = (primary + secondary).sorted { lhs, rhs in
            if calendar.isDate(lhs.date, inSameDayAs: rhs.date) {
                return lhs.createdAt > rhs.createdAt
            }

            return lhs.date > rhs.date
        }

        var merged: [UTEntry] = []
        var seenIDs = Set<UUID>()

        for entry in candidates {
            if seenIDs.insert(entry.id).inserted {
                merged.append(entry)
            }
        }

        return merged
    }
}

private enum Hidden4KHDURLNormalizer {
    static func normalizeImageURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        let host = components.host?.lowercased() ?? ""

        if host == "i0.wp.com" && components.path.hasPrefix("/pic.4khd.com/") {
            components.host = "img.4khd.com"
            components.path = components.path.replacingOccurrences(of: "/pic.4khd.com", with: "", options: .anchored)
            return components.url ?? url
        }

        if host == "pic.4khd.com" {
            components.host = "img.4khd.com"
            return components.url ?? url
        }

        return url
    }

    static func normalizeAlbumURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        if components.host == nil {
            components.host = "www.4khd.com"
            components.scheme = "https"
        }

        return components.url ?? url
    }
}

private enum HiddenJavDBURLNormalizer {
    static func normalizeMovieURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        if components.host == nil {
            components.scheme = "https"
            components.host = "javdb.com"
        }

        components.query = nil
        components.fragment = nil
        return components.url ?? url
    }

    static func normalizeImageURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        if components.host == nil {
            components.scheme = "https"
            components.host = "javdb.com"
        }

        return components.url ?? url
    }
}

enum Hidden4KHDLocalStore {
    static let favoriteAlbumsKey = "hidden_space.favorite_albums.v1"
    static let favoriteImagesKey = "hidden_space.favorite_images.v1"

    static func loadFavoriteAlbums() -> [HiddenAlbum] {
        guard let data = UserDefaults.standard.data(forKey: favoriteAlbumsKey),
              let albums = try? JSONDecoder().decode([HiddenAlbum].self, from: data) else {
            return []
        }

        return albums.map { album in
            HiddenAlbum(
                url: Hidden4KHDURLNormalizer.normalizeAlbumURL(album.url),
                title: album.title,
                coverURL: Hidden4KHDURLNormalizer.normalizeImageURL(album.coverURL)
            )
        }
    }

    static func saveFavoriteAlbums(_ albums: [HiddenAlbum]) {
        guard let data = try? JSONEncoder().encode(albums) else { return }
        UserDefaults.standard.set(data, forKey: favoriteAlbumsKey)
    }

    static func loadFavoriteImages() -> [URL] {
        guard let data = UserDefaults.standard.data(forKey: favoriteImagesKey) else {
            return []
        }

        if let rawURLs = try? JSONDecoder().decode([String].self, from: data) {
            return rawURLs
                .compactMap(URL.init(string:))
                .map(Hidden4KHDURLNormalizer.normalizeImageURL)
        }

        if let urls = try? JSONDecoder().decode([URL].self, from: data) {
            let normalized = urls.map(Hidden4KHDURLNormalizer.normalizeImageURL)
            saveFavoriteImages(normalized)
            return normalized
        }

        return []
    }

    static func saveFavoriteImages(_ imageURLs: [URL]) {
        let payload = imageURLs.map { Hidden4KHDURLNormalizer.normalizeImageURL($0).absoluteString }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: favoriteImagesKey)
    }
}

enum HiddenJavDBLocalStore {
    static let favoriteMoviesKey = "hidden_space.javdb.favorite_movies.v1"
    static let favoritePlaybacksKey = "hidden_space.javdb.favorite_playbacks.v1"

    static func loadFavoriteMovies() -> [HiddenJavDBMovie] {
        guard let data = UserDefaults.standard.data(forKey: favoriteMoviesKey),
              let movies = try? JSONDecoder().decode([HiddenJavDBMovie].self, from: data) else {
            return []
        }

        return movies.map { movie in
            HiddenJavDBMovie(
                url: HiddenJavDBURLNormalizer.normalizeMovieURL(movie.url),
                code: movie.code,
                title: movie.title,
                coverURL: HiddenJavDBURLNormalizer.normalizeImageURL(movie.coverURL),
                actresses: movie.actresses
            )
        }
    }

    static func saveFavoriteMovies(_ movies: [HiddenJavDBMovie]) {
        guard let data = try? JSONEncoder().encode(movies) else { return }
        UserDefaults.standard.set(data, forKey: favoriteMoviesKey)
    }

    static func loadFavoritePlaybacks() -> [HiddenJavDBFavoritePlayback] {
        guard let data = UserDefaults.standard.data(forKey: favoritePlaybacksKey),
              let playbacks = try? JSONDecoder().decode([HiddenJavDBFavoritePlayback].self, from: data) else {
            return []
        }

        return playbacks.map { playback in
            HiddenJavDBFavoritePlayback(
                id: playback.id,
                movie: HiddenJavDBMovie(
                    url: HiddenJavDBURLNormalizer.normalizeMovieURL(playback.movie.url),
                    code: playback.movie.code,
                    title: playback.movie.title,
                    coverURL: HiddenJavDBURLNormalizer.normalizeImageURL(playback.movie.coverURL),
                    actresses: playback.movie.actresses
                ),
                sourceName: playback.sourceName,
                streamURL: playback.streamURL,
                refererURL: playback.refererURL,
                positionSeconds: max(0, playback.positionSeconds),
                createdAt: playback.createdAt
            )
        }
    }

    static func saveFavoritePlaybacks(_ playbacks: [HiddenJavDBFavoritePlayback]) {
        guard let data = try? JSONEncoder().encode(playbacks) else { return }
        UserDefaults.standard.set(data, forKey: favoritePlaybacksKey)
    }
}

struct HiddenSupabaseConfiguration {
    let baseURL: URL
    let publishableKey: String
    let schema: String

    var projectHost: String {
        baseURL.host ?? baseURL.absoluteString
    }

    static var current: HiddenSupabaseConfiguration? {
        guard
            let rawURL = (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            let rawKey = (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            let baseURL = URL(string: rawURL),
            !rawURL.isEmpty,
            !rawKey.isEmpty
        else {
            return nil
        }

        let schema = ((Bundle.main.object(forInfoDictionaryKey: "SUPABASE_SCHEMA") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .cloudNonEmpty) ?? "easysearch"

        return HiddenSupabaseConfiguration(
            baseURL: baseURL,
            publishableKey: rawKey,
            schema: schema
        )
    }
}

enum HiddenSupabaseAuthOutcome {
    case authenticated(HiddenSupabaseSession)
    case confirmationRequired(String)
}

struct HiddenSupabaseSession: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let userID: UUID?
    let email: String?

    var needsRefresh: Bool {
        expiresAt.timeIntervalSinceNow <= 120
    }
}

private struct HiddenSupabaseErrorPayload: Decodable {
    let message: String?
    let msg: String?
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case message
        case msg
        case error
        case errorDescription = "error_description"
    }

    var resolvedMessage: String? {
        message ?? msg ?? errorDescription ?? error
    }
}

private struct HiddenSupabaseFavoriteRow: Decodable {
    let movie_id: String
    let movie_url: String
    let code: String
    let title: String
    let cover_url: String
    let actresses: [String]

    func asMovie() -> HiddenJavDBMovie? {
        guard
            let movieURL = URL(string: movie_url),
            let coverURL = URL(string: cover_url)
        else {
            return nil
        }

        return HiddenJavDBMovie(
            url: HiddenJavDBURLNormalizer.normalizeMovieURL(movieURL),
            code: code,
            title: title,
            coverURL: HiddenJavDBURLNormalizer.normalizeImageURL(coverURL),
            actresses: actresses
        )
    }
}

private struct HiddenSupabasePlaybackRow: Decodable {
    let id: UUID
    let movie_id: String
    let movie_url: String
    let code: String
    let title: String
    let cover_url: String
    let actresses: [String]
    let source_name: String
    let stream_url: String
    let referer_url: String
    let position_seconds: Double
    let created_at: String

    func asPlayback() -> HiddenJavDBFavoritePlayback? {
        guard
            let movieURL = URL(string: movie_url),
            let coverURL = URL(string: cover_url),
            let streamURL = URL(string: stream_url),
            let refererURL = URL(string: referer_url)
        else {
            return nil
        }

        return HiddenJavDBFavoritePlayback(
            id: id,
            movie: HiddenJavDBMovie(
                url: HiddenJavDBURLNormalizer.normalizeMovieURL(movieURL),
                code: code,
                title: title,
                coverURL: HiddenJavDBURLNormalizer.normalizeImageURL(coverURL),
                actresses: actresses
            ),
            sourceName: source_name,
            streamURL: streamURL,
            refererURL: refererURL,
            positionSeconds: max(0, position_seconds),
            createdAt: HiddenSupabaseDateFormatter.date(from: created_at) ?? Date()
        )
    }
}

private struct HiddenSupabaseFavoritePayload: Encodable {
    let movie_id: String
    let movie_url: String
    let code: String
    let title: String
    let cover_url: String
    let actresses: [String]

    init(movie: HiddenJavDBMovie) {
        movie_id = movie.id
        movie_url = movie.url.absoluteString
        code = movie.code
        title = movie.title
        cover_url = movie.coverURL.absoluteString
        actresses = movie.actresses
    }
}

private struct HiddenSupabasePlaybackPayload: Encodable {
    let id: UUID
    let movie_id: String
    let movie_url: String
    let code: String
    let title: String
    let cover_url: String
    let actresses: [String]
    let source_name: String
    let stream_url: String
    let referer_url: String
    let position_seconds: Double
    let created_at: String

    init(playback: HiddenJavDBFavoritePlayback) {
        id = playback.id
        movie_id = playback.movie.id
        movie_url = playback.movie.url.absoluteString
        code = playback.movie.code
        title = playback.movie.title
        cover_url = playback.movie.coverURL.absoluteString
        actresses = playback.movie.actresses
        source_name = playback.sourceName
        stream_url = playback.streamURL.absoluteString
        referer_url = playback.refererURL.absoluteString
        position_seconds = playback.positionSeconds
        created_at = HiddenSupabaseDateFormatter.string(from: playback.createdAt)
    }
}

private struct HiddenSupabase4KHDAlbumRow: Decodable {
    let album_id: String
    let album_url: String
    let title: String
    let cover_url: String

    func asAlbum() -> HiddenAlbum? {
        guard
            let albumURL = URL(string: album_url),
            let coverURL = URL(string: cover_url)
        else {
            return nil
        }

        return HiddenAlbum(
            url: Hidden4KHDURLNormalizer.normalizeAlbumURL(albumURL),
            title: title,
            coverURL: Hidden4KHDURLNormalizer.normalizeImageURL(coverURL)
        )
    }
}

private struct HiddenSupabase4KHDImageRow: Decodable {
    let image_id: String
    let image_url: String

    func asImageURL() -> URL? {
        URL(string: image_url).map(Hidden4KHDURLNormalizer.normalizeImageURL)
    }
}

private struct HiddenSupabase4KHDAlbumPayload: Encodable {
    let album_id: String
    let album_url: String
    let title: String
    let cover_url: String

    init(album: HiddenAlbum) {
        album_id = album.id
        album_url = album.url.absoluteString
        title = album.title
        cover_url = album.coverURL.absoluteString
    }
}

private struct HiddenSupabase4KHDImagePayload: Encodable {
    let image_id: String
    let image_url: String

    init(imageURL: URL) {
        let normalized = Hidden4KHDURLNormalizer.normalizeImageURL(imageURL)
        image_id = normalized.absoluteString
        image_url = normalized.absoluteString
    }
}

private struct HiddenSupabaseUTEntryRow: Decodable {
    let entry_id: UUID
    let entry_date: String
    let hours: Double
    let note: String
    let created_at: String

    func asUTEntry() -> UTEntry? {
        guard let date = HiddenSupabaseDateFormatter.date(from: entry_date) else {
            return nil
        }

        return UTEntry(
            id: entry_id,
            date: date,
            hours: hours,
            note: note,
            createdAt: HiddenSupabaseDateFormatter.date(from: created_at) ?? Date()
        )
    }
}

private struct HiddenSupabaseUTEntryPayload: Encodable {
    let entry_id: UUID
    let entry_date: String
    let hours: Double
    let note: String
    let created_at: String

    init(entry: UTEntry) {
        entry_id = entry.id
        entry_date = HiddenSupabaseDateFormatter.string(from: entry.date)
        hours = entry.hours
        note = entry.note
        created_at = HiddenSupabaseDateFormatter.string(from: entry.createdAt)
    }
}

private enum HiddenSupabaseDateFormatter {
    private static let preciseFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let fallbackFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func string(from date: Date) -> String {
        preciseFormatter.string(from: date)
    }

    static func date(from string: String) -> Date? {
        preciseFormatter.date(from: string) ?? fallbackFormatter.date(from: string)
    }
}

private enum HiddenSupabaseSessionStore {
    private static let service = "com.easysearch.hidden-space.supabase"
    private static let account = "javdb-session"

    static func load() -> HiddenSupabaseSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return try? JSONDecoder().decode(HiddenSupabaseSession.self, from: data)
    }

    static func save(_ session: HiddenSupabaseSession) throws {
        let data = try JSONEncoder().encode(session)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw NSError(
                domain: "HiddenSupabaseSessionStore",
                code: Int(updateStatus),
                userInfo: [NSLocalizedDescriptionKey: "无法更新云端会话"]
            )
        }

        var insert = query
        insert[kSecValueData as String] = data
        let insertStatus = SecItemAdd(insert as CFDictionary, nil)
        guard insertStatus == errSecSuccess else {
            throw NSError(
                domain: "HiddenSupabaseSessionStore",
                code: Int(insertStatus),
                userInfo: [NSLocalizedDescriptionKey: "无法保存云端会话"]
            )
        }
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

actor HiddenSupabaseService {
    static let shared = HiddenSupabaseService()

    private let urlSession: URLSession
    private var session: HiddenSupabaseSession?

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        urlSession = URLSession(configuration: configuration)
        session = HiddenSupabaseSessionStore.load()
    }

    func configuration() -> HiddenSupabaseConfiguration? {
        HiddenSupabaseConfiguration.current
    }

    func restoreSessionIfPossible() async throws -> HiddenSupabaseSession? {
        guard let stored = session ?? HiddenSupabaseSessionStore.load() else {
            return nil
        }

        session = stored
        if stored.needsRefresh {
            return try await refreshSessionIfNeeded(force: true)
        }
        return stored
    }

    func signIn(email: String, password: String) async throws -> HiddenSupabaseSession {
        let body = try JSONSerialization.data(withJSONObject: [
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines),
            "password": password
        ])

        let request = try request(
            path: "/auth/v1/token",
            method: "POST",
            queryItems: [URLQueryItem(name: "grant_type", value: "password")],
            body: body,
            bearerToken: nil,
            isRESTRequest: false
        )

        let data = try await performDataRequest(request)
        guard let parsedSession = try parseSession(fromAuthResponse: data) else {
            throw NSError(
                domain: "HiddenSupabaseService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "登录成功，但没有拿到会话"]
            )
        }

        try persist(session: parsedSession)
        return parsedSession
    }

    func signUp(email: String, password: String) async throws -> HiddenSupabaseAuthOutcome {
        let body = try JSONSerialization.data(withJSONObject: [
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines),
            "password": password
        ])

        let request = try request(
            path: "/auth/v1/signup",
            method: "POST",
            body: body,
            bearerToken: nil,
            isRESTRequest: false
        )

        let data = try await performDataRequest(request)
        if let parsedSession = try parseSession(fromAuthResponse: data) {
            try persist(session: parsedSession)
            return .authenticated(parsedSession)
        }

        return .confirmationRequired("注册成功。当前项目可能开启了邮箱确认，请先去邮箱确认后再登录。")
    }

    func signOut() {
        session = nil
        HiddenSupabaseSessionStore.clear()
    }

    func fetchFavorites() async throws -> [HiddenJavDBMovie] {
        let request = try await authorizedRESTRequest(
            path: "/rest/v1/jav_favorites",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "created_at.desc")
            ]
        )

        let data = try await performDataRequest(request)
        let rows = try JSONDecoder().decode([HiddenSupabaseFavoriteRow].self, from: data)
        return rows.compactMap { $0.asMovie() }
    }

    func upsertFavorites(_ movies: [HiddenJavDBMovie]) async throws {
        guard !movies.isEmpty else { return }
        let payload = movies.map(HiddenSupabaseFavoritePayload.init(movie:))
        try await upsertFavoritesPayload(payload)
    }

    func upsertFavorite(_ movie: HiddenJavDBMovie) async throws {
        try await upsertFavoritesPayload([HiddenSupabaseFavoritePayload(movie: movie)])
    }

    func deleteFavorite(movieID: String) async throws {
        let request = try await authorizedRESTRequest(
            path: "/rest/v1/jav_favorites",
            method: "DELETE",
            queryItems: [
                URLQueryItem(name: "movie_id", value: "eq.\(movieID)")
            ]
        )

        _ = try await performDataRequest(request)
    }

    func fetchPlaybacks() async throws -> [HiddenJavDBFavoritePlayback] {
        let request = try await authorizedRESTRequest(
            path: "/rest/v1/jav_playbacks",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "created_at.desc")
            ]
        )

        let data = try await performDataRequest(request)
        let rows = try JSONDecoder().decode([HiddenSupabasePlaybackRow].self, from: data)
        return rows.compactMap { $0.asPlayback() }
    }

    func upsertPlaybacks(_ playbacks: [HiddenJavDBFavoritePlayback]) async throws {
        guard !playbacks.isEmpty else { return }
        let payload = playbacks.map(HiddenSupabasePlaybackPayload.init(playback:))
        try await upsertPlaybacksPayload(payload)
    }

    func upsertPlayback(_ playback: HiddenJavDBFavoritePlayback) async throws {
        try await upsertPlaybacksPayload([HiddenSupabasePlaybackPayload(playback: playback)])
    }

    func deletePlayback(id: UUID) async throws {
        let request = try await authorizedRESTRequest(
            path: "/rest/v1/jav_playbacks",
            method: "DELETE",
            queryItems: [
                URLQueryItem(name: "id", value: "eq.\(id.uuidString)")
            ]
        )

        _ = try await performDataRequest(request)
    }

    func fetch4KHDAlbums() async throws -> [HiddenAlbum] {
        let request = try await authorizedRESTRequest(
            path: "/rest/v1/fourkhd_favorite_albums",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "created_at.desc")
            ]
        )

        let data = try await performDataRequest(request)
        let rows = try JSONDecoder().decode([HiddenSupabase4KHDAlbumRow].self, from: data)
        return rows.compactMap { $0.asAlbum() }
    }

    func upsert4KHDAlbums(_ albums: [HiddenAlbum]) async throws {
        guard !albums.isEmpty else { return }
        try await upsert4KHDAlbumsPayload(albums.map(HiddenSupabase4KHDAlbumPayload.init(album:)))
    }

    func upsert4KHDAlbum(_ album: HiddenAlbum) async throws {
        try await upsert4KHDAlbumsPayload([HiddenSupabase4KHDAlbumPayload(album: album)])
    }

    func delete4KHDAlbum(albumID: String) async throws {
        let request = try await authorizedRESTRequest(
            path: "/rest/v1/fourkhd_favorite_albums",
            method: "DELETE",
            queryItems: [
                URLQueryItem(name: "album_id", value: "eq.\(albumID)")
            ]
        )

        _ = try await performDataRequest(request)
    }

    func fetch4KHDImages() async throws -> [URL] {
        let request = try await authorizedRESTRequest(
            path: "/rest/v1/fourkhd_favorite_images",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "created_at.desc")
            ]
        )

        let data = try await performDataRequest(request)
        let rows = try JSONDecoder().decode([HiddenSupabase4KHDImageRow].self, from: data)
        return rows.compactMap { $0.asImageURL() }
    }

    func fetchUTEntries() async throws -> [UTEntry] {
        let request = try await authorizedRESTRequest(
            path: "/rest/v1/ut_entries",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "created_at.desc")
            ]
        )

        let data = try await performDataRequest(request)
        let rows = try JSONDecoder().decode([HiddenSupabaseUTEntryRow].self, from: data)
        return rows.compactMap { $0.asUTEntry() }
    }

    func upsert4KHDImages(_ imageURLs: [URL]) async throws {
        guard !imageURLs.isEmpty else { return }
        try await upsert4KHDImagesPayload(imageURLs.map(HiddenSupabase4KHDImagePayload.init(imageURL:)))
    }

    func upsert4KHDImage(_ imageURL: URL) async throws {
        try await upsert4KHDImagesPayload([HiddenSupabase4KHDImagePayload(imageURL: imageURL)])
    }

    func delete4KHDImage(imageID: String) async throws {
        let request = try await authorizedRESTRequest(
            path: "/rest/v1/fourkhd_favorite_images",
            method: "DELETE",
            queryItems: [
                URLQueryItem(name: "image_id", value: "eq.\(imageID)")
            ]
        )

        _ = try await performDataRequest(request)
    }

    func upsertUTEntries(_ entries: [UTEntry]) async throws {
        guard !entries.isEmpty else { return }
        try await upsertUTEntriesPayload(entries.map(HiddenSupabaseUTEntryPayload.init(entry:)))
    }

    func upsertUTEntry(_ entry: UTEntry) async throws {
        try await upsertUTEntriesPayload([HiddenSupabaseUTEntryPayload(entry: entry)])
    }

    func deleteUTEntry(id: UUID) async throws {
        let request = try await authorizedRESTRequest(
            path: "/rest/v1/ut_entries",
            method: "DELETE",
            queryItems: [
                URLQueryItem(name: "entry_id", value: "eq.\(id.uuidString)")
            ]
        )

        _ = try await performDataRequest(request)
    }

    private func upsertFavoritesPayload(_ payload: [HiddenSupabaseFavoritePayload]) async throws {
        let body = try JSONEncoder().encode(payload)
        let request = try await authorizedRESTRequest(
            path: "/rest/v1/jav_favorites",
            method: "POST",
            queryItems: [
                URLQueryItem(name: "on_conflict", value: "user_id,movie_id")
            ],
            body: body,
            prefer: "resolution=merge-duplicates,missing=default,return=minimal"
        )

        _ = try await performDataRequest(request)
    }

    private func upsertPlaybacksPayload(_ payload: [HiddenSupabasePlaybackPayload]) async throws {
        let body = try JSONEncoder().encode(payload)
        let request = try await authorizedRESTRequest(
            path: "/rest/v1/jav_playbacks",
            method: "POST",
            queryItems: [
                URLQueryItem(name: "on_conflict", value: "id")
            ],
            body: body,
            prefer: "resolution=merge-duplicates,missing=default,return=minimal"
        )

        _ = try await performDataRequest(request)
    }

    private func upsert4KHDAlbumsPayload(_ payload: [HiddenSupabase4KHDAlbumPayload]) async throws {
        let body = try JSONEncoder().encode(payload)
        let request = try await authorizedRESTRequest(
            path: "/rest/v1/fourkhd_favorite_albums",
            method: "POST",
            queryItems: [
                URLQueryItem(name: "on_conflict", value: "user_id,album_id")
            ],
            body: body,
            prefer: "resolution=merge-duplicates,missing=default,return=minimal"
        )

        _ = try await performDataRequest(request)
    }

    private func upsert4KHDImagesPayload(_ payload: [HiddenSupabase4KHDImagePayload]) async throws {
        let body = try JSONEncoder().encode(payload)
        let request = try await authorizedRESTRequest(
            path: "/rest/v1/fourkhd_favorite_images",
            method: "POST",
            queryItems: [
                URLQueryItem(name: "on_conflict", value: "user_id,image_id")
            ],
            body: body,
            prefer: "resolution=merge-duplicates,missing=default,return=minimal"
        )

        _ = try await performDataRequest(request)
    }

    private func upsertUTEntriesPayload(_ payload: [HiddenSupabaseUTEntryPayload]) async throws {
        let body = try JSONEncoder().encode(payload)
        let request = try await authorizedRESTRequest(
            path: "/rest/v1/ut_entries",
            method: "POST",
            queryItems: [
                URLQueryItem(name: "on_conflict", value: "user_id,entry_id")
            ],
            body: body,
            prefer: "resolution=merge-duplicates,missing=default,return=minimal"
        )

        _ = try await performDataRequest(request)
    }

    private func authorizedRESTRequest(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        prefer: String? = nil
    ) async throws -> URLRequest {
        let validSession = try await validSession()
        return try request(
            path: path,
            method: method,
            queryItems: queryItems,
            body: body,
            bearerToken: validSession.accessToken,
            isRESTRequest: true,
            prefer: prefer
        )
    }

    private func validSession() async throws -> HiddenSupabaseSession {
        if let currentSession = session {
            if currentSession.needsRefresh {
                if let refreshed = try await refreshSessionIfNeeded(force: true) {
                    return refreshed
                }
            } else {
                return currentSession
            }
        }

        if let restored = try await restoreSessionIfPossible() {
            return restored
        }

        throw NSError(
            domain: "HiddenSupabaseService",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: "云端会话已失效，请重新登录"]
        )
    }

    private func refreshSessionIfNeeded(force: Bool) async throws -> HiddenSupabaseSession? {
        guard let currentSession = session, force || currentSession.needsRefresh else {
            return session
        }

        guard !currentSession.refreshToken.isEmpty else {
            signOut()
            return nil
        }

        let body = try JSONSerialization.data(withJSONObject: [
            "refresh_token": currentSession.refreshToken
        ])

        let request = try request(
            path: "/auth/v1/token",
            method: "POST",
            queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            body: body,
            bearerToken: nil,
            isRESTRequest: false
        )

        do {
            let data = try await performDataRequest(request)
            guard let refreshed = try parseSession(fromAuthResponse: data) else {
                signOut()
                return nil
            }
            try persist(session: refreshed)
            return refreshed
        } catch {
            signOut()
            throw error
        }
    }

    private func persist(session newSession: HiddenSupabaseSession) throws {
        session = newSession
        try HiddenSupabaseSessionStore.save(newSession)
    }

    private func request(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        bearerToken: String?,
        isRESTRequest: Bool,
        prefer: String? = nil
    ) throws -> URLRequest {
        guard let configuration = HiddenSupabaseConfiguration.current else {
            throw NSError(
                domain: "HiddenSupabaseService",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "未配置 Supabase URL 或 Key"]
            )
        }

        var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false)
        components?.path = path
        components?.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components?.url else {
            throw NSError(
                domain: "HiddenSupabaseService",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "无法构造云端请求地址"]
            )
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }

        if isRESTRequest {
            switch method.uppercased() {
            case "GET", "HEAD":
                request.setValue(configuration.schema, forHTTPHeaderField: "Accept-Profile")
            default:
                request.setValue(configuration.schema, forHTTPHeaderField: "Content-Profile")
            }
        }

        if let prefer {
            request.setValue(prefer, forHTTPHeaderField: "Prefer")
        }

        return request
    }

    private func performDataRequest(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "HiddenSupabaseService",
                code: -5,
                userInfo: [NSLocalizedDescriptionKey: "云端返回了无效响应"]
            )
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let payload = try? JSONDecoder().decode(HiddenSupabaseErrorPayload.self, from: data)
            let message = payload?.resolvedMessage?.cloudNonEmpty ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)

            throw NSError(
                domain: "HiddenSupabaseService",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }

        return data
    }

    private func parseSession(fromAuthResponse data: Data) throws -> HiddenSupabaseSession? {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let accessToken = object["access_token"] as? String
        let refreshToken = object["refresh_token"] as? String
        let expiresIn = object["expires_in"] as? Double
        let user = object["user"] as? [String: Any]
        let userID = (user?["id"] as? String).flatMap(UUID.init(uuidString:))
        let email = user?["email"] as? String

        guard let accessToken, let refreshToken else {
            return nil
        }

        let expiresAt: Date
        if let expiresAtTimestamp = object["expires_at"] as? TimeInterval {
            expiresAt = Date(timeIntervalSince1970: expiresAtTimestamp)
        } else {
            expiresAt = Date().addingTimeInterval(expiresIn ?? 3600)
        }

        return HiddenSupabaseSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            userID: userID,
            email: email
        )
    }
}

extension Error {
    var isHiddenSupabaseAuthFailure: Bool {
        let nsError = self as NSError
        guard nsError.domain == "HiddenSupabaseService" else {
            return false
        }

        return nsError.code == 401 || nsError.code == 403
    }
}

@MainActor
final class HiddenCloudSyncViewModel: ObservableObject {
    static let shared = HiddenCloudSyncViewModel()

    @Published var isCloudConfigured = false
    @Published var isCloudAuthenticated = false
    @Published var cloudUserEmail: String?
    @Published var cloudStatusMessage: String?
    @Published var isPreparingCloud = false
    @Published var isCloudBusy = false

    private let cloudService = HiddenSupabaseService.shared
    private var didPrepareCloud = false

    func prepareIfNeeded() async {
        guard !didPrepareCloud, !isPreparingCloud else { return }
        didPrepareCloud = true

        isPreparingCloud = true
        defer { isPreparingCloud = false }

        guard let configuration = await cloudService.configuration() else {
            isCloudConfigured = false
            isCloudAuthenticated = false
            cloudUserEmail = nil
            cloudStatusMessage = "未配置云端同步，当前仅保存在本地。"
            return
        }

        isCloudConfigured = true
        cloudStatusMessage = "已连接 \(configuration.projectHost)，正在检查会话..."

        do {
            if let session = try await cloudService.restoreSessionIfPossible() {
                applySession(session)
                await syncNow(reason: "已恢复云端会话")
            } else {
                isCloudAuthenticated = false
                cloudUserEmail = nil
                cloudStatusMessage = "云端已配置，但尚未登录。"
            }
        } catch {
            isCloudAuthenticated = false
            cloudUserEmail = nil
            cloudStatusMessage = "云端会话恢复失败：\(error.localizedDescription)"
            didPrepareCloud = false
        }
    }

    func syncIfPossible() async {
        guard !isPreparingCloud, !isCloudBusy else { return }

        if !didPrepareCloud {
            await prepareIfNeeded()
            return
        }

        guard isCloudConfigured, isCloudAuthenticated else { return }
        await syncNow(reason: "云端同步完成")
    }

    func signIn(email: String, password: String) async {
        guard isCloudConfigured else {
            cloudStatusMessage = "请先配置 Supabase URL 和 publishable key。"
            return
        }

        isCloudBusy = true
        defer { isCloudBusy = false }

        do {
            let session = try await cloudService.signIn(email: email, password: password)
            applySession(session)
            await syncNow(reason: "登录成功")
        } catch {
            cloudStatusMessage = "登录失败：\(error.localizedDescription)"
        }
    }

    func signUp(email: String, password: String) async {
        guard isCloudConfigured else {
            cloudStatusMessage = "请先配置 Supabase URL 和 publishable key。"
            return
        }

        isCloudBusy = true
        defer { isCloudBusy = false }

        do {
            let outcome = try await cloudService.signUp(email: email, password: password)
            switch outcome {
            case let .authenticated(session):
                applySession(session)
                await syncNow(reason: "注册成功")
            case let .confirmationRequired(message):
                isCloudAuthenticated = false
                cloudUserEmail = nil
                cloudStatusMessage = message
            }
        } catch {
            cloudStatusMessage = "注册失败：\(error.localizedDescription)"
        }
    }

    func signOut() async {
        await cloudService.signOut()
        isCloudAuthenticated = false
        cloudUserEmail = nil
        cloudStatusMessage = "已退出云端登录，当前仅保存在本地。"
    }

    func syncNow() async {
        await syncNow(reason: "云端同步完成")
    }

    func syncUTEntryUpsertIfPossible(_ entry: UTEntry) async {
        guard await prepareForMutationIfNeeded() else { return }

        do {
            try await cloudService.upsertUTEntry(entry)
            cloudStatusMessage = "已同步 UT 记录到云端"
        } catch {
            handleCloudMutationError(error, fallbackMessage: "UT 云端同步失败")
        }
    }

    func syncUTEntryDeletionIfPossible(_ entry: UTEntry) async {
        guard await prepareForMutationIfNeeded() else { return }

        do {
            try await cloudService.deleteUTEntry(id: entry.id)
            cloudStatusMessage = "已从云端移除 UT 记录"
        } catch {
            handleCloudMutationError(error, fallbackMessage: "UT 云端删除失败")
        }
    }

    private func syncNow(reason: String) async {
        guard isCloudAuthenticated else { return }

        isCloudBusy = true
        defer { isCloudBusy = false }

        do {
            let reports = try await CloudSyncCoordinator.sync(makeCollections())
            let summary = reports.map(\.summaryText).joined(separator: " · ")
            cloudStatusMessage = summary.isEmpty ? reason : "\(reason) · \(summary)"
        } catch {
            if error.isHiddenSupabaseAuthFailure {
                isCloudAuthenticated = false
                didPrepareCloud = false
            }
            cloudStatusMessage = "云端同步失败：\(error.localizedDescription)"
        }
    }

    private func makeCollections() -> [AnyCloudSyncCollection] {
        [
            CloudSyncCollection(
                label: "jav 影片",
                unit: "部",
                loadLocal: {
                    let localPlaybacks = HiddenJavDBLocalStore.loadFavoritePlaybacks()
                    return HiddenCloudMerge.movies(
                        primary: HiddenJavDBLocalStore.loadFavoriteMovies(),
                        secondary: localPlaybacks.map(\.movie)
                    )
                },
                fetchRemote: { try await self.cloudService.fetchFavorites() },
                saveLocal: HiddenJavDBLocalStore.saveFavoriteMovies,
                upsertRemote: { try await self.cloudService.upsertFavorites($0) },
                merge: HiddenCloudMerge.movies
            ).eraseToAnyCollection(),
            CloudSyncCollection(
                label: "jav 播放点",
                unit: "条",
                loadLocal: HiddenJavDBLocalStore.loadFavoritePlaybacks,
                fetchRemote: { try await self.cloudService.fetchPlaybacks() },
                saveLocal: HiddenJavDBLocalStore.saveFavoritePlaybacks,
                upsertRemote: { try await self.cloudService.upsertPlaybacks($0) },
                merge: HiddenCloudMerge.playbacks
            ).eraseToAnyCollection(),
            CloudSyncCollection(
                label: "4khd album",
                unit: "个",
                loadLocal: Hidden4KHDLocalStore.loadFavoriteAlbums,
                fetchRemote: { try await self.cloudService.fetch4KHDAlbums() },
                saveLocal: Hidden4KHDLocalStore.saveFavoriteAlbums,
                upsertRemote: { try await self.cloudService.upsert4KHDAlbums($0) },
                merge: HiddenCloudMerge.albums
            ).eraseToAnyCollection(),
            CloudSyncCollection(
                label: "图片",
                unit: "张",
                loadLocal: Hidden4KHDLocalStore.loadFavoriteImages,
                fetchRemote: { try await self.cloudService.fetch4KHDImages() },
                saveLocal: Hidden4KHDLocalStore.saveFavoriteImages,
                upsertRemote: { try await self.cloudService.upsert4KHDImages($0) },
                merge: HiddenCloudMerge.imageURLs
            ).eraseToAnyCollection(),
            CloudSyncCollection(
                label: "UT",
                unit: "条",
                loadLocal: { UTTrackerLocalStore().loadEntries() },
                fetchRemote: { try await self.cloudService.fetchUTEntries() },
                saveLocal: { UTTrackerLocalStore().saveEntries($0) },
                upsertRemote: { try await self.cloudService.upsertUTEntries($0) },
                merge: HiddenCloudMerge.utEntries
            ).eraseToAnyCollection()
        ]
    }

    private func applySession(_ session: HiddenSupabaseSession) {
        isCloudAuthenticated = true
        cloudUserEmail = session.email
        cloudStatusMessage = session.email?.cloudNonEmpty.map { "已登录 \($0)" } ?? "已登录云端同步"
    }

    private func prepareForMutationIfNeeded() async -> Bool {
        if !didPrepareCloud {
            await prepareIfNeeded()
        }

        return isCloudConfigured && isCloudAuthenticated
    }

    private func handleCloudMutationError(_ error: Error, fallbackMessage: String) {
        if error.isHiddenSupabaseAuthFailure {
            isCloudAuthenticated = false
            didPrepareCloud = false
        }

        cloudStatusMessage = "\(fallbackMessage)：\(error.localizedDescription)"
    }
}
