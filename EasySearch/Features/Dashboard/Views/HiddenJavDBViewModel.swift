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
    private var cachedTotalPages: Int?
    private var randomLoadSessionID = UUID()

    /// Mirrored from the app-wide cloud owner for UI bindings in this feature.
    var isCloudConfigured: Bool { CloudSyncViewModel.shared.isCloudConfigured }
    var isCloudAuthenticated: Bool { CloudSyncViewModel.shared.isCloudAuthenticated }
    var cloudUserEmail: String? { CloudSyncViewModel.shared.cloudUserEmail }
    var cloudStatusMessage: String? { CloudSyncViewModel.shared.cloudStatusMessage }
    var isPreparingCloud: Bool { CloudSyncViewModel.shared.isPreparingCloud }
    var isCloudBusy: Bool { CloudSyncViewModel.shared.isCloudBusy }

    private static let randomMovieCount = 9

    init() {
        loadFavoriteMovies()
        loadFavoritePlaybacks()
    }

    /// Single owner: app-wide CloudSyncViewModel. Then reload local favorites into this VM.
    func prepareCloudIfNeeded() async {
        await CloudSyncViewModel.shared.prepareIfNeeded()
        loadFavoriteMovies()
        loadFavoritePlaybacks()
        objectWillChange.send()
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

        Task {
            await CloudSyncViewModel.shared.syncJavFavoriteIfPossible(
                movie,
                shouldRemove: shouldRemove
            )
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

        Task {
            await CloudSyncViewModel.shared.syncJavPlaybackUpsertIfPossible(storedPlayback)
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

        Task {
            if let replacedPlayback = context.replacedPlayback {
                await CloudSyncViewModel.shared.syncJavPlaybackUpsertIfPossible(replacedPlayback)
            } else {
                await CloudSyncViewModel.shared.syncJavPlaybackDeletionIfPossible(
                    playbackID: context.savedPlayback.id
                )
            }
        }

        return playbackMarkerPositions(for: context.savedPlayback.movie)
    }

    func removeFavoritePlayback(_ playback: HiddenJavDBFavoritePlayback) {
        favoritePlaybacks.removeAll { $0.id == playback.id }
        saveFavoritePlaybacks()

        Task {
            await CloudSyncViewModel.shared.syncJavPlaybackDeletionIfPossible(
                playbackID: playback.id
            )
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
        await CloudSyncViewModel.shared.signIn(email: email, password: password)
        loadFavoriteMovies()
        loadFavoritePlaybacks()
        objectWillChange.send()
    }

    func signUp(email: String, password: String) async {
        await CloudSyncViewModel.shared.signUp(email: email, password: password)
        loadFavoriteMovies()
        loadFavoritePlaybacks()
        objectWillChange.send()
    }

    func signOut() async {
        await CloudSyncViewModel.shared.signOut()
        objectWillChange.send()
    }

    func syncCloudNow() async {
        await CloudSyncViewModel.shared.syncNow()
        loadFavoriteMovies()
        loadFavoritePlaybacks()
        objectWillChange.send()
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

        Task {
            await CloudSyncViewModel.shared.syncJavFavoriteIfPossible(
                movie,
                shouldRemove: false
            )
        }
    }
}
