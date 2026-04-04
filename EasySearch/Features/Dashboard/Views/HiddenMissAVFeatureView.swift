import SwiftUI
import Foundation
import AVKit
@preconcurrency import AVFoundation
import UIKit

@MainActor
final class HiddenMissAVViewModel: ObservableObject {
    @Published var homeSections: [HiddenMissAVSection] = []
    @Published var isLoadingHome = false
    @Published var homeErrorMessage: String?
    @Published var searchResults: [HiddenMissAVMovie] = []
    @Published var isSearching = false
    @Published var searchErrorMessage: String?
    @Published var lastSearchQuery: String?
    @Published var favoriteMovies: [HiddenMissAVMovie] = []
    @Published var detailsByMovieID: [String: HiddenMissAVMovieDetail] = [:]
    @Published var detailErrorsByMovieID: [String: String] = [:]
    @Published var detailLoadingIDs: Set<String> = []
    private let cloudSyncViewModel = HiddenCloudSyncViewModel.shared
    private var favoriteMarkers: [HiddenMissAVFavoriteMarker]

    init() {
        favoriteMovies = []
        favoriteMarkers = []
        reloadLocalCollections()
    }

    func reloadLocalCollections() {
        favoriteMovies = HiddenMissAVLocalStore.loadFavoriteMovies()
        favoriteMarkers = HiddenMissAVLocalStore.loadFavoriteMarkers()
        HiddenMissAVLocalStore.clearWatchHistory()
    }

    func loadHomeIfNeeded(force: Bool) async {
        if isLoadingHome {
            return
        }
        if !force, !homeSections.isEmpty {
            return
        }

        isLoadingHome = true
        homeErrorMessage = nil
        defer { isLoadingHome = false }

        do {
            homeSections = try await HiddenMissAVAPI.fetchHomeSections()
        } catch {
            if homeSections.isEmpty {
                homeErrorMessage = error.localizedDescription
            }
        }
    }

    func searchMovies(query: String) async {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            clearSearch()
            return
        }

        isSearching = true
        searchErrorMessage = nil
        defer { isSearching = false }

        do {
            searchResults = try await HiddenMissAVAPI.searchMovies(query: normalizedQuery)
            lastSearchQuery = normalizedQuery
        } catch {
            searchResults = []
            lastSearchQuery = normalizedQuery
            searchErrorMessage = error.localizedDescription
        }
    }

    func clearSearch() {
        searchResults = []
        searchErrorMessage = nil
        lastSearchQuery = nil
    }

    func refreshForSettingsChange() async {
        homeSections = []
        homeErrorMessage = nil
        detailsByMovieID = [:]
        detailErrorsByMovieID = [:]

        if let lastSearchQuery, !lastSearchQuery.isEmpty {
            await searchMovies(query: lastSearchQuery)
        } else {
            await loadHomeIfNeeded(force: true)
        }
    }

    func loadDetailIfNeeded(for movie: HiddenMissAVMovie, force: Bool = false) async {
        if detailLoadingIDs.contains(movie.id) {
            return
        }
        if !force, detailsByMovieID[movie.id] != nil {
            return
        }

        detailLoadingIDs.insert(movie.id)
        detailErrorsByMovieID[movie.id] = nil
        defer { detailLoadingIDs.remove(movie.id) }

        do {
            detailsByMovieID[movie.id] = try await HiddenMissAVAPI.fetchMovieDetail(for: movie)
        } catch {
            detailErrorsByMovieID[movie.id] = error.localizedDescription
        }
    }

    func toggleFavorite(_ movie: HiddenMissAVMovie) {
        if isFavorite(movie) {
            favoriteMovies.removeAll { $0.id == movie.id }
            HiddenMissAVLocalStore.saveFavoriteMovies(favoriteMovies)
            Task {
                await cloudSyncViewModel.syncMissAVFavoriteDeletionIfPossible(movie)
            }
        } else {
            favoriteMovies.insert(movie, at: 0)
            HiddenMissAVLocalStore.saveFavoriteMovies(favoriteMovies)
            Task {
                await cloudSyncViewModel.syncMissAVFavoriteUpsertIfPossible(movie)
            }
        }
    }

    func isFavorite(_ movie: HiddenMissAVMovie) -> Bool {
        favoriteMovies.contains { $0.id == movie.id }
    }

    func resumePosition(for movie: HiddenMissAVMovie) -> Double {
        0
    }

    func markerPositions(for movie: HiddenMissAVMovie) -> [Double] {
        favoriteMarkers
            .filter { $0.normalizedMovieCode == markerStorageKey(for: movie) }
            .map(\.positionSeconds)
            .filter { $0.isFinite && $0 >= 0 }
            .sorted()
    }

    func savePlayback(
        movie: HiddenMissAVMovie,
        item: HiddenSharedPlayerItem,
        position: Double
    ) -> HiddenPlaybackSaveResult {
        let normalizedPosition = max(0, position)
        let snapshot = favoriteMarkers

        if let existingMarker = favoriteMarkers.first(where: {
            $0.normalizedMovieCode == markerStorageKey(for: movie) && abs($0.positionSeconds - normalizedPosition) < 1
        }) {
            return HiddenPlaybackSaveResult(
                savedPositionSeconds: existingMarker.positionSeconds,
                markerPositions: markerPositions(for: movie),
                undo: { [weak self] in
                    self?.markerPositions(for: movie) ?? []
                }
            )
        }

        let marker = HiddenMissAVFavoriteMarker(
            movieCode: movie.code,
            positionSeconds: normalizedPosition,
            createdAt: Date()
        )
        favoriteMarkers.append(marker)
        favoriteMarkers = normalizedFavoriteMarkers(favoriteMarkers)
        HiddenMissAVLocalStore.saveFavoriteMarkers(favoriteMarkers)

        Task {
            await cloudSyncViewModel.syncMissAVFavoriteMarkerUpsertIfPossible(marker)
        }

        return HiddenPlaybackSaveResult(
            savedPositionSeconds: normalizedPosition,
            markerPositions: markerPositions(for: movie),
            undo: { [weak self] in
                self?.favoriteMarkers = snapshot
                HiddenMissAVLocalStore.saveFavoriteMarkers(snapshot)
                Task {
                    await self?.cloudSyncViewModel.syncMissAVFavoriteMarkerDeletionIfPossible(marker)
                }
                return self?.markerPositions(for: movie) ?? []
            }
        )
    }

    func recordPlayback(
        movie: HiddenMissAVMovie,
        item: HiddenSharedPlayerItem,
        position: Double
    ) {
        return
    }

    private func markerStorageKey(for movie: HiddenMissAVMovie) -> String {
        movie.code.uppercased()
    }

    private func normalizedFavoriteMarkers(_ markers: [HiddenMissAVFavoriteMarker]) -> [HiddenMissAVFavoriteMarker] {
        let sortedMarkers = markers.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.positionSeconds > rhs.positionSeconds
            }

            return lhs.createdAt > rhs.createdAt
        }

        var normalized: [HiddenMissAVFavoriteMarker] = []
        for marker in sortedMarkers {
            guard marker.positionSeconds.isFinite, marker.positionSeconds >= 0 else { continue }
            if normalized.contains(where: { $0.matchesSameMarker(as: marker) }) {
                continue
            }
            normalized.append(marker)
        }
        return normalized
    }
}

