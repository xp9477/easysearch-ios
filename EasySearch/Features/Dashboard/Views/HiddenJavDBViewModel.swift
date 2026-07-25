import Foundation
import Combine

@MainActor
final class HiddenJavDBViewModel: ObservableObject {
    @Published var randomMovies: [HiddenJavDBMovie] = []
    @Published var isLoadingRandomMovie = false
    @Published var randomErrorMessage: String?
    @Published var searchedMovies: [HiddenJavDBMovie] = []
    @Published var isSearchingMovies = false
    @Published var searchMovieErrorMessage: String?
    @Published var lastSearchedMovieQuery: String?
    @Published var favoriteMovies: [HiddenJavDBMovie] = []
    @Published var favoritePlaybacks: [HiddenJavDBFavoritePlayback] = []
    @Published var detailsByMovieID: [String: HiddenJavDBMovieDetail] = [:]
    @Published var detailErrorsByMovieID: [String: String] = [:]
    @Published var detailLoadingIDs: Set<String> = []
    @Published var isCloudConfigured = false
    @Published var isCloudAuthenticated = false
    @Published var cloudUserEmail: String?
    @Published var cloudStatusMessage: String?
    @Published var isPreparingCloud = false
    @Published var isCloudBusy = false

    private var cachedTotalPages: Int?
    private var randomLoadSessionID = UUID()
    private var didPrepareCloud = false
    private let cloudService = HiddenSupabaseService.shared

    private static let randomMovieCount = 9

    init() {
        loadFavoriteMovies()
        loadFavoritePlaybacks()
    }

