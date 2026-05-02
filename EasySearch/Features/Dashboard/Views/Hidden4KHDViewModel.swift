import Foundation
import Combine

enum HiddenRandomMode: String, CaseIterable, Identifiable {
    case single
    case nine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .single:
            return "随机 1 张"
        case .nine:
            return "随机 9 张"
        }
    }

    var requestCount: Int {
        switch self {
        case .single:
            return 1
        case .nine:
            return 9
        }
    }

    var loadingText: String {
        switch self {
        case .single:
            return "正在抓取随机封面..."
        case .nine:
            return "正在抓取随机 9 张..."
        }
    }
}

struct HiddenFavoriteImageSelection {
    let selected: URL
    let previewPool: [URL]
    let sourceLabel: String
}

private enum HiddenFavoriteImageSource {
    case directImage(URL)
    case album(HiddenAlbum)
}

@MainActor
final class HiddenSpaceViewModel: ObservableObject {
    @Published var randomAlbums: [HiddenAlbum] = []
    @Published var isLoadingRandomAlbum = false
    @Published var randomErrorMessage: String?
    @Published var searchedAlbums: [HiddenAlbum] = []
    @Published var isSearchingAlbums = false
    @Published var searchAlbumErrorMessage: String?
    @Published var lastSearchedAlbumQuery: String?
    @Published var favoriteAlbums: [HiddenAlbum] = []
    @Published var favoriteImageURLs: [URL] = []

    private var cachedTotalPages: Int?
    private var favoriteAlbumImageCache: [String: [URL]] = [:]
    private var didPrepareCloud = false
    private var isPreparingCloud = false
    private var isCloudAuthenticated = false
    private let cloudService = HiddenSupabaseService.shared

    var randomAlbum: HiddenAlbum? { randomAlbums.first }
    var totalFavoritesCount: Int { favoriteAlbums.count + favoriteImageURLs.count }

    init() {
        loadFavoriteAlbums()
        loadFavoriteImages()
    }

    func prepareCloudIfNeeded() async {
        guard !didPrepareCloud, !isPreparingCloud else { return }
        didPrepareCloud = true
        isPreparingCloud = true
        defer { isPreparingCloud = false }

        do {
            guard try await cloudService.restoreSessionIfPossible() != nil else {
                isCloudAuthenticated = false
                return
            }

            isCloudAuthenticated = true

            let remoteAlbums = try await cloudService.fetch4KHDAlbums()
            let remoteImages = try await cloudService.fetch4KHDImages()

            favoriteAlbums = HiddenCloudMerge.albums(primary: remoteAlbums, secondary: favoriteAlbums)
            favoriteImageURLs = HiddenCloudMerge.imageURLs(primary: remoteImages, secondary: favoriteImageURLs)
            saveFavorites()
            saveFavoriteImages()

            try await cloudService.upsert4KHDAlbums(favoriteAlbums)
            try await cloudService.upsert4KHDImages(favoriteImageURLs)
        } catch {
            if error.isHiddenSupabaseAuthFailure {
                isCloudAuthenticated = false
            }
            didPrepareCloud = false
        }
    }

    func loadRandomAlbumIfNeeded(mode: HiddenRandomMode) async {
        guard randomAlbums.isEmpty else { return }
        await loadRandomAlbums(mode: mode)
    }

    func loadRandomAlbums(mode: HiddenRandomMode) async {
        guard !isLoadingRandomAlbum else { return }

        isLoadingRandomAlbum = true
        randomErrorMessage = nil

        defer {
            isLoadingRandomAlbum = false
        }

        do {
            randomAlbums = try await fetchRandomAlbums(count: mode.requestCount)
        } catch {
            randomErrorMessage = error.localizedDescription
        }
    }

    func searchAlbums(query: String) async {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            resetSearchAlbums()
            return
        }

        guard !isSearchingAlbums else { return }

        isSearchingAlbums = true
        searchAlbumErrorMessage = nil
        lastSearchedAlbumQuery = normalizedQuery

        defer {
            isSearchingAlbums = false
        }