enum HiddenMissAVLocalStore {
    private static let favoritesKey = "hidden_space.missav.favorite_movies"
    private static let favoriteMarkersKey = "hidden_space.missav.favorite_markers"
    private static let historyKey = "hidden_space.missav.watch_history"
    private static let userDefaults = UserDefaults.standard
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func loadFavoriteMovies() -> [HiddenMissAVMovie] {
        guard let data = userDefaults.data(forKey: favoritesKey),
              let movies = try? decoder.decode([HiddenMissAVMovie].self, from: data) else {
            return []
        }
        return movies
    }

    static func saveFavoriteMovies(_ movies: [HiddenMissAVMovie]) {
        guard let data = try? encoder.encode(movies) else { return }
        userDefaults.set(data, forKey: favoritesKey)
    }

    static func loadFavoriteMarkers() -> [HiddenMissAVFavoriteMarker] {
        guard let data = userDefaults.data(forKey: favoriteMarkersKey) else {
            return []
        }

        if let markers = try? decoder.decode([HiddenMissAVFavoriteMarker].self, from: data) {
            return markers
        }

        if let legacyPositions = try? decoder.decode([String: [Double]].self, from: data) {
            let markers = legacyFavoriteMarkers(from: legacyPositions)
            saveFavoriteMarkers(markers)
            return markers
        }

        return []
    }

    static func saveFavoriteMarkers(_ markers: [HiddenMissAVFavoriteMarker]) {
        guard let data = try? encoder.encode(markers) else { return }
        userDefaults.set(data, forKey: favoriteMarkersKey)
    }

    static func loadFavoriteMarkerPositions() -> [String: [Double]] {
        Dictionary(grouping: loadFavoriteMarkers(), by: \.normalizedMovieCode)
            .mapValues { markers in
                markers.map(\.positionSeconds).sorted()
            }
    }

    static func saveFavoriteMarkerPositions(_ positions: [String: [Double]]) {
        saveFavoriteMarkers(legacyFavoriteMarkers(from: positions))
    }

    static func clearWatchHistory() {
        userDefaults.removeObject(forKey: historyKey)
    }

    private static func legacyFavoriteMarkers(from positions: [String: [Double]]) -> [HiddenMissAVFavoriteMarker] {
        positions
            .flatMap { code, values in
                values.map { position in
                    HiddenMissAVFavoriteMarker(
                        movieCode: code,
                        positionSeconds: position,
                        createdAt: Date()
                    )
                }
            }
            .filter { $0.positionSeconds.isFinite && $0.positionSeconds >= 0 }
            .sorted { $0.createdAt > $1.createdAt }
    }
}

private enum HiddenMissAVAPI {
    private static let supportedLocales: Set<String> = ["cn", "en", "ja", "ko", "ms", "th", "de", "fr", "vi", "id", "fil", "pt"]
    private static let blockedPathComponents: Set<String> = [
        "search", "new", "release", "genres", "genre", "makers", "maker", "actors", "actor",
        "actresses", "actress", "history", "contact", "ads", "terms", "upload", "articles",
        "article", "site", "labels", "label", "directors", "director", "cn", "en", "ja"
    ]

    static func fetchHomeSections() async throws -> [HiddenMissAVSection] {
        let url = HiddenMissAVDomainConfiguration.currentLocalizedBaseURL()
        let html = try await HiddenMissAVPlaybackResolver.fetchHTML(from: url)
        let sections = parseHomeSections(from: html, baseURL: url)
        guard !sections.isEmpty else {
            throw NSError(
                domain: "HiddenMissAVAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "没有解析到首页影片分区"]
            )
        }
        return sections
    }

