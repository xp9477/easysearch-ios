import Combine
import Foundation
import Security

// App-wide cloud sync backend (Supabase). Lives in Core/CloudSync.
// Collections: Jav favorites/playbacks, 4KHD albums/images, UT entries, QingLong profiles.

extension String {
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

    static func qingLongProfiles(
        primary: [QingLongPanelProfile],
        secondary: [QingLongPanelProfile]
    ) -> [QingLongPanelProfile] {
        let candidates = (primary + secondary).sorted { lhs, rhs in
            if lhs.syncActivityAt == rhs.syncActivityAt {
                return lhs.savedAt > rhs.savedAt
            }

            return lhs.syncActivityAt > rhs.syncActivityAt
        }

        var merged: [QingLongPanelProfile] = []
        var seenIDs = Set<String>()

        for profile in candidates {
            if seenIDs.insert(profile.id).inserted {
                merged.append(profile)
            }
        }

        return merged
    }

    static func workoutDays(primary: [WorkoutDay], secondary: [WorkoutDay]) -> [WorkoutDay] {
        var byID: [String: WorkoutDay] = [:]

        for day in primary + secondary {
            if let existing = byID[day.id] {
                if existing.updatedAt > day.updatedAt {
                    continue
                }

                if existing.updatedAt == day.updatedAt {
                    // Equal clocks are possible after JSON round-trips. Deletion must
                    // win ties; otherwise an empty-day tombstone can be resurrected.
                    if existing.isTombstone || !day.isTombstone {
                        continue
                    }
                }
            }

            byID[day.id] = day
        }

        return byID.values.sorted { $0.dayStart > $1.dayStart }
    }

    static func monthlyExpenseClaims(
        primary: [MonthlyExpenseClaim],
        secondary: [MonthlyExpenseClaim]
    ) -> [MonthlyExpenseClaim] {
        var byID: [String: MonthlyExpenseClaim] = [:]
        for claim in primary + secondary {
            if let existing = byID[claim.id] {
                byID[claim.id] = mergeMonthlyClaim(existing, claim)
            } else {
                byID[claim.id] = claim
            }
        }
        return byID.values.sorted { $0.monthStart > $1.monthStart }
    }

    private static func mergeMonthlyClaim(
        _ lhs: MonthlyExpenseClaim,
        _ rhs: MonthlyExpenseClaim
    ) -> MonthlyExpenseClaim {
        MonthlyExpenseClaim(
            monthStart: lhs.monthStart,
            taxi: preferExpenseStatus(lhs.taxi, rhs.taxi),
            parking: preferExpenseStatus(lhs.parking, rhs.parking),
            phoneBill: preferExpenseStatus(lhs.phoneBill, rhs.phoneBill),
            misc: preferExpenseStatus(lhs.misc, rhs.misc)
        )
    }

    private static func preferExpenseStatus(
        _ lhs: ExpenseClaimItemStatus,
        _ rhs: ExpenseClaimItemStatus
    ) -> ExpenseClaimItemStatus {
        if lhs != .pending { return lhs }
        return rhs
    }

    static func travelExpenseClaims(
        primary: [TravelExpenseClaim],
        secondary: [TravelExpenseClaim]
    ) -> [TravelExpenseClaim] {
        let candidates = (primary + secondary).sorted { $0.updatedAt > $1.updatedAt }
        var merged: [TravelExpenseClaim] = []
        var seen = Set<UUID>()
        for claim in candidates where seen.insert(claim.id).inserted {
            merged.append(claim)
        }
        return merged
    }
}

private enum Hidden4KHDURLNormalizer {
    static func normalizeImageURL(_ url: URL) -> URL {
        // Keep cloud + local image keys aligned with the runtime image pipeline.
        HiddenSpaceAPI.normalizeImageURL(url)
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
                sourceName: HiddenJavDBPlaybackSourceNormalizer.normalize(playback.sourceName),
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

private enum HiddenJavDBPlaybackSourceNormalizer {
    static func normalize(_ rawSourceName: String) -> String {
        switch rawSourceName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "jable", "miss.av", "missav":
            return "MISSAV"
        default:
            return rawSourceName
        }
    }
}

struct HiddenSupabaseConfiguration: Sendable {
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

enum HiddenSupabaseAuthOutcome: Sendable {
    case authenticated(HiddenSupabaseSession)
    case confirmationRequired(String)
}

struct HiddenSupabaseSession: Codable, Sendable {
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
    let code: String?
    let errorCode: String?

    enum CodingKeys: String, CodingKey {
        case message
        case msg
        case error
        case code
        case errorCode = "error_code"
        case errorDescription = "error_description"
    }

    var resolvedMessage: String? {
        message ?? msg ?? errorDescription ?? error
    }

