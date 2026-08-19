import Foundation
import Combine

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

    var totalFavoritesCount: Int { favoriteAlbums.count + favoriteImageURLs.count }

    private static let randomAlbumCount = 9

    init() {
        loadFavoriteAlbums()
        loadFavoriteImages()
    }

    /// Relies on app-wide `CloudSyncViewModel` as the single full-sync owner.
    func prepareCloudIfNeeded() async {
        await CloudSyncViewModel.shared.prepareIfNeeded()
        // Global sync may have rewritten local stores — reload into this VM.
        loadFavoriteAlbums()
        loadFavoriteImages()
    }

    func loadRandomAlbumIfNeeded() async {
        guard randomAlbums.isEmpty else { return }
        await loadRandomAlbums()
    }

    func loadRandomAlbums() async {
        guard !isLoadingRandomAlbum else { return }

        isLoadingRandomAlbum = true
        randomErrorMessage = nil

        defer {
            isLoadingRandomAlbum = false
        }

        do {
            randomAlbums = try await fetchRandomAlbums(count: Self.randomAlbumCount)
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

        Task {
            await CloudSyncViewModel.shared.sync4KHDAlbumIfPossible(
                album,
                shouldRemove: shouldRemove
            )
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

        Task {
            await CloudSyncViewModel.shared.sync4KHDImageIfPossible(
                normalized,
                shouldRemove: shouldRemove
            )
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

}