    static func searchMovies(query: String) async throws -> [HiddenMissAVMovie] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return [] }

        return try await fetchMoviePage(from: searchURL(query: normalizedQuery), limit: 60).movies
    }

    static func fetchMovies(from url: URL, limit: Int = 60) async throws -> [HiddenMissAVMovie] {
        try await fetchMoviePage(from: url, limit: limit).movies
    }

    static func fetchMoviePage(from url: URL, limit: Int? = 60) async throws -> HiddenMissAVMoviePage {
        let html = try await HiddenMissAVPlaybackResolver.fetchHTML(from: url)
        let serverPage = parseMoviePage(from: html, baseURL: url, limit: limit)
        if !serverPage.movies.isEmpty {
            return serverPage
        }

        let renderedHTML = try await HiddenJavDBWebHTMLFetcher.shared.fetchHTML(from: url)
        let renderedPage = parseMoviePage(from: renderedHTML, baseURL: url, limit: limit)
        if !renderedPage.movies.isEmpty {
            return renderedPage
        }

        throw NSError(
            domain: "HiddenMissAVAPI",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: "没有解析到可用结果"]
        )
    }

    static func fetchMovieDetail(for movie: HiddenMissAVMovie) async throws -> HiddenMissAVMovieDetail {
        let pageURL = HiddenMissAVDomainConfiguration.currentMovieURL(forCode: movie.code) ?? movie.url
        let html = try await HiddenMissAVPlaybackResolver.fetchHTML(from: pageURL)
        let renderedHTML = try? await HiddenJavDBWebHTMLFetcher.shared.fetchHTML(from: pageURL)
        let detailCode = firstNonEmpty([
            extractMetadataValue(label: "番号", from: html),
            extractMetadataValue(label: "番號", from: html)
        ]) ?? movie.code
        let detailTitle = firstNonEmpty([
            extractMetadataValue(label: "标题", from: html),
            extractMetadataValue(label: "標題", from: html),
            HiddenMissAVHTMLParser.regexFirstCapture(
                pattern: #"<meta\s+property=["']og:title["']\s+content=["']([^"']+)["']"#,
                in: html,
                dotMatchesLine: true
            ).map(HiddenMissAVHTMLParser.cleanTitle).map { stripLeadingCode($0, code: detailCode) }
        ]) ?? movie.title

        let releaseDate = firstNonEmpty([
            extractMetadataValue(label: "发行日期", from: html),
            HiddenMissAVHTMLParser.regexFirstCapture(
                pattern: #"<meta\s+property=["']og:video:release_date["']\s+content=["']([^"']+)["']"#,
                in: html,
                dotMatchesLine: true
            )
        ])

        let actresses = extractMetadataList(label: "女优", from: html)
        let actors = extractMetadataList(label: "男优", from: html)
        let tags = extractMetadataList(label: "类型", from: html)
        let studio = firstNonEmpty([
            extractMetadataValue(label: "发行商", from: html),
            extractMetadataValue(label: "片商", from: html)
        ])
        let director = extractMetadataValue(label: "导演", from: html)
        let label = firstNonEmpty([
            extractMetadataValue(label: "标籤", from: html),
            extractMetadataValue(label: "标签", from: html)
        ])
        let screenshots = parseScreenshotURLs(from: html, movie: movie)
        let normalizedMovie = HiddenMissAVMovie(
            url: HiddenMissAVDomainConfiguration.currentMovieURL(forCode: detailCode) ?? movie.url,
            code: detailCode,
            title: detailTitle,
            coverURL: screenshots.first ?? movie.coverURL,
            previewVideoURL: movie.previewVideoURL ?? normalizePreviewURL(from: movie.coverURL),
            durationText: movie.durationText,
            hasChineseSubtitle: movie.hasChineseSubtitle,
            hasEnglishSubtitle: movie.hasEnglishSubtitle,
            isUncensored: movie.isUncensored
        )
        let relatedMovies = parseRelatedMovies(
            renderedHTML: renderedHTML,
            fallbackHTML: html,
            currentMovie: normalizedMovie,
            baseURL: pageURL
        )

        return HiddenMissAVMovieDetail(
            movie: normalizedMovie,
            releaseDate: releaseDate,
            actresses: actresses,
            actors: actors,
            tags: tags,
            studio: studio,
            director: director,
            label: label,
            screenshots: screenshots,
            relatedMovies: relatedMovies
        )
    }

    private static func searchURL(query: String) -> URL {
        HiddenMissAVDomainConfiguration.currentLocalizedBaseURL()
            .appendingPathComponent("search")
            .appendingPathComponent(query)
    }

    private static func parseHomeSections(from html: String, baseURL: URL) -> [HiddenMissAVSection] {
        let marker = #"<div class="sm:container mx-auto mb-5 px-4">"#
        let blocks = html.components(separatedBy: marker).dropFirst()

        var sections: [HiddenMissAVSection] = []
        for block in blocks {
            guard let title = HiddenMissAVHTMLParser.regexFirstCapture(
                pattern: #"<h2[^>]*>\s*(.*?)\s*</h2>"#,
                in: block,
                dotMatchesLine: true
            ).map(HiddenMissAVHTMLParser.cleanTitle)?.nonEmpty else {
                continue
            }

            let movies = parseMovies(from: block, baseURL: baseURL, limit: 24)
            guard !movies.isEmpty else { continue }

            let moreURL = HiddenMissAVHTMLParser.regexFirstCapture(
                pattern: #"<a[^>]+href=["']([^"']+)["'][^>]*>\s*更多"#,
                in: block,
                dotMatchesLine: true
            ).flatMap { HiddenMissAVHTMLParser.normalizedExternalURL(from: $0, relativeTo: baseURL) }

            sections.append(
                HiddenMissAVSection(
                    title: title,
                    moreURL: moreURL,
                    movies: movies
                )
            )
        }

        return sections
    }

    private static func parseRelatedMovies(
        renderedHTML: String?,
        fallbackHTML: String,
        currentMovie: HiddenMissAVMovie,
        baseURL: URL
    ) -> [HiddenMissAVMovie] {
        let renderedMovies = renderedHTML.map {
            parseMovies(from: $0, baseURL: baseURL, limit: 24)
        } ?? []

        if !renderedMovies.isEmpty {
            return dedupedMovies(renderedMovies.filter { $0.id != currentMovie.id }, limit: 18)
        }

        return dedupedMovies(
            parseMovies(from: fallbackHTML, baseURL: baseURL, limit: 24).filter { $0.id != currentMovie.id },
            limit: 18
        )
    }

    private static func parseMoviePage(from html: String, baseURL: URL, limit: Int?) -> HiddenMissAVMoviePage {
        HiddenMissAVMoviePage(
            movies: parseMovies(from: html, baseURL: baseURL, limit: limit),
            nextPageURL: parseNextPageURL(from: html, baseURL: baseURL)
        )
    }

    private static func parseMovies(from html: String, baseURL: URL, limit: Int?) -> [HiddenMissAVMovie] {
        let blocks = HiddenMissAVHTMLParser.regexFullMatches(
            pattern: #"<div[^>]*class=["'][^"']*thumbnail group[^"']*["'][^>]*>.*?</div>\s*</div>"#,
            in: html,
            dotMatchesLine: true
        )

        var movies: [HiddenMissAVMovie] = []
        var seen = Set<String>()

        for block in blocks {
            guard let movie = parseMovie(from: block, baseURL: baseURL) else { continue }
            guard seen.insert(movie.id).inserted else { continue }
            movies.append(movie)

            if let limit, movies.count >= limit {
                break
            }
        }

        return movies
    }

    private static func parseNextPageURL(from html: String, baseURL: URL) -> URL? {
        let patterns = [
            #"<a[^>]+href=["']([^"']+)["'][^>]*>\s*下一页\s*</a>"#,
            #"<a[^>]+href=["']([^"']+)["'][^>]*>\s*下一頁\s*</a>"#,
            #"<a[^>]+rel=["']next["'][^>]+href=["']([^"']+)["']"#,
            #"<a[^>]+href=["']([^"']+)["'][^>]+rel=["']next["']"#
        ]

        for pattern in patterns {
            if let rawValue = HiddenMissAVHTMLParser.regexFirstCapture(
                pattern: pattern,
                in: html,
                dotMatchesLine: true
            ),
            let url = HiddenMissAVHTMLParser.normalizedExternalURL(from: rawValue, relativeTo: baseURL) {
                return url
            }
        }

        return nil
    }

    private static func parseMovie(from block: String, baseURL: URL) -> HiddenMissAVMovie? {
        guard let rawURL = HiddenMissAVHTMLParser.regexFirstCapture(
            pattern: #"<a[^>]+href=["']([^"']+)["'][^>]*>"#,
            in: block,
            dotMatchesLine: true
        ),
        let absoluteURL = HiddenMissAVHTMLParser.normalizedExternalURL(from: rawURL, relativeTo: baseURL),
        let movieURL = normalizeMovieURL(absoluteURL),
        let code = extractMovieCode(from: movieURL) else {
            return nil
        }

        let coverRaw = firstNonEmpty([
            HiddenMissAVHTMLParser.regexFirstCapture(
                pattern: #"<img[^>]+data-src=["']([^"']+cover(?:-t|-n)?\.[^"']+)["']"#,
                in: block,
                dotMatchesLine: true
            ),
            HiddenMissAVHTMLParser.regexFirstCapture(
                pattern: #"<img[^>]+src=["']([^"']+cover(?:-t|-n)?\.[^"']+)["']"#,
                in: block,
                dotMatchesLine: true
            )
        ])

        guard let coverRaw,
              let coverURL = normalizeCoverURL(from: coverRaw, baseURL: baseURL) else {
            return nil
        }

        let fullTitle = firstNonEmpty([
            HiddenMissAVHTMLParser.regexFirstCapture(
                pattern: #"<div[^>]*class=["'][^"']*truncate[^"']*["'][^>]*>\s*<a[^>]*>(.*?)</a>"#,
                in: block,
                dotMatchesLine: true
            ),
            HiddenMissAVHTMLParser.regexFirstCapture(
                pattern: #"<a[^>]*class=["'][^"']*group-hover:text-primary[^"']*["'][^>]*>(.*?)</a>"#,
                in: block,
                dotMatchesLine: true
            ),
            HiddenMissAVHTMLParser.regexFirstCapture(
                pattern: #"<img[^>]+alt=["']([^"']+)["']"#,
                in: block,
                dotMatchesLine: true
            )
        ]).map(HiddenMissAVHTMLParser.cleanTitle)
        let title = fullTitle.map { stripLeadingCode($0, code: code) } ?? code
        let previewVideoURL = firstNonEmpty([
            HiddenMissAVHTMLParser.regexFirstCapture(
                pattern: #"<video[^>]+data-src=["']([^"']+preview\.mp4[^"']*)["']"#,
                in: block,
                dotMatchesLine: true
            ),
            HiddenMissAVHTMLParser.regexFirstCapture(
                pattern: #"<video[^>]+src=["']([^"']+preview\.mp4[^"']*)["']"#,
                in: block,
                dotMatchesLine: true
            )
        ]).flatMap { normalizePreviewURL(from: $0, baseURL: baseURL) } ?? normalizePreviewURL(from: coverURL)

        let durationText = HiddenMissAVHTMLParser.regexFirstCapture(
            pattern: #"<span[^>]*>\s*(\d{1,2}:\d{2}:\d{2})\s*</span>"#,
            in: block,
            dotMatchesLine: true
        )?.trimmingCharacters(in: .whitespacesAndNewlines)

        return HiddenMissAVMovie(
            url: movieURL,
            code: code,
            title: title.nonEmpty ?? code,
            coverURL: coverURL,
            previewVideoURL: previewVideoURL,
            durationText: durationText?.nonEmpty,
            hasChineseSubtitle: block.contains("中文字幕"),
            hasEnglishSubtitle: block.contains("英文字幕"),
            isUncensored: block.contains("无码影片") || block.contains("無碼影片")
        )
    }

    private static func parseScreenshotURLs(from html: String, movie: HiddenMissAVMovie) -> [URL] {
        let candidates = firstNonEmpty([
            HiddenMissAVHTMLParser.regexFirstCapture(
                pattern: #"<meta\s+property=["']og:image["']\s+content=["']([^"']+)["']"#,
                in: html,
                dotMatchesLine: true
            ),
            HiddenMissAVHTMLParser.regexFirstCapture(
                pattern: #"<link\s+rel=["']preload["']\s+as=["']image["']\s+href=["']([^"']+)["']"#,
                in: html,
                dotMatchesLine: true
            )
        ]).flatMap { normalizeCoverURL(from: $0, baseURL: movie.url) }

        guard let imageURL = candidates else {
            return [movie.coverURL]
        }
        return [imageURL]
    }

    private static func extractMetadataValue(label: String, from html: String) -> String? {
        let escapedLabel = NSRegularExpression.escapedPattern(for: label)
        let patterns = [
            #"<div[^>]*class=["'][^"']*text-secondary[^"']*["'][^>]*>\s*<span>\s*\#(escapedLabel):\s*</span>\s*<time[^>]*>(.*?)</time>"#,
            #"<div[^>]*class=["'][^"']*text-secondary[^"']*["'][^>]*>\s*<span>\s*\#(escapedLabel):\s*</span>\s*<span[^>]*class=["'][^"']*font-medium[^"']*["'][^>]*>(.*?)</span>"#,
            #"<div[^>]*class=["'][^"']*text-secondary[^"']*["'][^>]*>\s*<span>\s*\#(escapedLabel):\s*</span>\s*(.*?)</div>"#
        ]

        for pattern in patterns {
            if let rawValue = HiddenMissAVHTMLParser.regexFirstCapture(
                pattern: pattern,
                in: html,
                dotMatchesLine: true
            ) {
                let cleanedValue = HiddenMissAVHTMLParser.cleanTitle(rawValue)
                if let nonEmpty = cleanedValue.nonEmpty {
                    return nonEmpty
                }
            }
        }

        return nil
    }

    private static func extractMetadataList(label: String, from html: String) -> [String] {
        let escapedLabel = NSRegularExpression.escapedPattern(for: label)
        guard let block = HiddenMissAVHTMLParser.regexFirstCapture(
            pattern: #"<div[^>]*class=["'][^"']*text-secondary[^"']*["'][^>]*>\s*<span>\s*\#(escapedLabel):\s*</span>\s*(.*?)</div>"#,
            in: html,
            dotMatchesLine: true
        ) else {
            return []
        }

        let anchorValues = HiddenMissAVHTMLParser.regexCaptureAll(
            pattern: #"<a[^>]*>(.*?)</a>"#,
            in: block,
            dotMatchesLine: true
        )
        let values = anchorValues.isEmpty
            ? HiddenMissAVHTMLParser.cleanTitle(block)
                .components(separatedBy: ",")
                .map { HiddenMissAVHTMLParser.cleanTitle($0) }
            : anchorValues.map(HiddenMissAVHTMLParser.cleanTitle)

        var deduped: [String] = []
        var seen = Set<String>()
        for value in values {
            guard let normalizedValue = value.nonEmpty else { continue }
            if seen.insert(normalizedValue).inserted {
                deduped.append(normalizedValue)
            }
        }
        return deduped
    }

    private static func normalizeMovieURL(_ url: URL) -> URL? {
        guard let code = extractMovieCode(from: url) else {
            return nil
        }
        return HiddenMissAVDomainConfiguration.currentMovieURL(forCode: code)
    }

    private static func extractMovieCode(from url: URL) -> String? {
        var components = url.pathComponents.filter { $0 != "/" }
        if let first = components.first, first.lowercased().hasPrefix("dm") {
            components.removeFirst()
        }
        if let first = components.first, supportedLocales.contains(first.lowercased()) {
            components.removeFirst()
        }
        guard let lastComponent = components.last?.trimmingCharacters(in: .whitespacesAndNewlines),
              !lastComponent.isEmpty else {
            return nil
        }

        let normalized = lastComponent
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .lowercased()

        guard !blockedPathComponents.contains(normalized),
              !normalized.contains("."),
              normalized.range(of: #"^[a-z0-9][a-z0-9_-]*$"#, options: .regularExpression) != nil else {
            return nil
        }

        return normalized.uppercased()
    }

    private static func normalizeCoverURL(from raw: String, baseURL: URL) -> URL? {
        guard let url = HiddenMissAVHTMLParser.normalizedExternalURL(from: raw, relativeTo: baseURL) else {
            return nil
        }
        let normalized = url.absoluteString.replacingOccurrences(of: "/cover-t.", with: "/cover-n.")
        return URL(string: normalized) ?? url
    }

    private static func normalizePreviewURL(from raw: String, baseURL: URL) -> URL? {
        HiddenMissAVHTMLParser.normalizedExternalURL(from: raw, relativeTo: baseURL)
    }

    private static func normalizePreviewURL(from coverURL: URL) -> URL? {
        let absoluteString = coverURL.absoluteString.replacingOccurrences(
            of: #"/cover(?:-(?:n|t))?\.[^/?#]+"#,
            with: "/preview.mp4",
            options: .regularExpression
        )
        return URL(string: absoluteString)
    }

    private static func stripLeadingCode(_ title: String, code: String) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let uppercaseTitle = trimmedTitle.uppercased()
        let variants = [
            code.uppercased(),
            code.uppercased().replacingOccurrences(of: "_", with: "-"),
            code.uppercased().replacingOccurrences(of: "-", with: "_"),
            code.uppercased().replacingOccurrences(of: "-", with: ""),
            code.uppercased().replacingOccurrences(of: "_", with: ""),
            code.uppercased().replacingOccurrences(of: "-", with: " ")
        ].sorted { $0.count > $1.count }

        for variant in variants where uppercaseTitle.hasPrefix(variant) {
            let index = trimmedTitle.index(trimmedTitle.startIndex, offsetBy: variant.count)
            let remainder = trimmedTitle[index...]
                .trimmingCharacters(in: CharacterSet(charactersIn: " -:|/·").union(.whitespacesAndNewlines))
            if let nonEmpty = String(remainder).nonEmpty {
                return nonEmpty
            }
        }

        return trimmedTitle
    }

    private static func firstNonEmpty(_ values: [String?]) -> String? {
        for value in values {
            if let nonEmpty = value?.nonEmpty {
                return nonEmpty
            }
        }
        return nil
    }

    private static func dedupedMovies(_ movies: [HiddenMissAVMovie], limit: Int) -> [HiddenMissAVMovie] {
        var deduped: [HiddenMissAVMovie] = []
        var seen = Set<String>()

        for movie in movies where seen.insert(movie.id).inserted {
            deduped.append(movie)
            if deduped.count >= limit {
                break
            }
        }

        return deduped
    }
}