        do {
            searchedAlbums = try await HiddenSpaceAPI.searchAlbums(query: normalizedQuery)
        } catch {
            searchedAlbums = []
            searchAlbumErrorMessage = error.localizedDescription
        }
    }

    func resetSearchAlbums() {
        searchedAlbums = []
        searchAlbumErrorMessage = nil
        lastSearchedAlbumQuery = nil
    }

    func toggleFavorite(_ album: HiddenAlbum) {
        let shouldRemove = favoriteAlbums.contains(where: { $0.id == album.id })
        if let index = favoriteAlbums.firstIndex(where: { $0.id == album.id }) {
            favoriteAlbums.remove(at: index)
            favoriteAlbumImageCache[album.id] = nil
        } else {
            favoriteAlbums.insert(album, at: 0)
        }
        saveFavorites()

        guard isCloudAuthenticated else { return }
        Task {
            do {
                if shouldRemove {
                    try await cloudService.delete4KHDAlbum(albumID: album.id)
                } else {
                    try await cloudService.upsert4KHDAlbum(album)
                }
            } catch {
                handleCloudMutationError(error)
            }
        }
    }

    func isFavorite(_ album: HiddenAlbum) -> Bool {
        favoriteAlbums.contains(where: { $0.id == album.id })
    }

    func toggleFavoriteImage(_ imageURL: URL) {
        let normalized = HiddenSpaceAPI.normalizeImageURL(imageURL)
        let target = normalized.absoluteString
        let shouldRemove = favoriteImageURLs.contains(where: { $0.absoluteString == target })

        if let index = favoriteImageURLs.firstIndex(where: { $0.absoluteString == target }) {
            favoriteImageURLs.remove(at: index)
        } else {
            favoriteImageURLs.insert(normalized, at: 0)
        }
        saveFavoriteImages()

        guard isCloudAuthenticated else { return }
        Task {
            do {
                if shouldRemove {
                    try await cloudService.delete4KHDImage(imageID: target)
                } else {
                    try await cloudService.upsert4KHDImage(normalized)
                }
            } catch {
                handleCloudMutationError(error)
            }
        }
    }

    func isFavoriteImage(_ imageURL: URL) -> Bool {
        let target = HiddenSpaceAPI.normalizeImageURL(imageURL).absoluteString
        return favoriteImageURLs.contains(where: { $0.absoluteString == target })
    }

    func fetchRandomFavoriteImageSelection() async throws -> HiddenFavoriteImageSelection {
        let directImages = deduplicatedImageURLs(favoriteImageURLs)
        var candidates: [HiddenFavoriteImageSource] = directImages.map(HiddenFavoriteImageSource.directImage)
        candidates.append(contentsOf: favoriteAlbums.map(HiddenFavoriteImageSource.album))

        guard !candidates.isEmpty else {
            throw emptyFavoriteImageError()
        }

        for source in candidates.shuffled() {
            switch source {
            case let .directImage(imageURL):
                return HiddenFavoriteImageSelection(
                    selected: imageURL,
                    previewPool: directImages,
                    sourceLabel: "来自喜欢的图片"
                )
            case let .album(album):
                do {
                    let albumImages = try await favoriteImages(for: album)
                    guard let selected = albumImages.randomElement() else { continue }
                    return HiddenFavoriteImageSelection(
                        selected: selected,
                        previewPool: albumImages,
                        sourceLabel: "来自 album：\(album.title)"
                    )
                } catch {
                    continue
                }
            }
        }

        throw emptyFavoriteImageError()
    }

    func prefetchImages(_ imageURLs: [URL]) {
        HiddenImagePipeline.shared.prefetch(imageURLs)
    }

    private func fetchRandomAlbums(count: Int) async throws -> [HiddenAlbum] {
        var albums: [HiddenAlbum] = []
        var seen = Set<String>()
        var attempts = 0
        let maxAttempts = max(18, count * 12)

        while albums.count < count && attempts < maxAttempts {
            attempts += 1
            let result = try await HiddenSpaceAPI.fetchRandomAlbum(knownTotalPages: cachedTotalPages)
            cachedTotalPages = result.totalPages

            let album = result.album
            if seen.insert(album.id).inserted {
                albums.append(album)
            }
        }

        guard !albums.isEmpty else {
            throw NSError(domain: "HiddenSpaceViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "没有拿到可用封面"])
        }

        return albums
    }

    private func loadFavoriteAlbums() {
        favoriteAlbums = Hidden4KHDLocalStore.loadFavoriteAlbums()
        let activeIDs = Set(favoriteAlbums.map(\.id))
        favoriteAlbumImageCache = favoriteAlbumImageCache.filter { activeIDs.contains($0.key) }
    }

    private func saveFavorites() {
        Hidden4KHDLocalStore.saveFavoriteAlbums(favoriteAlbums)
    }

    private func loadFavoriteImages() {
        favoriteImageURLs = Hidden4KHDLocalStore.loadFavoriteImages()
    }

    private func saveFavoriteImages() {
        Hidden4KHDLocalStore.saveFavoriteImages(favoriteImageURLs)
    }

    private func favoriteImages(for album: HiddenAlbum) async throws -> [URL] {
        if let cached = favoriteAlbumImageCache[album.id] {
            return cached
        }

        do {
            let fetched = try await HiddenSpaceAPI.fetchAlbumImageURLs(albumURL: album.url)
                .map(HiddenSpaceAPI.normalizeImageURL)
            let deduplicated = deduplicatedImageURLs(fetched)
            favoriteAlbumImageCache[album.id] = deduplicated
            return deduplicated
        } catch {
            favoriteAlbumImageCache[album.id] = []
            throw error
        }
    }

    private func deduplicatedImageURLs(_ imageURLs: [URL]) -> [URL] {
        var deduped: [URL] = []
        var seen = Set<String>()
        for imageURL in imageURLs {
            let normalized = HiddenSpaceAPI.normalizeImageURL(imageURL)
            if seen.insert(normalized.absoluteString).inserted {
                deduped.append(normalized)
            }
        }
        return deduped
    }

    private func emptyFavoriteImageError() -> NSError {
        NSError(
            domain: "HiddenSpaceViewModel",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: "喜欢列表里还没有可用图片"]
        )
    }

    private func handleCloudMutationError(_ error: Error) {
        if error.isHiddenSupabaseAuthFailure {
            isCloudAuthenticated = false
            didPrepareCloud = false
        }
    }
}