    var resolvedCode: String? {
        code ?? errorCode
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
            sourceName: HiddenJavDBPlaybackSourceNormalizer.normalize(source_name),
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

private struct HiddenSupabaseQingLongPanelProfileRow: Decodable {
    let profile_id: String
    let base_url: String
    let display_name: String
    let saved_at: String
    let last_connected_at: String?

    func asProfile() -> QingLongPanelProfile? {
        guard
            let baseURL = try? QingLongEndpoint.normalizedURL(from: base_url),
            let savedAt = HiddenSupabaseDateFormatter.date(from: saved_at)
        else {
            return nil
        }

        return QingLongPanelProfile(
            id: profile_id,
            baseURL: baseURL,
            displayName: display_name,
            savedAt: savedAt,
            lastConnectedAt: last_connected_at.flatMap(HiddenSupabaseDateFormatter.date(from:))
        )
    }
}

private struct HiddenSupabaseQingLongPanelProfilePayload: Encodable {
    let profile_id: String
    let base_url: String
    let display_name: String
    let saved_at: String
    let last_connected_at: String?

    init(profile: QingLongPanelProfile) {
        profile_id = profile.id
        base_url = profile.baseURL.absoluteString
        display_name = profile.displayName
        saved_at = HiddenSupabaseDateFormatter.string(from: profile.savedAt)
        last_connected_at = profile.lastConnectedAt.map(HiddenSupabaseDateFormatter.string(from:))
    }
}

private struct HiddenSupabaseTrainingLineDTO: Codable {
    let id: UUID
    let exercise_id: String
    let exercise_name: String
    let amount: Int
    let unit: String
    let created_at: String

    init(line: WorkoutLine) {
        id = line.id
        exercise_id = line.exerciseID
        exercise_name = line.exerciseName
        amount = line.amount
        unit = line.unit.rawValue
        created_at = HiddenSupabaseDateFormatter.string(from: line.createdAt)
    }

    func asLine() throws -> WorkoutLine {
        guard let decodedUnit = ExerciseUnit(rawValue: unit) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Unsupported training unit: \(unit)"
                )
            )
        }
        guard let createdAt = HiddenSupabaseDateFormatter.date(from: created_at) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Invalid training line created_at"
                )
            )
        }
        return WorkoutLine(
            id: id,
            exerciseID: exercise_id,
            exerciseName: exercise_name,
            amount: amount,
            unit: decodedUnit,
            createdAt: createdAt
        )
    }
}

private struct HiddenSupabaseTrainingDayRow: Decodable {
    let day_id: String
    let day_start: String
    let note: String
    let lines: [HiddenSupabaseTrainingLineDTO]
    let updated_at: String

    func asDay() throws -> WorkoutDay {
        guard let dayStart = HiddenSupabaseDateFormatter.date(from: day_start),
              let updatedAt = HiddenSupabaseDateFormatter.date(from: updated_at) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Invalid training day timestamp"
                )
            )
        }
        let noteValue = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let decodedLines = try lines.map { try $0.asLine() }
        return WorkoutDay(
            id: day_id,
            dayStart: dayStart,
            lines: decodedLines,
            note: noteValue.isEmpty ? nil : note,
            updatedAt: updatedAt
        )
    }
}

private struct HiddenSupabaseTrainingDayPayload: Encodable {
    let day_id: String
    let day_start: String
    let note: String
    let lines: [HiddenSupabaseTrainingLineDTO]
    let updated_at: String

    init(day: WorkoutDay) {
        day_id = day.id
        day_start = HiddenSupabaseDateFormatter.string(from: day.dayStart)
        note = day.note ?? ""
        lines = day.lines.map(HiddenSupabaseTrainingLineDTO.init(line:))
        updated_at = HiddenSupabaseDateFormatter.string(from: day.updatedAt)
    }
}

private struct HiddenSupabaseExpenseMonthlyRow: Decodable {
    let claim_id: String
    let month_start: String
    let taxi: String
    let parking: String
    let phone_bill: String
    let misc: String

    func asClaim() -> MonthlyExpenseClaim? {
        guard let monthStart = HiddenSupabaseDateFormatter.date(from: month_start) else {
            return nil
        }
        return MonthlyExpenseClaim(
            monthStart: monthStart,
            taxi: ExpenseClaimItemStatus(rawValue: taxi) ?? .pending,
            parking: ExpenseClaimItemStatus(rawValue: parking) ?? .pending,
            phoneBill: ExpenseClaimItemStatus(rawValue: phone_bill) ?? .pending,
            misc: ExpenseClaimItemStatus(rawValue: misc) ?? .pending
        )
    }
}

private struct HiddenSupabaseExpenseMonthlyPayload: Encodable {
    let claim_id: String
    let month_start: String
    let taxi: String
    let parking: String
    let phone_bill: String
    let misc: String
    let updated_at: String

    init(claim: MonthlyExpenseClaim) {
        claim_id = claim.id
        month_start = HiddenSupabaseDateFormatter.string(from: claim.monthStart)
        taxi = claim.taxi.rawValue
        parking = claim.parking.rawValue
        phone_bill = claim.phoneBill.rawValue
        misc = claim.misc.rawValue
        updated_at = HiddenSupabaseDateFormatter.string(from: Date())
    }
}

private struct HiddenSupabaseExpenseTravelRow: Decodable {
    let claim_id: UUID
    let title: String
    let start_date: String
    let end_date: String?
    let travel_approval_status: String
    let per_diem_status: String
    let expense_status: String
    let created_at: String
    let updated_at: String