    func prepareCloudIfNeeded() async {
        guard !didPrepareCloud else { return }
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
                applyCloudSession(session)
                await syncCloudNow(reason: "已恢复云端会话")
            } else {
                isCloudAuthenticated = false
                cloudUserEmail = nil
                cloudStatusMessage = "云端已配置，但尚未登录。当前仍会保存在本地。"
            }
        } catch {
            isCloudAuthenticated = false
            cloudUserEmail = nil
            cloudStatusMessage = "云端会话恢复失败：\(error.localizedDescription)"
        }
    }

    func loadRandomMovieIfNeeded() async {
        guard randomMovies.isEmpty else { return }
        await loadRandomMovies()
    }

    func loadRandomMovies() async {
        guard !isLoadingRandomMovie else { return }

        let sessionID = UUID()
        randomLoadSessionID = sessionID
        isLoadingRandomMovie = true
        randomErrorMessage = nil
        randomMovies = []

        defer {
            if randomLoadSessionID == sessionID {
                isLoadingRandomMovie = false
            }
        }

        do {
            try await fetchRandomMoviesProgressively(count: Self.randomMovieCount, sessionID: sessionID)
        } catch {
            if randomLoadSessionID == sessionID {
                randomErrorMessage = error.localizedDescription
            }
        }
    }

    func searchMovies(query: String) async {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            resetSearchMovies()
            return
        }

        guard !isSearchingMovies else { return }

        isSearchingMovies = true
        searchMovieErrorMessage = nil
        lastSearchedMovieQuery = normalizedQuery

        defer {
            isSearchingMovies = false
        }

        do {
            searchedMovies = try await HiddenJavDBAPI.searchMovies(query: normalizedQuery)
        } catch {
            searchedMovies = []
            searchMovieErrorMessage = error.localizedDescription
        }
    }

    func resetSearchMovies() {
        searchedMovies = []
        searchMovieErrorMessage = nil
        lastSearchedMovieQuery = nil
    }

    func toggleFavorite(_ movie: HiddenJavDBMovie) {
        let shouldRemove = favoriteMovies.contains(where: { $0.id == movie.id })
        if let index = favoriteMovies.firstIndex(where: { $0.id == movie.id }) {
            favoriteMovies.remove(at: index)
        } else {
            favoriteMovies.insert(movie, at: 0)
        }
        saveFavoriteMovies()

        guard isCloudAuthenticated else { return }
        Task {
            await syncFavoriteMutation(movie: movie, shouldRemove: shouldRemove)
        }
    }

    func isFavorite(_ movie: HiddenJavDBMovie) -> Bool {
        favoriteMovies.contains(where: { $0.id == movie.id })
    }

    @discardableResult
    func saveFavoritePlayback(_ playback: HiddenJavDBFavoritePlayback) -> HiddenJavDBFavoritePlaybackSaveContext {
        ensureFavoriteMovie(playback.movie)

        var storedPlayback = playback
        var replacedPlayback: HiddenJavDBFavoritePlayback?
        if let existingIndex = favoritePlaybacks.firstIndex(where: {
            $0.movie.id == playback.movie.id &&
            $0.sourceName == playback.sourceName &&
            $0.streamURL.absoluteString == playback.streamURL.absoluteString &&
            abs($0.positionSeconds - playback.positionSeconds) < 2
        }) {
            let existing = favoritePlaybacks[existingIndex]
            favoritePlaybacks.remove(at: existingIndex)
            replacedPlayback = existing
            storedPlayback = HiddenJavDBFavoritePlayback(
                id: existing.id,
                movie: playback.movie,
                sourceName: playback.sourceName,
                streamURL: playback.streamURL,
                refererURL: playback.refererURL,
                positionSeconds: playback.positionSeconds,
                createdAt: Date()
            )
        }

        favoritePlaybacks.insert(storedPlayback, at: 0)
        if favoritePlaybacks.count > 120 {
            favoritePlaybacks = Array(favoritePlaybacks.prefix(120))
        }
        saveFavoritePlaybacks()

        if isCloudAuthenticated {
            Task {
                await syncPlaybackUpsert(storedPlayback)
            }
        }

        return HiddenJavDBFavoritePlaybackSaveContext(
            savedPlayback: storedPlayback,
            replacedPlayback: replacedPlayback,
            markerPositions: playbackMarkerPositions(for: playback.movie)
        )
    }

    @discardableResult
    func undoFavoritePlaybackSave(_ context: HiddenJavDBFavoritePlaybackSaveContext) -> [Double] {
        favoritePlaybacks.removeAll { $0.id == context.savedPlayback.id }

        if let replacedPlayback = context.replacedPlayback {
            favoritePlaybacks.insert(replacedPlayback, at: 0)
        }

        saveFavoritePlaybacks()

        guard isCloudAuthenticated else {
            return playbackMarkerPositions(for: context.savedPlayback.movie)
        }

        Task {
            if let replacedPlayback = context.replacedPlayback {
                await syncPlaybackUpsert(replacedPlayback)
            } else {
                await syncPlaybackDeletion(context.savedPlayback)
            }
        }

        return playbackMarkerPositions(for: context.savedPlayback.movie)
    }

    func removeFavoritePlayback(_ playback: HiddenJavDBFavoritePlayback) {
        favoritePlaybacks.removeAll { $0.id == playback.id }
        saveFavoritePlaybacks()

        guard isCloudAuthenticated else { return }
        Task {
            await syncPlaybackDeletion(playback)
        }
    }

    func favoritePlaybacks(for movie: HiddenJavDBMovie) -> [HiddenJavDBFavoritePlayback] {
        favoritePlaybacks.filter { $0.movie.id == movie.id }
    }

    func playbackMarkerPositions(for movie: HiddenJavDBMovie) -> [Double] {
        let sortedPositions = favoritePlaybacks(for: movie)
            .map(\.positionSeconds)
            .filter { $0.isFinite && $0 >= 0 }
            .sorted()

        var markerPositions: [Double] = []
        markerPositions.reserveCapacity(sortedPositions.count)

        for position in sortedPositions {
            if let last = markerPositions.last, abs(last - position) < 2 {
                continue
            }
            markerPositions.append(position)
        }

        return markerPositions
    }

    func signIn(email: String, password: String) async {
        guard isCloudConfigured else {
            cloudStatusMessage = "请先在 Info.plist 配置 Supabase。"
            return
        }

        isCloudBusy = true
        defer { isCloudBusy = false }

        do {
            let session = try await cloudService.signIn(email: email, password: password)
            applyCloudSession(session)
            await syncCloudNow(reason: "登录成功")
        } catch {
            cloudStatusMessage = "登录失败：\(error.localizedDescription)"
        }
    }

    func signUp(email: String, password: String) async {
        guard isCloudConfigured else {
            cloudStatusMessage = "请先在 Info.plist 配置 Supabase。"
            return
        }

        isCloudBusy = true
        defer { isCloudBusy = false }

        do {
            let outcome = try await cloudService.signUp(email: email, password: password)
            switch outcome {
            case let .authenticated(session):
                applyCloudSession(session)
                await syncCloudNow(reason: "注册成功")
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

    func syncCloudNow() async {
        await syncCloudNow(reason: "同步成功")
    }

    func loadDetailIfNeeded(for movie: HiddenJavDBMovie) async {
        if detailsByMovieID[movie.id] != nil || detailLoadingIDs.contains(movie.id) {
            return
        }

        detailLoadingIDs.insert(movie.id)
        detailErrorsByMovieID[movie.id] = nil

        defer {
            detailLoadingIDs.remove(movie.id)
        }

        do {
            let detail = try await HiddenJavDBAPI.fetchMovieDetail(for: movie)
            detailsByMovieID[movie.id] = detail
        } catch {
            detailErrorsByMovieID[movie.id] = error.localizedDescription
        }
    }

    private func fetchRandomMoviesProgressively(count: Int, sessionID: UUID) async throws {
        var seen = Set<String>()
        var attempts = 0
        let maxAttempts = max(18, count * 12)

        while randomMovies.count < count && attempts < maxAttempts {
            try Task.checkCancellation()
            guard randomLoadSessionID == sessionID else {
                return
            }

            attempts += 1
            let result = try await HiddenJavDBAPI.fetchRandomMovie(knownTotalPages: cachedTotalPages)
            cachedTotalPages = result.totalPages

            let movie = result.movie
            if seen.insert(movie.id).inserted {
                randomMovies.append(movie)
            }
        }

        guard !randomMovies.isEmpty else {
            throw NSError(
                domain: "HiddenJavDBViewModel",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "没有拿到可用影片，请重试"]
            )
        }
    }

    private func applyCloudSession(_ session: HiddenSupabaseSession) {
        isCloudAuthenticated = true
        cloudUserEmail = session.email
        if let email = session.email?.nonEmpty {
            cloudStatusMessage = "已登录 \(email)"
        } else {
            cloudStatusMessage = "已登录云端同步"
        }
    }

    private func syncCloudNow(reason: String) async {
        guard isCloudAuthenticated else { return }

        isCloudBusy = true
        defer { isCloudBusy = false }

        do {
            let remoteFavorites = try await cloudService.fetchFavorites()
            let remotePlaybacks = try await cloudService.fetchPlaybacks()

            let mergedFavorites = HiddenCloudMerge.movies(primary: remoteFavorites, secondary: favoriteMovies)
            let mergedPlaybacks = HiddenCloudMerge.playbacks(primary: remotePlaybacks, secondary: favoritePlaybacks)

            favoriteMovies = mergedFavorites
            favoritePlaybacks = mergedPlaybacks
            saveFavoriteMovies()
            saveFavoritePlaybacks()

            try await cloudService.upsertFavorites(mergedFavorites)
            try await cloudService.upsertPlaybacks(mergedPlaybacks)

            cloudStatusMessage = reason
        } catch {
            cloudStatusMessage = "云端同步失败：\(error.localizedDescription)"
        }
    }

    private func syncFavoriteMutation(movie: HiddenJavDBMovie, shouldRemove: Bool) async {
        do {
            if shouldRemove {
                try await cloudService.deleteFavorite(movieID: movie.id)
            } else {
                try await cloudService.upsertFavorite(movie)
            }
            cloudStatusMessage = shouldRemove ? "已从云端移除喜欢影片" : "已同步喜欢影片到云端"
        } catch {
            cloudStatusMessage = "喜欢影片云端同步失败：\(error.localizedDescription)"
        }
    }

    private func syncPlaybackUpsert(_ playback: HiddenJavDBFavoritePlayback) async {
        do {
            try await cloudService.upsertPlayback(playback)
            cloudStatusMessage = "已同步播放收藏到云端"
        } catch {
            cloudStatusMessage = "播放收藏云端同步失败：\(error.localizedDescription)"
        }
    }

    private func syncPlaybackDeletion(_ playback: HiddenJavDBFavoritePlayback) async {
        do {
            try await cloudService.deletePlayback(id: playback.id)
            cloudStatusMessage = "已从云端移除播放收藏"
        } catch {
            cloudStatusMessage = "播放收藏删除失败：\(error.localizedDescription)"
        }
    }

    private func loadFavoriteMovies() {
        favoriteMovies = HiddenJavDBLocalStore.loadFavoriteMovies()
    }

    private func saveFavoriteMovies() {
        HiddenJavDBLocalStore.saveFavoriteMovies(favoriteMovies)
    }

    private func loadFavoritePlaybacks() {
        favoritePlaybacks = HiddenJavDBLocalStore.loadFavoritePlaybacks()
    }

    private func saveFavoritePlaybacks() {
        HiddenJavDBLocalStore.saveFavoritePlaybacks(favoritePlaybacks)
    }

    private func ensureFavoriteMovie(_ movie: HiddenJavDBMovie) {
        guard !favoriteMovies.contains(where: { $0.id == movie.id }) else { return }

        favoriteMovies.insert(movie, at: 0)
        saveFavoriteMovies()

        guard isCloudAuthenticated else { return }
        Task {
            await syncFavoriteMutation(movie: movie, shouldRemove: false)
        }
    }
}