struct HiddenMissAVFeatureView: View {
    @ObservedObject var viewModel: HiddenMissAVViewModel
    @State private var searchQuery = ""
    @State private var activePreviewMovieID: String?
    @State private var selectedMovie: HiddenMissAVMovie?

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                quickActions
                searchPanel
                content
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("MissAV")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.reloadLocalCollections()
            await viewModel.loadHomeIfNeeded(force: false)
        }
        .navigationDestination(isPresented: selectedMoviePresentedBinding) {
            if let selectedMovie {
                HiddenMissAVMovieDetailView(movie: selectedMovie, viewModel: viewModel)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .hiddenSpaceSettingsDidChange)) { _ in
            Task {
                activePreviewMovieID = nil
                await viewModel.refreshForSettingsChange()
            }
        }
    }

    private var quickActions: some View {
        NavigationLink(value: HiddenSpaceRoute.missAVFavorites) {
            HiddenMissAVQuickActionCard(
                title: "收藏",
                subtitle: "\(viewModel.favoriteMovies.count) 部",
                systemImage: "heart.fill"
            )
        }
        .buttonStyle(.plain)
    }

    private var searchPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("搜索")
                .font(.headline)

            HStack(spacing: 8) {
                TextField("输入番号或关键词，例如 ADN-773", text: $searchQuery)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .submitLabel(.search)
                    .onSubmit {
                        performSearch()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.tertiarySystemFill))
                    )

                Button("搜索") {
                    performSearch()
                }
                .buttonStyle(.borderedProminent)

                if viewModel.lastSearchQuery != nil {
                    Button("清除") {
                        searchQuery = ""
                        viewModel.clearSearch()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isSearching {
            HiddenMissAVCenteredStatusView(title: "正在搜索...", systemImage: nil)
        } else if let lastSearchQuery = viewModel.lastSearchQuery {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("搜索结果")
                        .font(.headline)
                    Spacer()
                    Text(lastSearchQuery)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let searchErrorMessage = viewModel.searchErrorMessage, viewModel.searchResults.isEmpty {
                    HiddenMissAVErrorCard(message: searchErrorMessage) {
                        performSearch()
                    }
                } else if viewModel.searchResults.isEmpty {
                    HiddenMissAVCenteredStatusView(title: "没有搜索到结果", systemImage: "magnifyingglass")
                } else {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(viewModel.searchResults) { movie in
                            HiddenMissAVInteractiveMovieTile(
                                movie: movie,
                                activePreviewMovieID: $activePreviewMovieID,
                                onOpenMovie: { selectedMovie = $0 }
                            )
                        }
                    }
                }
            }
        } else if viewModel.isLoadingHome && viewModel.homeSections.isEmpty {
            HiddenMissAVCenteredStatusView(title: "正在加载首页...", systemImage: nil)
        } else if let homeErrorMessage = viewModel.homeErrorMessage, viewModel.homeSections.isEmpty {
            HiddenMissAVErrorCard(message: homeErrorMessage) {
                Task {
                    await viewModel.loadHomeIfNeeded(force: true)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(viewModel.homeSections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(section.title)
                                .font(.headline)
                            Spacer()
                            if let moreURL = section.moreURL {
                                NavigationLink(value: HiddenSpaceRoute.missAVSection(title: section.title, url: moreURL)) {
                                    Label("更多", systemImage: "chevron.right")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(section.movies) { movie in
                                HiddenMissAVInteractiveMovieTile(
                                    movie: movie,
                                    activePreviewMovieID: $activePreviewMovieID,
                                    onOpenMovie: { selectedMovie = $0 }
                                )
                            }
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                }
            }
        }
    }

    private func performSearch() {
        Task {
            await viewModel.searchMovies(query: searchQuery)
        }
    }

    private var selectedMoviePresentedBinding: Binding<Bool> {
        Binding(
            get: { selectedMovie != nil },
            set: { isPresented in
                if !isPresented {
                    selectedMovie = nil
                }
            }
        )
    }
}

struct HiddenMissAVSectionPageView: View {
    let title: String
    let url: URL
    @ObservedObject var viewModel: HiddenMissAVViewModel

    @State private var movies: [HiddenMissAVMovie] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var loadMoreErrorMessage: String?
    @State private var nextPageURL: URL?
    @State private var loadedPageURLs: Set<String> = []
    @State private var activePreviewMovieID: String?
    @State private var selectedMovie: HiddenMissAVMovie?

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ScrollView {
            Group {
                if isLoading && movies.isEmpty {
                    HiddenMissAVCenteredStatusView(title: "正在加载...", systemImage: nil)
                        .frame(maxWidth: .infinity, minHeight: 260)
                } else if let errorMessage, movies.isEmpty {
                    HiddenMissAVErrorCard(message: errorMessage) {
                        Task {
                            await loadMovies(force: true)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                } else if movies.isEmpty {
                    HiddenMissAVCenteredStatusView(title: "这里还没有内容", systemImage: "square.grid.2x2")
                        .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    VStack(spacing: 0) {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(movies) { movie in
                                HiddenMissAVInteractiveMovieTile(
                                    movie: movie,
                                    activePreviewMovieID: $activePreviewMovieID,
                                    onOpenMovie: { selectedMovie = $0 }
                                )
                            }
                        }

                        loadMoreFooter
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadMovies(force: false)
        }
        .navigationDestination(isPresented: selectedMoviePresentedBinding) {
            if let selectedMovie {
                HiddenMissAVMovieDetailView(movie: selectedMovie, viewModel: viewModel)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .hiddenSpaceSettingsDidChange)) { _ in
            Task {
                activePreviewMovieID = nil
                await loadMovies(force: true)
            }
        }
    }

    private func loadMovies(force: Bool) async {
        if isLoading {
            return
        }
        if !force, !movies.isEmpty {
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let page = try await HiddenMissAVAPI.fetchMoviePage(from: url, limit: 120)
            movies = page.movies
            loadMoreErrorMessage = nil
            loadedPageURLs = [pageStorageKey(for: url)]
            nextPageURL = unresolvedNextPageURL(from: page.nextPageURL)
        } catch {
            if movies.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private var loadMoreFooter: some View {
        if let loadMoreErrorMessage {
            HiddenMissAVErrorCard(message: loadMoreErrorMessage) {
                Task {
                    await loadMoreIfNeeded(forceRetry: true)
                }
            }
            .padding(.top, 12)
        } else if isLoadingMore {
            HStack {
                Spacer()
                ProgressView("正在加载更多...")
                Spacer()
            }
            .padding(.top, 16)
        } else if nextPageURL != nil {
            HStack {
                Spacer()
                ProgressView("加载更多...")
                Spacer()
            }
            .padding(.top, 16)
            .onAppear {
                Task {
                    await loadMoreIfNeeded()
                }
            }
        }
    }

    private func loadMoreIfNeeded(forceRetry: Bool = false) async {
        guard !isLoading, !isLoadingMore else { return }
        guard let nextPageURL else { return }
        guard forceRetry || loadMoreErrorMessage == nil else { return }

        let pageKey = pageStorageKey(for: nextPageURL)
        guard !loadedPageURLs.contains(pageKey) else {
            self.nextPageURL = nil
            return
        }

        isLoadingMore = true
        loadMoreErrorMessage = nil
        defer { isLoadingMore = false }

        do {
            let page = try await HiddenMissAVAPI.fetchMoviePage(from: nextPageURL, limit: 120)
            loadedPageURLs.insert(pageKey)
            appendMovies(page.movies)
            self.nextPageURL = unresolvedNextPageURL(from: page.nextPageURL)
        } catch {
            loadMoreErrorMessage = error.localizedDescription
        }
    }

    private func appendMovies(_ newMovies: [HiddenMissAVMovie]) {
        guard !newMovies.isEmpty else { return }

        var seen = Set(movies.map(\.id))
        for movie in newMovies where seen.insert(movie.id).inserted {
            movies.append(movie)
        }
    }

    private func unresolvedNextPageURL(from candidate: URL?) -> URL? {
        guard let candidate else { return nil }
        return loadedPageURLs.contains(pageStorageKey(for: candidate)) ? nil : candidate
    }

    private func pageStorageKey(for url: URL) -> String {
        url.absoluteString
    }

    private var selectedMoviePresentedBinding: Binding<Bool> {
        Binding(
            get: { selectedMovie != nil },
            set: { isPresented in
                if !isPresented {
                    selectedMovie = nil
                }
            }
        )
    }
}

struct HiddenMissAVFavoritesView: View {
    @ObservedObject var viewModel: HiddenMissAVViewModel
    @State private var activePreviewMovieID: String?
    @State private var selectedMovie: HiddenMissAVMovie?

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ScrollView {
            if viewModel.favoriteMovies.isEmpty {
                HiddenMissAVCenteredStatusView(title: "还没有收藏影片", systemImage: "heart")
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(viewModel.favoriteMovies) { movie in
                        HiddenMissAVInteractiveMovieTile(
                            movie: movie,
                            activePreviewMovieID: $activePreviewMovieID,
                            onOpenMovie: { selectedMovie = $0 }
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("MissAV 收藏")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.reloadLocalCollections()
        }
        .navigationDestination(isPresented: selectedMoviePresentedBinding) {
            if let selectedMovie {
                HiddenMissAVMovieDetailView(movie: selectedMovie, viewModel: viewModel)
            }
        }
    }

    private var selectedMoviePresentedBinding: Binding<Bool> {
        Binding(
            get: { selectedMovie != nil },
            set: { isPresented in
                if !isPresented {
                    selectedMovie = nil
                }
            }
        )
    }
}

struct HiddenMissAVMovieDetailView: View {
    let movie: HiddenMissAVMovie
    @ObservedObject var viewModel: HiddenMissAVViewModel

    @State private var isResolvingPlayback = false
    @State private var playbackErrorMessage: String?
    @State private var playerItem: HiddenSharedPlayerItem?
    @State private var domainDisplay = HiddenMissAVDomainConfiguration.currentHost()
    @State private var activePreviewMovieID: String?
    @State private var selectedMovie: HiddenMissAVMovie?

    private let relatedColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    private var detail: HiddenMissAVMovieDetail? {
        viewModel.detailsByMovieID[movie.id]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HiddenMissAVCoverImage(url: detail?.screenshots.first ?? movie.coverURL)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                playbackSection
                summarySection
                screenshotsSection
                relatedSection
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(movie.displayCode)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.toggleFavorite(movie)
                } label: {
                    Image(systemName: viewModel.isFavorite(movie) ? "heart.fill" : "heart")
                        .foregroundStyle(viewModel.isFavorite(movie) ? .pink : .primary)
                }
            }
        }
        .task {
            viewModel.reloadLocalCollections()
            await viewModel.loadDetailIfNeeded(for: movie)
        }
        .navigationDestination(isPresented: selectedMoviePresentedBinding) {
            if let selectedMovie {
                HiddenMissAVMovieDetailView(movie: selectedMovie, viewModel: viewModel)
            }
        }
        .fullScreenCover(item: playerItemBinding) { item in
            HiddenSharedVideoPlayerView(
                item: item,
                onSavePlaybackPosition: { item, position in
                    viewModel.savePlayback(movie: movie, item: item, position: position)
                },
                onPlaybackClosed: nil
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .hiddenSpaceSettingsDidChange)) { _ in
            domainDisplay = HiddenMissAVDomainConfiguration.currentHost()
        }
    }

    private var playbackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("播放")
                .font(.headline)

            Button {
                Task {
                    await playMovie()
                }
            } label: {
                HStack(spacing: 12) {
                    Group {
                        if isResolvingPlayback {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .frame(width: 18, height: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(isResolvingPlayback ? "载入中..." : "直接播放")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(domainDisplay)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    if let savedPosition = resumePositionText {
                        Text(savedPosition)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                )
            }
            .buttonStyle(.plain)
            .disabled(isResolvingPlayback)

            if let playbackErrorMessage {
                Text(playbackErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.detailLoadingIDs.contains(movie.id) {
                HiddenMissAVCenteredStatusView(title: "正在加载详情...", systemImage: nil)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if let detail {
                HiddenMissAVInfoRow(title: "标题", value: detail.movie.displayTitle)
                HiddenMissAVInfoRow(title: "番号", value: detail.movie.displayCode)
                HiddenMissAVInfoRow(title: "发行日期", value: detail.releaseDate ?? "未知")
                HiddenMissAVInfoRow(title: "女优", value: detail.actressesText)
                if !detail.actors.isEmpty {
                    HiddenMissAVInfoRow(title: "男优", value: detail.actorsText)
                }
                HiddenMissAVInfoRow(title: "类型", value: detail.tagsText)
                HiddenMissAVInfoRow(title: "发行商", value: detail.studio ?? "未知")
                if let director = detail.director?.nonEmpty {
                    HiddenMissAVInfoRow(title: "导演", value: director)
                }
                if let label = detail.label?.nonEmpty {
                    HiddenMissAVInfoRow(title: "标籤", value: label)
                }
            } else if let errorMessage = viewModel.detailErrorsByMovieID[movie.id] {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                HiddenMissAVInfoRow(title: "标题", value: movie.displayTitle)
                HiddenMissAVInfoRow(title: "番号", value: movie.displayCode)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    @ViewBuilder
    private var screenshotsSection: some View {
        if let detail, !detail.screenshots.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("截图")
                    .font(.headline)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(detail.screenshots, id: \.absoluteString) { imageURL in
                            HiddenMissAVCoverImage(url: imageURL)
                                .frame(width: 220, height: 124)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
        }
    }

    @ViewBuilder
    private var relatedSection: some View {
        if let detail, !detail.relatedMovies.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("相关影片")
                        .font(.headline)
                    Spacer()
                    Text("\(detail.relatedMovies.count) 部")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: relatedColumns, spacing: 10) {
                    ForEach(detail.relatedMovies) { relatedMovie in
                        HiddenMissAVInteractiveMovieTile(
                            movie: relatedMovie,
                            activePreviewMovieID: $activePreviewMovieID,
                            onOpenMovie: { selectedMovie = $0 }
                        )
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
        }
    }

    private var resumePositionText: String? {
        let seconds = viewModel.resumePosition(for: movie)
        guard seconds > 0.5 else { return nil }
        return "续播 \(HiddenMissAVTimeFormatter.string(from: seconds))"
    }

    private func playMovie() async {
        guard !isResolvingPlayback else { return }

        isResolvingPlayback = true
        playbackErrorMessage = nil
        defer { isResolvingPlayback = false }

        do {
            let pageURL = HiddenMissAVDomainConfiguration.currentMovieURL(forCode: movie.code) ?? movie.url
            let target = try await HiddenMissAVPlaybackResolver.resolvePlaybackTarget(pageURL: pageURL)
            switch target {
            case let .stream(streamURL, refererURL):
                playerItem = HiddenSharedPlayerItem(
                    resourceID: movie.id,
                    title: movie.displayTitle,
                    code: movie.displayCode,
                    coverURL: movie.coverURL,
                    sourceName: "MISSAV",
                    streamURL: streamURL,
                    refererURL: refererURL,
                    startPositionSeconds: viewModel.resumePosition(for: movie),
                    markerPositions: viewModel.markerPositions(for: movie)
                )
            }
        } catch {
            playbackErrorMessage = error.localizedDescription
        }
    }

    private var playerItemBinding: Binding<HiddenSharedPlayerItem?> {
        Binding(
            get: { playerItem },
            set: { playerItem = $0 }
        )
    }

    private var selectedMoviePresentedBinding: Binding<Bool> {
        Binding(
            get: { selectedMovie != nil },
            set: { isPresented in
                if !isPresented {
                    selectedMovie = nil
                }
            }
        )
    }
}

private enum HiddenMissAVTimeFormatter {
    static func string(from seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "00:00" }
        let totalSeconds = Int(seconds.rounded(.down))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }
}

private struct HiddenMissAVInteractiveMovieTile: View {
    let movie: HiddenMissAVMovie
    @Binding var activePreviewMovieID: String?
    let onOpenMovie: (HiddenMissAVMovie) -> Void

    private var isPreviewing: Bool {
        activePreviewMovieID == movie.id
    }

    var body: some View {
        HiddenMissAVMovieTile(
            movie: movie,
            isPreviewing: isPreviewing,
            onPreviewTap: handleTap,
            onOpenMovie: openMovie
        )
    }

    private func handleTap() {
        guard movie.previewVideoURL != nil else {
            openMovie()
            return
        }

        if isPreviewing {
            openMovie()
        } else {
            activePreviewMovieID = movie.id
        }
    }

    private func openMovie() {
        activePreviewMovieID = nil
        onOpenMovie(movie)
    }
}

private struct HiddenMissAVMovieTile: View {
    let movie: HiddenMissAVMovie
    var isPreviewing = false
    let onPreviewTap: () -> Void
    let onOpenMovie: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                onPreviewTap()
            } label: {
                ZStack(alignment: .bottomLeading) {
                    Group {
                        if isPreviewing, let previewVideoURL = movie.previewVideoURL {
                            HiddenMissAVInlinePreviewView(url: previewVideoURL)
                        } else {
                            HiddenMissAVCoverImage(url: movie.coverURL)
                        }
                    }
                    .frame(height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    HStack(spacing: 6) {
                        if movie.hasChineseSubtitle {
                            HiddenMissAVFlag(text: "中字", color: .red)
                        } else if movie.hasEnglishSubtitle {
                            HiddenMissAVFlag(text: "英字", color: .red)
                        } else if movie.isUncensored {
                            HiddenMissAVFlag(text: "无码", color: .blue)
                        }
                    }
                    .padding(8)

                    VStack(alignment: .trailing, spacing: 4) {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(isPreviewing ? "再次点击进入详情" : "点击封面预览")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.black.opacity(0.55), in: Capsule())
                        }
                        .padding(8)
                    }
                }
            }
            .buttonStyle(.plain)

            Button {
                onOpenMovie()
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(movie.displayCode)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(movie.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)

            if let durationText = movie.durationText?.nonEmpty {
                Text(durationText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

private struct HiddenMissAVHistoryRow: View {
    let item: HiddenMissAVWatchHistoryItem

    var body: some View {
        HStack(spacing: 12) {
            HiddenMissAVCoverImage(url: item.movie.coverURL)
                .frame(width: 112, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.movie.displayCode)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(item.movie.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text("上次播放到 \(HiddenMissAVTimeFormatter.string(from: item.positionSeconds))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(item.updatedAt.formatted(date: .numeric, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct HiddenMissAVQuickActionCard: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 42, height: 42)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

private struct HiddenMissAVInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct HiddenMissAVFlag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.88), in: Capsule())
    }
}

private struct HiddenMissAVInlinePreviewView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> HiddenMissAVInlinePlayerContainerView {
        let view = HiddenMissAVInlinePlayerContainerView()
        view.playerLayer.videoGravity = .resizeAspectFill
        context.coordinator.attach(to: view, url: url)
        return view
    }

    func updateUIView(_ uiView: HiddenMissAVInlinePlayerContainerView, context: Context) {
        context.coordinator.attach(to: uiView, url: url)
    }

    static func dismantleUIView(_ uiView: HiddenMissAVInlinePlayerContainerView, coordinator: Coordinator) {
        coordinator.stop()
        uiView.playerLayer.player = nil
    }

    final class Coordinator {
        private var currentURL: URL?
        private var queuePlayer: AVQueuePlayer?
        private var looper: AVPlayerLooper?

        func attach(to view: HiddenMissAVInlinePlayerContainerView, url: URL) {
            guard currentURL != url || queuePlayer == nil else {
                queuePlayer?.play()
                return
            }

            stop()

            let playerItem = AVPlayerItem(url: url)
            let player = AVQueuePlayer()
            player.isMuted = true
            player.actionAtItemEnd = .none
            player.automaticallyWaitsToMinimizeStalling = true
            looper = AVPlayerLooper(player: player, templateItem: playerItem)
            player.play()

            view.playerLayer.player = player
            queuePlayer = player
            currentURL = url
        }

        func stop() {
            queuePlayer?.pause()
            queuePlayer?.removeAllItems()
            looper = nil
            queuePlayer = nil
            currentURL = nil
        }
    }
}

private final class HiddenMissAVInlinePlayerContainerView: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}

private struct HiddenMissAVCoverImage: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            case .empty:
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                    ProgressView()
                }
            case .failure:
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                    Image(systemName: "photo")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            @unknown default:
                EmptyView()
            }
        }
    }
}

private struct HiddenMissAVCenteredStatusView: View {
    let title: String
    let systemImage: String?

    var body: some View {
        VStack(spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct HiddenMissAVErrorCard: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("重试", action: retry)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}