    func asClaim() -> TravelExpenseClaim? {
        guard
            let startDate = HiddenSupabaseDateFormatter.date(from: start_date),
            let createdAt = HiddenSupabaseDateFormatter.date(from: created_at),
            let updatedAt = HiddenSupabaseDateFormatter.date(from: updated_at)
        else {
            return nil
        }

        return TravelExpenseClaim(
            id: claim_id,
            title: title,
            startDate: startDate,
            endDate: end_date.flatMap(HiddenSupabaseDateFormatter.date(from:)),
            travelApprovalStatus: TravelApprovalStatus(rawValue: travel_approval_status) ?? .pending,
            perDiemStatus: ExpenseClaimItemStatus(rawValue: per_diem_status) ?? .pending,
            expenseStatus: ExpenseClaimItemStatus(rawValue: expense_status) ?? .pending,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

private struct HiddenSupabaseExpenseTravelPayload: Encodable {
    let claim_id: UUID
    let title: String
    let start_date: String
    let end_date: String?
    let travel_approval_status: String
    let per_diem_status: String
    let expense_status: String
    let created_at: String
    let updated_at: String

    init(claim: TravelExpenseClaim) {
        claim_id = claim.id
        title = claim.title
        start_date = HiddenSupabaseDateFormatter.string(from: claim.startDate)
        end_date = claim.endDate.map(HiddenSupabaseDateFormatter.string(from:))
        travel_approval_status = claim.travelApprovalStatus.rawValue
        per_diem_status = claim.perDiemStatus.rawValue
        expense_status = claim.expenseStatus.rawValue
        created_at = HiddenSupabaseDateFormatter.string(from: claim.createdAt)
        updated_at = HiddenSupabaseDateFormatter.string(from: claim.updatedAt)
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

protocol HiddenSupabaseSessionStorage: AnyObject, Sendable {
    func load() -> HiddenSupabaseSession?
    func save(_ session: HiddenSupabaseSession) throws
    func clear()
}

private final class HiddenSupabaseKeychainSessionStore: HiddenSupabaseSessionStorage, @unchecked Sendable {
    private static let account = "javdb-session"
    private let store = KeychainStore(service: "com.easysearch.hidden-space.supabase")

    func load() -> HiddenSupabaseSession? {
        guard let data = try? store.loadData(account: Self.account) else {
            return nil
        }
        return try? JSONDecoder().decode(HiddenSupabaseSession.self, from: data)
    }

    func save(_ session: HiddenSupabaseSession) throws {
        let data = try JSONEncoder().encode(session)
        try store.saveData(data, account: Self.account)
    }

    func clear() {
        store.delete(account: Self.account)
    }
}

typealias HiddenSupabaseTransport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

private enum HiddenSupabaseAuthFailureClassifier {
    static let errorCodeUserInfoKey = "HiddenSupabaseAuthErrorCode"
    private static let definitiveCodes: Set<String> = [
        "bad_jwt",
        "invalid_credentials",
        "invalid_grant",
        "refresh_token_already_used",
        "refresh_token_not_found",
        "session_expired",
        "session_not_found",
        "user_banned",
        "user_not_found"
    ]

    static func isDefinitiveSessionInvalidation(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == "HiddenSupabaseService" else { return false }

        if nsError.code == 401 {
            return true
        }

        guard nsError.code == 400 || nsError.code == 422 else {
            return false
        }

        let authCode = (nsError.userInfo[errorCodeUserInfoKey] as? String)?
            .lowercased()
        if let authCode, definitiveCodes.contains(authCode) {
            return true
        }

        // Older GoTrue deployments did not always include the structured code.
        let message = nsError.localizedDescription.lowercased()
        return message.contains("refresh token not found")
            || message.contains("refresh token already used")
            || message.contains("invalid refresh token")
    }
}

actor HiddenSupabaseService {
    static let shared = HiddenSupabaseService()

    private struct SessionSnapshot: Equatable {
        let generation: UInt64
        let accessToken: String
        let refreshToken: String
        let userID: UUID?
        let email: String?
    }

    private struct RefreshOperation {
        let id: UUID
        let snapshot: SessionSnapshot
        let task: Task<Data, Error>
    }

    private let sessionStore: any HiddenSupabaseSessionStorage
    private let configurationProvider: @Sendable () -> HiddenSupabaseConfiguration?
    private let transport: HiddenSupabaseTransport
    private var session: HiddenSupabaseSession?
    private var sessionGeneration: UInt64 = 0
    private var refreshOperation: RefreshOperation?

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        let urlSession = URLSession(configuration: configuration)
        let sessionStore = HiddenSupabaseKeychainSessionStore()

        self.sessionStore = sessionStore
        configurationProvider = { HiddenSupabaseConfiguration.current }
        transport = { request in
            try await urlSession.data(for: request)
        }
        session = sessionStore.load()
    }

    /// Dependency-injected initializer used by deterministic session lifecycle tests.
    init(
        configuration: HiddenSupabaseConfiguration,
        sessionStore: any HiddenSupabaseSessionStorage,
        transport: @escaping HiddenSupabaseTransport
    ) {
        self.sessionStore = sessionStore
        configurationProvider = { configuration }
        self.transport = transport
        session = sessionStore.load()
    }

    func configuration() -> HiddenSupabaseConfiguration? {
        configurationProvider()
    }

    func restoreSessionIfPossible() async throws -> HiddenSupabaseSession? {
        guard let stored = session ?? sessionStore.load() else {
            return nil
        }

        session = stored
        if stored.needsRefresh {
            return try await refreshSessionIfNeeded(force: true)
        }
        return stored
    }

    func signIn(email: String, password: String) async throws -> HiddenSupabaseSession {
        let replacementGeneration = beginSessionReplacement()
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
        try ensureCurrentGeneration(replacementGeneration)
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
        let replacementGeneration = beginSessionReplacement()
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
        try ensureCurrentGeneration(replacementGeneration)
        if let parsedSession = try parseSession(fromAuthResponse: data) {
            try persist(session: parsedSession)
            return .authenticated(parsedSession)
        }

        // A successful sign-up without tokens means email confirmation is
        // required. The replacement operation already invalidated in-flight
        // work; clear any previous account now so the actor and UI cannot
        // disagree about which user is authenticated.
        session = nil
        sessionStore.clear()
        return .confirmationRequired("注册成功。当前项目可能开启了邮箱确认，请先去邮箱确认后再登录。")
    }

    func signOut() {
        advanceSessionGeneration()
        session = nil
        sessionStore.clear()
    }

    func fetchFavorites(expectedUserID: UUID) async throws -> [HiddenJavDBMovie] {
        let request = try await authorizedRESTRequest(
            path: "/rest/v1/jav_favorites",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "created_at.desc")
            ],
            expectedUserID: expectedUserID
        )

        let data = try await performDataRequest(request)
        let rows = try JSONDecoder().decode([HiddenSupabaseFavoriteRow].self, from: data)
        return rows.compactMap { $0.asMovie() }
    }

    func upsertFavorites(
        _ movies: [HiddenJavDBMovie],
        expectedUserID: UUID
    ) async throws {
        guard !movies.isEmpty else { return }
        let payload = movies.map(HiddenSupabaseFavoritePayload.init(movie:))
        try await upsertFavoritesPayload(payload, expectedUserID: expectedUserID)
    }

    func upsertFavorite(
        _ movie: HiddenJavDBMovie,
        expectedUserID: UUID
    ) async throws {
        try await upsertFavoritesPayload(
            [HiddenSupabaseFavoritePayload(movie: movie)],
            expectedUserID: expectedUserID
        )
    }

    func deleteFavorite(movieID: String, expectedUserID: UUID) async throws {
        let request = try await authorizedRESTRequest(
            path: "/rest/v1/jav_favorites",
            method: "DELETE",
            queryItems: [
                URLQueryItem(name: "movie_id", value: "eq.\(movieID)")
            ],
            expectedUserID: expectedUserID
        )

        _ = try await performDataRequest(request)
    }

    func fetchPlaybacks(expectedUserID: UUID) async throws -> [HiddenJavDBFavoritePlayback] {
        let request = try await authorizedRESTRequest(
            path: "/rest/v1/jav_playbacks",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "created_at.desc")
            ],
            expectedUserID: expectedUserID
        )

        let data = try await performDataRequest(request)
        let rows = try JSONDecoder().decode([HiddenSupabasePlaybackRow].self, from: data)
        return rows.compactMap { $0.asPlayback() }
    }

    func upsertPlaybacks(
        _ playbacks: [HiddenJavDBFavoritePlayback],
        expectedUserID: UUID
    ) async throws {
        guard !playbacks.isEmpty else { return }
        let payload = playbacks.map(HiddenSupabasePlaybackPayload.init(playback:))
        try await upsertPlaybacksPayload(payload, expectedUserID: expectedUserID)
    }

    func upsertPlayback(
        _ playback: HiddenJavDBFavoritePlayback,
        expectedUserID: UUID
    ) async throws {
        try await upsertPlaybacksPayload(
            [HiddenSupabasePlaybackPayload(playback: playback)],
            expectedUserID: expectedUserID
        )
    }

    func deletePlayback(id: UUID, expectedUserID: UUID) async throws {
        let request = try await authorizedRESTRequest(
            path: "/rest/v1/jav_playbacks",
            method: "DELETE",
            queryItems: [
                URLQueryItem(name: "id", value: "eq.\(id.uuidString)")
            ],
            expectedUserID: expectedUserID
        )

        _ = try await performDataRequest(request)
    }

    func fetch4KHDAlbums(expectedUserID: UUID) async throws -> [HiddenAlbum] {
        let request = try await authorizedRESTRequest(
            path: "/rest/v1/fourkhd_favorite_albums",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "created_at.desc")
            ],
            expectedUserID: expectedUserID
        )

        let data = try await performDataRequest(request)
        let rows = try JSONDecoder().decode([HiddenSupabase4KHDAlbumRow].self, from: data)
        return rows.compactMap { $0.asAlbum() }
    }

    func upsert4KHDAlbums(
        _ albums: [HiddenAlbum],
        expectedUserID: UUID
    ) async throws {
        guard !albums.isEmpty else { return }
        try await upsert4KHDAlbumsPayload(
            albums.map(HiddenSupabase4KHDAlbumPayload.init(album:)),
            expectedUserID: expectedUserID
        )
    }

    func upsert4KHDAlbum(
        _ album: HiddenAlbum,
        expectedUserID: UUID
    ) async throws {
        try await upsert4KHDAlbumsPayload(
            [HiddenSupabase4KHDAlbumPayload(album: album)],
            expectedUserID: expectedUserID
        )
    }

    func delete4KHDAlbum(albumID: String, expectedUserID: UUID) async throws {
        let request = try await authorizedRESTRequest(
            path: "/rest/v1/fourkhd_favorite_albums",
            method: "DELETE",
            queryItems: [
                URLQueryItem(name: "album_id", value: "eq.\(albumID)")
            ],
            expectedUserID: expectedUserID
        )

        _ = try await performDataRequest(request)
    }

    func fetch4KHDImages(expectedUserID: UUID) async throws -> [URL] {
        let request = try await authorizedRESTRequest(
            path: "/rest/v1/fourkhd_favorite_images",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "created_at.desc")
            ],
            expectedUserID: expectedUserID
        )

        let data = try await performDataRequest(request)
        let rows = try JSONDecoder().decode([HiddenSupabase4KHDImageRow].self, from: data)
        return rows.compactMap { $0.asImageURL() }
    }

    func fetchUTEntries(expectedUserID: UUID) async throws -> [UTEntry] {
        let request = try await authorizedRESTRequest(
            path: "/rest/v1/ut_entries",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "created_at.desc")
            ],
            expectedUserID: expectedUserID
        )

        let data = try await performDataRequest(request)
        let rows = try JSONDecoder().decode([HiddenSupabaseUTEntryRow].self, from: data)
        return rows.compactMap { $0.asUTEntry() }
    }

    func fetchQingLongPanelProfiles(expectedUserID: UUID) async throws -> [QingLongPanelProfile] {
        let request = try await authorizedRESTRequest(
            path: "/rest/v1/qinglong_panel_profiles",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "saved_at.desc")
            ],
            expectedUserID: expectedUserID
        )

        let data = try await performDataRequest(request)
        let rows = try JSONDecoder().decode([HiddenSupabaseQingLongPanelProfileRow].self, from: data)
        return rows.compactMap { $0.asProfile() }
    }

    func upsert4KHDImages(
        _ imageURLs: [URL],
        expectedUserID: UUID
    ) async throws {
        guard !imageURLs.isEmpty else { return }
        try await upsert4KHDImagesPayload(
            imageURLs.map(HiddenSupabase4KHDImagePayload.init(imageURL:)),
            expectedUserID: expectedUserID
        )
    }

    func upsert4KHDImage(
        _ imageURL: URL,
        expectedUserID: UUID
    ) async throws {
        try await upsert4KHDImagesPayload(
            [HiddenSupabase4KHDImagePayload(imageURL: imageURL)],
            expectedUserID: expectedUserID
        )
    }

    func delete4KHDImage(imageID: String, expectedUserID: UUID) async throws {
        let request = try await authorizedRESTRequest(
            path: "/rest/v1/fourkhd_favorite_images",
            method: "DELETE",
            queryItems: [
                URLQueryItem(name: "image_id", value: "eq.\(imageID)")
            ],
            expectedUserID: expectedUserID
        )

        _ = try await performDataRequest(request)
    }

    func upsertUTEntries(
        _ entries: [UTEntry],
        expectedUserID: UUID
    ) async throws {
        guard !entries.isEmpty else { return }
        try await upsertUTEntriesPayload(
            entries.map(HiddenSupabaseUTEntryPayload.init(entry:)),
            expectedUserID: expectedUserID
        )
    }

    func upsertUTEntry(_ entry: UTEntry, expectedUserID: UUID) async throws {
        try await upsertUTEntriesPayload(
            [HiddenSupabaseUTEntryPayload(entry: entry)],
            expectedUserID: expectedUserID
        )
    }

    func deleteUTEntry(id: UUID, expectedUserID: UUID) async throws {
        let request = try await authorizedRESTRequest(
            path: "/rest/v1/ut_entries",
            method: "DELETE",
            queryItems: [
                URLQueryItem(name: "entry_id", value: "eq.\(id.uuidString)")
            ],
            expectedUserID: expectedUserID
        )

        _ = try await performDataRequest(request)
    }

    func upsertQingLongPanelProfiles(
        _ profiles: [QingLongPanelProfile],
        expectedUserID: UUID
    ) async throws {
        guard !profiles.isEmpty else { return }
        try await upsertQingLongPanelProfilesPayload(
            profiles.map(HiddenSupabaseQingLongPanelProfilePayload.init(profile:)),
            expectedUserID: expectedUserID
        )
    }

    func upsertQingLongPanelProfile(
        _ profile: QingLongPanelProfile,
        expectedUserID: UUID
    ) async throws {
        try await upsertQingLongPanelProfilesPayload(
            [HiddenSupabaseQingLongPanelProfilePayload(profile: profile)],
            expectedUserID: expectedUserID
        )
    }

    func deleteQingLongPanelProfile(id: String, expectedUserID: UUID) async throws {
        let request = try await authorizedRESTRequest(
            path: "/rest/v1/qinglong_panel_profiles",
            method: "DELETE",
            queryItems: [
                URLQueryItem(name: "profile_id", value: "eq.\(id)")
            ],
            expectedUserID: expectedUserID
        )

        _ = try await performDataRequest(request)
    }

    func fetchTrainingDays(expectedUserID: UUID) async throws -> [WorkoutDay] {
        let request = try await authorizedRESTRequest(
            path: "/rest/v1/training_log_days",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "updated_at.desc")
            ],
            expectedUserID: expectedUserID
        )
        let data = try await performDataRequest(request)
        let rows = try JSONDecoder().decode([HiddenSupabaseTrainingDayRow].self, from: data)
        return try rows.map { try $0.asDay() }
    }

    func upsertTrainingDays(
        _ days: [WorkoutDay],
        expectedUserID: UUID
    ) async throws {
        guard !days.isEmpty else { return }
        try await upsertTrainingDaysPayload(
            days.map(HiddenSupabaseTrainingDayPayload.init(day:)),
            expectedUserID: expectedUserID
        )
    }

    func upsertTrainingDay(_ day: WorkoutDay, expectedUserID: UUID) async throws {
        try await upsertTrainingDaysPayload(
            [HiddenSupabaseTrainingDayPayload(day: day)],
            expectedUserID: expectedUserID
        )
    }

    func fetchExpenseMonthlyClaims(expectedUserID: UUID) async throws -> [MonthlyExpenseClaim] {
        let request = try await authorizedRESTRequest(
            path: "/rest/v1/expense_monthly_claims",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "month_start.desc")
            ],
            expectedUserID: expectedUserID
        )
        let data = try await performDataRequest(request)
        let rows = try JSONDecoder().decode([HiddenSupabaseExpenseMonthlyRow].self, from: data)
        return rows.compactMap { $0.asClaim() }
    }

    func upsertExpenseMonthlyClaims(
        _ claims: [MonthlyExpenseClaim],
        expectedUserID: UUID
    ) async throws {
        guard !claims.isEmpty else { return }
        try await upsertExpenseMonthlyClaimsPayload(
            claims.map(HiddenSupabaseExpenseMonthlyPayload.init(claim:)),
            expectedUserID: expectedUserID
        )
    }

    func upsertExpenseMonthlyClaim(
        _ claim: MonthlyExpenseClaim,
        expectedUserID: UUID
    ) async throws {
        try await upsertExpenseMonthlyClaimsPayload(
            [HiddenSupabaseExpenseMonthlyPayload(claim: claim)],
            expectedUserID: expectedUserID
        )
    }

    func fetchExpenseTravelClaims(expectedUserID: UUID) async throws -> [TravelExpenseClaim] {
        let request = try await authorizedRESTRequest(
            path: "/rest/v1/expense_travel_claims",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "updated_at.desc")
            ],
            expectedUserID: expectedUserID
        )
        let data = try await performDataRequest(request)
        let rows = try JSONDecoder().decode([HiddenSupabaseExpenseTravelRow].self, from: data)
        return rows.compactMap { $0.asClaim() }
    }

    func upsertExpenseTravelClaims(
        _ claims: [TravelExpenseClaim],
        expectedUserID: UUID
    ) async throws {
        guard !claims.isEmpty else { return }
        try await upsertExpenseTravelClaimsPayload(
            claims.map(HiddenSupabaseExpenseTravelPayload.init(claim:)),
            expectedUserID: expectedUserID
        )
    }

    func upsertExpenseTravelClaim(
        _ claim: TravelExpenseClaim,
        expectedUserID: UUID
    ) async throws {
        try await upsertExpenseTravelClaimsPayload(
            [HiddenSupabaseExpenseTravelPayload(claim: claim)],
            expectedUserID: expectedUserID
        )
    }

    private func upsertFavoritesPayload(
        _ payload: [HiddenSupabaseFavoritePayload],
        expectedUserID: UUID
    ) async throws {
        let body = try JSONEncoder().encode(payload)
        let request = try await authorizedRESTRequest(
            path: "/rest/v1/jav_favorites",
            method: "POST",
            queryItems: [
                URLQueryItem(name: "on_conflict", value: "user_id,movie_id")
            ],
            body: body,
            prefer: "resolution=merge-duplicates,missing=default,return=minimal",
            expectedUserID: expectedUserID
        )

        _ = try await performDataRequest(request)
    }

    private func upsertPlaybacksPayload(
        _ payload: [HiddenSupabasePlaybackPayload],
        expectedUserID: UUID
    ) async throws {
        let body = try JSONEncoder().encode(payload)
        let request = try await authorizedRESTRequest(
            path: "/rest/v1/jav_playbacks",
            method: "POST",
            queryItems: [
                URLQueryItem(name: "on_conflict", value: "id")
            ],
            body: body,
            prefer: "resolution=merge-duplicates,missing=default,return=minimal",
            expectedUserID: expectedUserID
        )

        _ = try await performDataRequest(request)
    }

    private func upsert4KHDAlbumsPayload(
        _ payload: [HiddenSupabase4KHDAlbumPayload],
        expectedUserID: UUID
    ) async throws {
        let body = try JSONEncoder().encode(payload)
        let request = try await authorizedRESTRequest(
            path: "/rest/v1/fourkhd_favorite_albums",
            method: "POST",
            queryItems: [
                URLQueryItem(name: "on_conflict", value: "user_id,album_id")
            ],
            body: body,
            prefer: "resolution=merge-duplicates,missing=default,return=minimal",
            expectedUserID: expectedUserID
        )

        _ = try await performDataRequest(request)
    }

    private func upsert4KHDImagesPayload(
        _ payload: [HiddenSupabase4KHDImagePayload],
        expectedUserID: UUID
    ) async throws {
        let body = try JSONEncoder().encode(payload)
        let request = try await authorizedRESTRequest(
            path: "/rest/v1/fourkhd_favorite_images",
            method: "POST",
            queryItems: [
                URLQueryItem(name: "on_conflict", value: "user_id,image_id")
            ],
            body: body,
            prefer: "resolution=merge-duplicates,missing=default,return=minimal",
            expectedUserID: expectedUserID
        )

        _ = try await performDataRequest(request)
    }

    private func upsertUTEntriesPayload(
        _ payload: [HiddenSupabaseUTEntryPayload],
        expectedUserID: UUID
    ) async throws {
        let body = try JSONEncoder().encode(payload)
        let request = try await authorizedRESTRequest(
            path: "/rest/v1/ut_entries",
            method: "POST",
            queryItems: [
                URLQueryItem(name: "on_conflict", value: "user_id,entry_id")
            ],
            body: body,
            prefer: "resolution=merge-duplicates,missing=default,return=minimal",
            expectedUserID: expectedUserID
        )

        _ = try await performDataRequest(request)
    }

    private func upsertQingLongPanelProfilesPayload(
        _ payload: [HiddenSupabaseQingLongPanelProfilePayload],
        expectedUserID: UUID
    ) async throws {
        let body = try JSONEncoder().encode(payload)
        let request = try await authorizedRESTRequest(
            path: "/rest/v1/qinglong_panel_profiles",
            method: "POST",
            queryItems: [
                URLQueryItem(name: "on_conflict", value: "user_id,profile_id")
            ],
            body: body,
            prefer: "resolution=merge-duplicates,missing=default,return=minimal",
            expectedUserID: expectedUserID
        )

        _ = try await performDataRequest(request)
    }

    private func upsertTrainingDaysPayload(
        _ payload: [HiddenSupabaseTrainingDayPayload],
        expectedUserID: UUID
    ) async throws {
        let body = try JSONEncoder().encode(payload)
        let request = try await authorizedRESTRequest(
            path: "/rest/v1/training_log_days",
            method: "POST",
            queryItems: [
                URLQueryItem(name: "on_conflict", value: "user_id,day_id")
            ],
            body: body,
            prefer: "resolution=merge-duplicates,missing=default,return=minimal",
            expectedUserID: expectedUserID
        )
        _ = try await performDataRequest(request)
    }

    private func upsertExpenseMonthlyClaimsPayload(
        _ payload: [HiddenSupabaseExpenseMonthlyPayload],
        expectedUserID: UUID
    ) async throws {
        let body = try JSONEncoder().encode(payload)
        let request = try await authorizedRESTRequest(
            path: "/rest/v1/expense_monthly_claims",
            method: "POST",
            queryItems: [
                URLQueryItem(name: "on_conflict", value: "user_id,claim_id")
            ],
            body: body,
            prefer: "resolution=merge-duplicates,missing=default,return=minimal",
            expectedUserID: expectedUserID
        )
        _ = try await performDataRequest(request)
    }

    private func upsertExpenseTravelClaimsPayload(
        _ payload: [HiddenSupabaseExpenseTravelPayload],
        expectedUserID: UUID
    ) async throws {
        let body = try JSONEncoder().encode(payload)
        let request = try await authorizedRESTRequest(
            path: "/rest/v1/expense_travel_claims",
            method: "POST",
            queryItems: [
                URLQueryItem(name: "on_conflict", value: "user_id,claim_id")
            ],
            body: body,
            prefer: "resolution=merge-duplicates,missing=default,return=minimal",
            expectedUserID: expectedUserID
        )
        _ = try await performDataRequest(request)
    }

    private func authorizedRESTRequest(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        prefer: String? = nil,
        expectedUserID: UUID
    ) async throws -> URLRequest {
        let validSession = try await validSession()
        if validSession.userID != expectedUserID {
            throw sessionSupersededError()
        }
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

        let snapshot = sessionSnapshot(for: currentSession)
        guard !currentSession.refreshToken.isEmpty else {
            invalidateSession(ifMatching: snapshot)
            return nil
        }

        if let refreshOperation,
           refreshOperation.snapshot == snapshot {
            return try await resolveRefreshOperation(refreshOperation)
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

        let transport = self.transport
        let task = Task<Data, Error> {
            try Task.checkCancellation()
            let response = try await transport(request)
            try Task.checkCancellation()
            return try Self.validatedData(from: response)
        }
        let operation = RefreshOperation(id: UUID(), snapshot: snapshot, task: task)
        refreshOperation = operation

        return try await resolveRefreshOperation(operation)
    }

    private func resolveRefreshOperation(_ operation: RefreshOperation) async throws -> HiddenSupabaseSession? {
        let data: Data
        do {
            data = try await operation.task.value
        } catch {
            if refreshOperation?.id == operation.id {
                refreshOperation = nil
                if isDefinitiveRefreshInvalidation(error) {
                    invalidateSession(ifMatching: operation.snapshot)
                }
            }
            throw error
        }

        let parsedSession: HiddenSupabaseSession
        do {
            guard let candidate = try parseSession(fromAuthResponse: data) else {
                throw NSError(
                    domain: "HiddenSupabaseService",
                    code: -6,
                    userInfo: [NSLocalizedDescriptionKey: "云端刷新成功，但响应中没有完整会话"]
                )
            }
            parsedSession = candidate
        } catch {
            // A completed refresh Task must never remain single-flight state
            // after response parsing fails, otherwise every later caller
            // re-awaits the permanently failed Task.
            if refreshOperation?.id == operation.id {
                refreshOperation = nil
            }
            throw error
        }

        let refreshedSession: HiddenSupabaseSession
        do {
            refreshedSession = try reconciledRefreshSession(
                parsedSession,
                expected: operation.snapshot
            )
        } catch {
            if refreshOperation?.id == operation.id {
                refreshOperation = nil
            }
            throw error
        }

        // More than one caller may await the same Task. The first caller commits
        // once; subsequent callers return that exact committed session.
        guard refreshOperation?.id == operation.id else {
            if operation.snapshot.generation == sessionGeneration,
               let session,
               session.accessToken == refreshedSession.accessToken,
               session.refreshToken == refreshedSession.refreshToken,
               session.userID == refreshedSession.userID {
                return session
            }
            throw sessionSupersededError()
        }

        guard isCurrent(operation.snapshot) else {
            refreshOperation = nil
            throw sessionSupersededError()
        }

        do {
            try persist(session: refreshedSession)
            refreshOperation = nil
            return refreshedSession
        } catch {
            refreshOperation = nil
            throw error
        }
    }

    private func persist(session newSession: HiddenSupabaseSession) throws {
        try sessionStore.save(newSession)
        session = newSession
    }

    private func beginSessionReplacement() -> UInt64 {
        advanceSessionGeneration()
        return sessionGeneration
    }

    private func advanceSessionGeneration() {
        sessionGeneration &+= 1
        refreshOperation?.task.cancel()
        refreshOperation = nil
    }

    private func ensureCurrentGeneration(_ expectedGeneration: UInt64) throws {
        guard sessionGeneration == expectedGeneration else {
            throw sessionSupersededError()
        }
    }

    private func sessionSnapshot(for session: HiddenSupabaseSession) -> SessionSnapshot {
        SessionSnapshot(
            generation: sessionGeneration,
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            userID: session.userID,
            email: session.email
        )
    }

    private func isCurrent(_ snapshot: SessionSnapshot) -> Bool {
        guard snapshot.generation == sessionGeneration, let session else {
            return false
        }

        return session.accessToken == snapshot.accessToken
            && session.refreshToken == snapshot.refreshToken
            && session.userID == snapshot.userID
    }

    private func invalidateSession(ifMatching snapshot: SessionSnapshot) {
        guard isCurrent(snapshot) else { return }
        advanceSessionGeneration()
        session = nil
        sessionStore.clear()
    }

    private func reconciledRefreshSession(
        _ refreshedSession: HiddenSupabaseSession,
        expected: SessionSnapshot
    ) throws -> HiddenSupabaseSession {
        if let expectedUserID = expected.userID,
           let refreshedUserID = refreshedSession.userID,
           refreshedUserID != expectedUserID {
            throw NSError(
                domain: "HiddenSupabaseService",
                code: -7,
                userInfo: [NSLocalizedDescriptionKey: "云端刷新返回了其他账号的会话，已拒绝写入"]
            )
        }

        return HiddenSupabaseSession(
            accessToken: refreshedSession.accessToken,
            refreshToken: refreshedSession.refreshToken,
            expiresAt: refreshedSession.expiresAt,
            userID: refreshedSession.userID ?? expected.userID,
            email: refreshedSession.email ?? expected.email
        )
    }

    private func sessionSupersededError() -> NSError {
        NSError(
            domain: "HiddenSupabaseService",
            code: -8,
            userInfo: [NSLocalizedDescriptionKey: "云端会话操作已被更新的登录状态取代"]
        )
    }

    private func isDefinitiveRefreshInvalidation(_ error: Error) -> Bool {
        HiddenSupabaseAuthFailureClassifier.isDefinitiveSessionInvalidation(error)
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
        guard let configuration = configurationProvider() else {
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

    private func performDataRequest(
        _ request: URLRequest,
        canRetryUnauthorized: Bool = true
    ) async throws -> Data {
        let authorizedSnapshot = try authorizedSessionSnapshot(for: request)

        do {
            let response = try await transport(request)

            if let authorizedSnapshot, !isCurrent(authorizedSnapshot) {
                throw sessionSupersededError()
            }

            return try Self.validatedData(from: response)
        } catch let requestError {
            let nsError = requestError as NSError
            if nsError.domain == "HiddenSupabaseService",
               nsError.code == 401,
               let authorizedSnapshot {
                if canRetryUnauthorized, isCurrent(authorizedSnapshot) {
                    do {
                        guard let refreshedSession = try await refreshSessionIfNeeded(force: true) else {
                            throw requestError
                        }

                        var retryRequest = request
                        retryRequest.setValue(
                            "Bearer \(refreshedSession.accessToken)",
                            forHTTPHeaderField: "Authorization"
                        )
                        return try await performDataRequest(
                            retryRequest,
                            canRetryUnauthorized: false
                        )
                    } catch let recoveryError {
                        // A definitive refresh rejection already cleared the
                        // store. Surface the original 401 so UI auth state also
                        // transitions once; transient refresh failures are kept.
                        if session == nil {
                            throw requestError
                        }
                        throw recoveryError
                    }
                }

                // A second 401 rejects a freshly rotated access token. Clear
                // only if it is still the exact current session; an old request
                // must never sign out a newer account.
                invalidateSession(ifMatching: authorizedSnapshot)
            }
            throw requestError
        }
    }

    private func authorizedSessionSnapshot(for request: URLRequest) throws -> SessionSnapshot? {
        guard let authorization = request.value(forHTTPHeaderField: "Authorization"),
              authorization.hasPrefix("Bearer ") else {
            return nil
        }

        let accessToken = String(authorization.dropFirst("Bearer ".count))
        guard let session, session.accessToken == accessToken else {
            throw sessionSupersededError()
        }

        return sessionSnapshot(for: session)
    }

    private static func validatedData(from result: (Data, URLResponse)) throws -> Data {
        let (data, response) = result
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
            var userInfo: [String: Any] = [NSLocalizedDescriptionKey: message]
            if let authErrorCode = payload?.resolvedCode?.cloudNonEmpty {
                userInfo[HiddenSupabaseAuthFailureClassifier.errorCodeUserInfoKey] = authErrorCode
            }

            throw NSError(
                domain: "HiddenSupabaseService",
                code: httpResponse.statusCode,
                userInfo: userInfo
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

        // 403 is commonly a valid-session authorization/RLS denial. Treating it
        // as logout caused the UI to repeatedly "lose" and restore the same session.
        return HiddenSupabaseAuthFailureClassifier.isDefinitiveSessionInvalidation(self)
    }
}
