import SwiftUI
import WebKit
import AVKit
@preconcurrency import AVFoundation
import UIKit

struct Hidden4KHDFeatureView: View {
    @ObservedObject var viewModel: HiddenSpaceViewModel
    @State private var randomMode: HiddenRandomMode
    @State private var searchQuery = ""

    private let randomNineColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    init(viewModel: HiddenSpaceViewModel) {
        self.viewModel = viewModel
        _randomMode = State(initialValue: HiddenSpaceSettingsStore.shared.load().fourKHDRandomMode)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                searchAlbumCard
                randomAlbumCard

                NavigationLink(value: HiddenSpaceRoute.fourKHDFavorites) {
                    HStack {
                        Label("喜欢列表", systemImage: "heart.text.square")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(viewModel.totalFavoritesCount)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .padding(.bottom, 18)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("4khd")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.prepareCloudIfNeeded()
            await viewModel.loadRandomAlbumIfNeeded(mode: randomMode)
        }
        .onChange(of: randomMode) { mode in
            Task {
                await viewModel.loadRandomAlbums(mode: mode)
            }
        }
        .onChange(of: searchQuery) { newValue in
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                viewModel.resetSearchAlbums()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .hiddenSpaceSettingsDidChange)) { _ in
            randomMode = HiddenSpaceSettingsStore.shared.load().fourKHDRandomMode
        }
    }

    @ViewBuilder
    private var searchAlbumCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("搜索 album")
                .font(.headline)

            HStack(spacing: 10) {
                TextField("输入标题关键词", text: $searchQuery)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .submitLabel(.search)
                    .onSubmit {
                        performAlbumSearch()
                    }

                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                        viewModel.resetSearchAlbums()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }

                Button("搜索") {
                    performAlbumSearch()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isSearchingAlbums || normalizedSearchQuery.isEmpty)
            }

            if viewModel.isSearchingAlbums {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("正在搜索...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if let searchErrorMessage = viewModel.searchAlbumErrorMessage {
                Text(searchErrorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let lastQuery = viewModel.lastSearchedAlbumQuery, !viewModel.searchedAlbums.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("“\(lastQuery)” · \(viewModel.searchedAlbums.count) 个结果")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: favoriteAlbumColumns, spacing: 10) {
                        ForEach(viewModel.searchedAlbums) { album in
                            NavigationLink(value: HiddenSpaceRoute.fourKHDAlbum(album)) {
                                FavoriteAlbumTile(album: album)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else if let lastQuery = viewModel.lastSearchedAlbumQuery {
                Text("“\(lastQuery)” 没有搜索到内容")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    @ViewBuilder
    private var randomAlbumCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("功能 1 · 随机封面")
                    .font(.headline)
                Spacer()
                if viewModel.isLoadingRandomAlbum {
                    ProgressView()
                }
            }

            Picker("随机模式", selection: $randomMode) {
                ForEach(HiddenRandomMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if viewModel.isLoadingRandomAlbum {
                VStack(spacing: 10) {
                    ProgressView()
                    Text(randomMode.loadingText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else if !viewModel.randomAlbums.isEmpty {
                if randomMode == .single, let album = viewModel.randomAlbum {
                    NavigationLink(value: HiddenSpaceRoute.fourKHDAlbum(album)) {
                        VStack(alignment: .leading, spacing: 10) {
                            AsyncCoverImage(url: album.coverURL, fitToContainer: true)
                                .frame(height: 230)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                            Text(album.title)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                        }
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 12) {
                        Button {
                            Task {
                                await viewModel.loadRandomAlbums(mode: randomMode)
                            }
                        } label: {
                            Label("随机 1 张", systemImage: "shuffle")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isLoadingRandomAlbum)

                        Button {
                            viewModel.toggleFavorite(album)
                        } label: {
                            Label(viewModel.isFavorite(album) ? "已喜欢" : "喜欢", systemImage: viewModel.isFavorite(album) ? "heart.fill" : "heart")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(viewModel.isFavorite(album) ? .pink : .primary)
                    }
                } else {
                    LazyVGrid(columns: randomNineColumns, spacing: 8) {
                        ForEach(Array(viewModel.randomAlbums.prefix(9))) { album in
                            NavigationLink(value: HiddenSpaceRoute.fourKHDAlbum(album)) {
                                RandomNineAlbumTile(
                                    album: album,
                                    isFavorite: viewModel.isFavorite(album)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button {
                        Task {
                            await viewModel.loadRandomAlbums(mode: randomMode)
                        }
                    } label: {
                        Label("随机 9 张", systemImage: "shuffle")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isLoadingRandomAlbum)
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(viewModel.randomErrorMessage ?? "暂时没有拿到封面")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("重试") {
                        Task {
                            await viewModel.loadRandomAlbums(mode: randomMode)
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var normalizedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var favoriteAlbumColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
    }

    private func performAlbumSearch() {
        let query = normalizedSearchQuery
        guard !query.isEmpty else {
            viewModel.resetSearchAlbums()
            return
        }

        Task {
            await viewModel.searchAlbums(query: query)
        }
    }
}

struct Hidden4KHDFavoritesView: View {
    @ObservedObject var viewModel: HiddenSpaceViewModel
    @ObservedObject var presentationState: HiddenSpacePresentationState
    @State private var randomFavoriteImageURL: URL?
    @State private var randomFavoritePreviewPool: [URL] = []
    @State private var randomFavoriteSourceLabel: String?
    @State private var isLoadingRandomFavorite = false
    @State private var randomFavoriteError: String?

    var body: some View {
        ScrollView {
            if viewModel.totalFavoritesCount == 0 {
                VStack(spacing: 10) {
                    Image(systemName: "heart")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("还没有喜欢的内容")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    randomFavoriteCard
                    favoriteCollectionsSection
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("喜欢列表")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: viewModel.totalFavoritesCount) {
            guard viewModel.totalFavoritesCount > 0 else {
                randomFavoriteImageURL = nil
                randomFavoritePreviewPool = []
                randomFavoriteSourceLabel = nil
                randomFavoriteError = nil
                return
            }
            await loadRandomFavorite(force: true)
        }
        .fullScreenCover(item: previewImageBinding) { preview in
            HiddenImagePreviewView(
                imageURLs: preview.urls,
                initialIndex: preview.index,
                viewModel: viewModel
            )
        }
    }

    @ViewBuilder
    private var randomFavoriteCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("随机喜欢图片")
                    .font(.headline)
                Spacer()
                if isLoadingRandomFavorite {
                    ProgressView()
                }
            }

            if let imageURL = randomFavoriteImageURL {
                Button {
                    let previewPool = randomFavoritePreviewPool.isEmpty ? [imageURL] : randomFavoritePreviewPool
                    let normalized = HiddenSpaceAPI.normalizeImageURL(imageURL).absoluteString
                    let index = previewPool.firstIndex(where: { $0.absoluteString == normalized }) ?? 0
                    previewImage = PreviewImage(index: index, urls: previewPool)
                } label: {
                    AsyncCoverImage(url: imageURL, fitToContainer: true)
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                if let randomFavoriteSourceLabel {
                    Text(randomFavoriteSourceLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Button {
                    Task {
                        await loadRandomFavorite(force: true)
                    }
                } label: {
                    Label("再随机", systemImage: "shuffle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoadingRandomFavorite)
            } else if isLoadingRandomFavorite {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("正在汇总喜欢图片...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(randomFavoriteError ?? "暂时没有可随机的图片")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("重试") {
                        Task {
                            await loadRandomFavorite(force: true)
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    @ViewBuilder
    private var favoriteCollectionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("分类查看")
                .font(.headline)

            if !viewModel.favoriteImageURLs.isEmpty {
                NavigationLink(value: HiddenSpaceRoute.fourKHDFavoriteImages) {
                    HiddenFavoriteSectionLinkCard(
                        title: "喜欢的图片",
                        subtitle: "进入子页分页查看，避免总览页一次性加载全部图片",
                        countText: "\(viewModel.favoriteImageURLs.count)",
                        systemImage: "photo.stack"
                    )
                }
                .buttonStyle(.plain)
            }

            if !viewModel.favoriteAlbums.isEmpty {
                NavigationLink(value: HiddenSpaceRoute.fourKHDFavoriteAlbums) {
                    HiddenFavoriteSectionLinkCard(
                        title: "喜欢的 album",
                        subtitle: "进入子页分页查看 album，按页控制封面数量",
                        countText: "\(viewModel.favoriteAlbums.count)",
                        systemImage: "square.stack.3d.up"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func loadRandomFavorite(force: Bool) async {
        if !force, randomFavoriteImageURL != nil {
            return
        }
        if isLoadingRandomFavorite {
            return
        }

        isLoadingRandomFavorite = true
        randomFavoriteError = nil

        defer {
            isLoadingRandomFavorite = false
        }

        do {
            let selection = try await viewModel.fetchRandomFavoriteImageSelection()
            randomFavoritePreviewPool = selection.previewPool
            randomFavoriteImageURL = selection.selected
            randomFavoriteSourceLabel = selection.sourceLabel
            viewModel.prefetchImages(Array(selection.previewPool.prefix(6)))
        } catch {
            randomFavoritePreviewPool = []
            randomFavoriteImageURL = nil
            randomFavoriteSourceLabel = nil
            randomFavoriteError = error.localizedDescription
        }
    }

    private var previewImage: PreviewImage? {
        get {
            guard case let .fourKHDFavoritesPreview(preview) = presentationState.modal else { return nil }
            return preview
        }
        nonmutating set {
            presentationState.modal = newValue.map(HiddenSpacePresentedModal.fourKHDFavoritesPreview)
        }
    }

    private var previewImageBinding: Binding<PreviewImage?> {
        Binding(
            get: { previewImage },
            set: { previewImage = $0 }
        )
    }
}

struct HiddenFavoriteImagesView: View {
    @ObservedObject var viewModel: HiddenSpaceViewModel
    @ObservedObject var presentationState: HiddenSpacePresentationState
    @State private var currentPage = 0

    private let imageColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]
    private let pageSize = 30

    var body: some View {
        ScrollView {
            if viewModel.favoriteImageURLs.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("还没有喜欢的图片")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("喜欢的图片")
                            .font(.headline)
                        Spacer()
                        Text("\(viewModel.favoriteImageURLs.count) 张")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    HiddenPagedFavoritesControls(
                        pageText: "第 \(effectivePage + 1) / \(pageCount) 页",
                        visibleRangeText: "显示 \(visibleRangeText)",
                        canGoPrevious: effectivePage > 0,
                        canGoNext: effectivePage < pageCount - 1,
                        onPrevious: { currentPage = max(effectivePage - 1, 0) },
                        onNext: { currentPage = min(effectivePage + 1, pageCount - 1) }
                    )

                    LazyVGrid(columns: imageColumns, spacing: 8) {
                        ForEach(Array(currentPageImageURLs.enumerated()), id: \.offset) { offset, imageURL in
                            let globalIndex = currentRange.lowerBound + offset
                            AlbumGridImageTile(
                                url: imageURL,
                                isFavorite: true,
                                onPreview: {
                                    previewImage = PreviewImage(index: globalIndex, urls: viewModel.favoriteImageURLs)
                                },
                                onToggleFavorite: {
                                    viewModel.toggleFavoriteImage(imageURL)
                                }
                            )
                        }
                    }

                    HiddenPagedFavoritesControls(
                        pageText: "第 \(effectivePage + 1) / \(pageCount) 页",
                        visibleRangeText: "显示 \(visibleRangeText)",
                        canGoPrevious: effectivePage > 0,
                        canGoNext: effectivePage < pageCount - 1,
                        onPrevious: { currentPage = max(effectivePage - 1, 0) },
                        onNext: { currentPage = min(effectivePage + 1, pageCount - 1) }
                    )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("喜欢图片")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.favoriteImageURLs.count) { _ in
            currentPage = min(currentPage, max(pageCount - 1, 0))
        }
        .task(id: effectivePage) {
            guard !currentPageImageURLs.isEmpty else { return }
            viewModel.prefetchImages(Array(currentPageImageURLs.prefix(8)))
        }
        .fullScreenCover(item: previewImageBinding) { preview in
            HiddenImagePreviewView(
                imageURLs: preview.urls,
                initialIndex: preview.index,
                viewModel: viewModel
            )
        }
    }

    private var pageCount: Int {
        max(Int(ceil(Double(viewModel.favoriteImageURLs.count) / Double(pageSize))), 1)
    }

    private var effectivePage: Int {
        min(max(currentPage, 0), max(pageCount - 1, 0))
    }

    private var currentRange: Range<Int> {
        let start = effectivePage * pageSize
        let end = min(start + pageSize, viewModel.favoriteImageURLs.count)
        return start..<end
    }

    private var currentPageImageURLs: [URL] {
        Array(viewModel.favoriteImageURLs[currentRange])
    }

    private var visibleRangeText: String {
        "\(currentRange.lowerBound + 1)-\(currentRange.upperBound) / \(viewModel.favoriteImageURLs.count) 张"
    }

    private var previewImage: PreviewImage? {
        get {
            guard case let .fourKHDFavoritesPreview(preview) = presentationState.modal else { return nil }
            return preview
        }
        nonmutating set {
            presentationState.modal = newValue.map(HiddenSpacePresentedModal.fourKHDFavoritesPreview)
        }
    }

    private var previewImageBinding: Binding<PreviewImage?> {
        Binding(
            get: { previewImage },
            set: { previewImage = $0 }
        )
    }
}

struct HiddenFavoriteAlbumsView: View {
    @ObservedObject var viewModel: HiddenSpaceViewModel
    @State private var currentPage = 0

    private let albumColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]
    private let pageSize = 18

    var body: some View {
        ScrollView {
            if viewModel.favoriteAlbums.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "square.stack.3d.up.slash")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("还没有喜欢的 album")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("喜欢的 album")
                            .font(.headline)
                        Spacer()
                        Text("\(viewModel.favoriteAlbums.count) 个")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    HiddenPagedFavoritesControls(
                        pageText: "第 \(effectivePage + 1) / \(pageCount) 页",
                        visibleRangeText: "显示 \(visibleRangeText)",
                        canGoPrevious: effectivePage > 0,
                        canGoNext: effectivePage < pageCount - 1,
                        onPrevious: { currentPage = max(effectivePage - 1, 0) },
                        onNext: { currentPage = min(effectivePage + 1, pageCount - 1) }
                    )

                    LazyVGrid(columns: albumColumns, spacing: 10) {
                        ForEach(currentPageAlbums) { album in
                            NavigationLink(value: HiddenSpaceRoute.fourKHDAlbum(album)) {
                                FavoriteAlbumTile(album: album)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HiddenPagedFavoritesControls(
                        pageText: "第 \(effectivePage + 1) / \(pageCount) 页",
                        visibleRangeText: "显示 \(visibleRangeText)",
                        canGoPrevious: effectivePage > 0,
                        canGoNext: effectivePage < pageCount - 1,
                        onPrevious: { currentPage = max(effectivePage - 1, 0) },
                        onNext: { currentPage = min(effectivePage + 1, pageCount - 1) }
                    )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("喜欢 album")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.favoriteAlbums.count) { _ in
            currentPage = min(currentPage, max(pageCount - 1, 0))
        }
    }

    private var pageCount: Int {
        max(Int(ceil(Double(viewModel.favoriteAlbums.count) / Double(pageSize))), 1)
    }

    private var effectivePage: Int {
        min(max(currentPage, 0), max(pageCount - 1, 0))
    }

    private var currentRange: Range<Int> {
        let start = effectivePage * pageSize
        let end = min(start + pageSize, viewModel.favoriteAlbums.count)
        return start..<end
    }

    private var currentPageAlbums: [HiddenAlbum] {
        Array(viewModel.favoriteAlbums[currentRange])
    }

    private var visibleRangeText: String {
        "\(currentRange.lowerBound + 1)-\(currentRange.upperBound) / \(viewModel.favoriteAlbums.count) 个"
    }
}

private struct HiddenFavoriteSectionLinkCard: View {
    let title: String
    let subtitle: String
    let countText: String
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
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(countText)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

private struct HiddenPagedFavoritesControls: View {
    let pageText: String
    let visibleRangeText: String
    let canGoPrevious: Bool
    let canGoNext: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pageText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(visibleRangeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("上一页", action: onPrevious)
                .buttonStyle(.bordered)
                .disabled(!canGoPrevious)

            Button("下一页", action: onNext)
                .buttonStyle(.borderedProminent)
                .disabled(!canGoNext)
        }
    }
}

struct HiddenAlbumDetailView: View {
    let album: HiddenAlbum
    @ObservedObject var viewModel: HiddenSpaceViewModel
    @ObservedObject var presentationState: HiddenSpacePresentationState

    @State private var imageURLs: [URL] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var imageAspectRatios: [String: CGFloat] = [:]
    @State private var lastPreviewedIndex: Int?
    @State private var pendingScrollIndex: Int?
    @State private var visibleImageFrames: [Int: CGRect] = [:]
    @State private var scrollViewportFrame: CGRect = .zero

    private let columnCount = 2
    private let columnSpacing: CGFloat = 10
    private let itemSpacing: CGFloat = 8
    private let returnScrollViewportPadding: CGFloat = 72

    var body: some View {
        ScrollViewReader { scrollProxy in
            GeometryReader { containerProxy in
                ScrollView {
                    content(availableWidth: max(containerProxy.size.width - 24, 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(
                    GeometryReader { viewportProxy in
                        Color.clear.preference(
                            key: HiddenAlbumDetailViewportPreferenceKey.self,
                            value: viewportProxy.frame(in: .global)
                        )
                    }
                )
                .onChange(of: pendingScrollIndex) { index in
                    guard let index else { return }
                    scrollToImage(index, using: scrollProxy)
                }
                .onPreferenceChange(HiddenAlbumDetailImageFramePreferenceKey.self) { frames in
                    visibleImageFrames = frames
                }
                .onPreferenceChange(HiddenAlbumDetailViewportPreferenceKey.self) { frame in
                    scrollViewportFrame = frame
                }
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    openSlideshow()
                } label: {
                    Image(systemName: "play.rectangle.fill")
                }
                .disabled(imageURLs.count < 2)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.toggleFavorite(album)
                } label: {
                    Image(systemName: viewModel.isFavorite(album) ? "heart.fill" : "heart")
                        .foregroundStyle(viewModel.isFavorite(album) ? .pink : .primary)
                }
            }
        }
        .task {
            await loadImages(force: false)
        }
        .onAppear {
            if let previewImage {
                lastPreviewedIndex = previewImage.index
            }
        }
        .fullScreenCover(item: previewImageBinding, onDismiss: {
            guard let lastPreviewedIndex else { return }
            pendingScrollIndex = lastPreviewedIndex
        }) { preview in
            HiddenImagePreviewView(
                imageURLs: preview.urls,
                initialIndex: preview.index,
                viewModel: viewModel,
                autoPlaySlideshow: preview.autoPlaySlideshow,
                onExit: { index in
                    lastPreviewedIndex = index
                }
            )
        }
    }

    @ViewBuilder
    private func content(availableWidth: CGFloat) -> some View {
        if isLoading {
            VStack(spacing: 10) {
                ProgressView()
                Text("正在加载 album 全部图片...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 220)
        } else if let errorMessage {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.orange)
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("重试") {
                    Task {
                        await loadImages(force: true)
                    }
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, minHeight: 220)
        } else {
            let layout = waterfallLayout(for: availableWidth)

            HStack(alignment: .top, spacing: columnSpacing) {
                ForEach(Array(layout.columns.enumerated()), id: \.offset) { _, column in
                    LazyVStack(spacing: itemSpacing) {
                        ForEach(column) { item in
                            AlbumWaterfallImageTile(
                                url: item.url,
                                width: layout.columnWidth,
                                estimatedAspectRatio: estimatedAspectRatio(for: item.url),
                                isFavorite: viewModel.isFavoriteImage(item.url),
                                onPreview: {
                                    lastPreviewedIndex = item.index
                                    previewImage = PreviewImage(index: item.index, urls: imageURLs)
                                },
                                onToggleFavorite: {
                                    viewModel.toggleFavoriteImage(item.url)
                                },
                                onAspectRatioChange: { ratio in
                                    updateAspectRatio(ratio, for: item.url)
                                }
                            )
                            .background(
                                GeometryReader { imageProxy in
                                    Color.clear.preference(
                                        key: HiddenAlbumDetailImageFramePreferenceKey.self,
                                        value: [item.index: imageProxy.frame(in: .global)]
                                    )
                                }
                            )
                            .id(item.index)
                        }
                    }
                    .frame(width: layout.columnWidth, alignment: .top)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private func scrollToImage(_ index: Int, using scrollProxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            let comfortableViewport = scrollViewportFrame.insetBy(dx: 0, dy: returnScrollViewportPadding)
            if let targetFrame = visibleImageFrames[index],
               comfortableViewport.intersects(targetFrame) {
                pendingScrollIndex = nil
                return
            }

            let anchor = preferredReturnAnchor(for: index)
            withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.9, blendDuration: 0.12)) {
                scrollProxy.scrollTo(index, anchor: anchor)
            }
            pendingScrollIndex = nil
        }
    }

    private func preferredReturnAnchor(for index: Int) -> UnitPoint {
        let visibleIndexes = visibleImageFrames.keys.sorted()

        if let firstVisibleIndex = visibleIndexes.first, index < firstVisibleIndex {
            return UnitPoint(x: 0.5, y: 0.16)
        }

        if let lastVisibleIndex = visibleIndexes.last, index > lastVisibleIndex {
            return UnitPoint(x: 0.5, y: 0.84)
        }

        if let targetFrame = visibleImageFrames[index], targetFrame.midY < scrollViewportFrame.midY {
            return UnitPoint(x: 0.5, y: 0.16)
        }

        return UnitPoint(x: 0.5, y: 0.84)
    }

    private func loadImages(force: Bool) async {
        if !force && (!imageURLs.isEmpty || isLoading) {
            return
        }

        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        do {
            imageURLs = try await HiddenSpaceAPI.fetchAlbumImageURLs(albumURL: album.url)
            viewModel.prefetchImages(Array(imageURLs.prefix(6)))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func waterfallLayout(for availableWidth: CGFloat) -> HiddenWaterfallLayout {
        let safeWidth = max(availableWidth, 0)
        let totalSpacing = columnSpacing * CGFloat(max(columnCount - 1, 0))
        let columnWidth = max((safeWidth - totalSpacing) / CGFloat(columnCount), 0)

        var columns = Array(repeating: [HiddenWaterfallItem](), count: columnCount)
        var columnHeights = Array(repeating: CGFloat.zero, count: columnCount)

        for (index, imageURL) in imageURLs.enumerated() {
            let ratio = estimatedAspectRatio(for: imageURL)
            let itemHeight = columnWidth / max(ratio, 0.35)
            let targetColumn = columnHeights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0

            columns[targetColumn].append(HiddenWaterfallItem(index: index, url: imageURL))
            columnHeights[targetColumn] += itemHeight + itemSpacing
        }

        return HiddenWaterfallLayout(columns: columns, columnWidth: columnWidth)
    }

    private func estimatedAspectRatio(for url: URL) -> CGFloat {
        let key = HiddenSpaceAPI.normalizeImageURL(url).absoluteString
        if let ratio = imageAspectRatios[key] {
            return ratio
        }
        return HiddenImagePipeline.shared.cachedAspectRatio(for: url) ?? 0.72
    }

    private func updateAspectRatio(_ ratio: CGFloat, for url: URL) {
        let key = HiddenSpaceAPI.normalizeImageURL(url).absoluteString
        let sanitizedRatio = max(ratio, 0.35)
        if let existing = imageAspectRatios[key], abs(existing - sanitizedRatio) < 0.02 {
            return
        }
        imageAspectRatios[key] = sanitizedRatio
    }

    private func openSlideshow() {
        guard !imageURLs.isEmpty else { return }
        let startingIndex = min(max(lastPreviewedIndex ?? 0, 0), max(imageURLs.count - 1, 0))
        lastPreviewedIndex = startingIndex
        previewImage = PreviewImage(index: startingIndex, urls: imageURLs, autoPlaySlideshow: true)
    }

    private var previewImage: PreviewImage? {
        get {
            guard case let .albumDetailPreview(albumID, preview) = presentationState.modal,
                  albumID == album.id else { return nil }
            return preview
        }
        nonmutating set {
            presentationState.modal = newValue.map { HiddenSpacePresentedModal.albumDetailPreview(albumID: album.id, preview: $0) }
        }
    }

    private var previewImageBinding: Binding<PreviewImage?> {
        Binding(
            get: { previewImage },
            set: { previewImage = $0 }
        )
    }
}

private struct HiddenImagePreviewView: View {
    private enum SlideDirection {
        case left
        case right
        case up
        case down
    }

    let imageURLs: [URL]
    @ObservedObject var viewModel: HiddenSpaceViewModel
    var autoPlaySlideshow = false
    var onExit: ((Int) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int
    @State private var slideTranslation: CGSize = .zero
    @State private var activeSlideDirection: SlideDirection?
    @State private var isSwitchingImage = false
    @State private var didReportExit = false
    @State private var scale: CGFloat = 1
    @State private var committedScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero
    @State private var isSlideshowPlaying = false
    @State private var slideshowTask: Task<Void, Never>?
    @State private var containerSize: CGSize = .zero

    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 5
    private let swipeThreshold: CGFloat = 70
    private let edgeResistance: CGFloat = 0.08
    private let edgeTranslationCap: CGFloat = 26
    private let verticalGestureScale: CGFloat = 0.97
    private let slideshowIntervalNanoseconds: UInt64 = 5_000_000_000

    init(
        imageURLs: [URL],
        initialIndex: Int,
        viewModel: HiddenSpaceViewModel,
        autoPlaySlideshow: Bool = false,
        onExit: ((Int) -> Void)? = nil
    ) {
        self.imageURLs = imageURLs
        self.viewModel = viewModel
        self.autoPlaySlideshow = autoPlaySlideshow
        self.onExit = onExit
        let safeIndex = min(max(initialIndex, 0), max(imageURLs.count - 1, 0))
        _currentIndex = State(initialValue: safeIndex)
    }

    private var imageURL: URL? {
        guard !imageURLs.isEmpty else { return nil }
        return imageURLs[currentIndex]
    }

    private var displayedSlideDirection: SlideDirection? {
        activeSlideDirection
    }

    private func switchAnimation(for direction: SlideDirection) -> Animation {
        .timingCurve(0.24, 0.88, 0.34, 1, duration: switchAnimationDuration(for: direction))
    }

    private func resetAnimation(for direction: SlideDirection?) -> Animation {
        .timingCurve(0.22, 0.82, 0.24, 1, duration: resetAnimationDuration(for: direction))
    }

    private var adjacentImageURL: URL? {
        guard let direction = displayedSlideDirection,
              let targetIndex = targetIndex(for: direction),
              imageURLs.indices.contains(targetIndex) else {
            return nil
        }
        return imageURLs[targetIndex]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let imageURL {
                GeometryReader { proxy in
                    ZStack {
                        if let adjacentImageURL, let direction = displayedSlideDirection {
                            previewLayer(url: adjacentImageURL, size: proxy.size)
                                .offset(secondaryImageOffset(for: direction, in: proxy.size))
                        }

                        previewLayer(url: imageURL, size: proxy.size)
                            .scaleEffect(scale)
                            .offset(primaryImageOffset)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .contentShape(Rectangle())
                    .clipped()
                    .onAppear {
                        containerSize = proxy.size
                    }
                    .onChange(of: proxy.size) { newValue in
                        containerSize = newValue
                    }
                    .gesture(
                        dragGesture(in: proxy.size)
                            .simultaneously(with: magnificationGesture(in: proxy.size))
                    )
                    .onTapGesture(count: 2) {
                        toggleZoom(in: proxy.size)
                    }
                }
            } else {
                Text("没有可显示的图片")
                    .foregroundStyle(.white.opacity(0.8))
            }

            VStack {
                HStack {
                    if let imageURL {
                        Button {
                            toggleSlideshow()
                        } label: {
                            Image(systemName: isSlideshowPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(.white.opacity(imageURLs.count > 1 ? 0.92 : 0.45))
                                .padding(8)
                                .background(Color.black.opacity(0.35), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(imageURLs.count < 2)

                        Button {
                            viewModel.toggleFavoriteImage(imageURL)
                        } label: {
                            Image(systemName: viewModel.isFavoriteImage(imageURL) ? "heart.fill" : "heart")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(viewModel.isFavoriteImage(imageURL) ? .pink : .white)
                                .padding(10)
                                .background(Color.black.opacity(0.35), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Button {
                        reportExitIfNeeded()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)

                Spacer()

                if !imageURLs.isEmpty {
                    Text("\(currentIndex + 1) / \(imageURLs.count)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.45), in: Capsule())
                        .padding(.bottom, 24)
                }
            }
        }
        .onChange(of: currentIndex) { _ in
            resetZoom()
        }
        .task(id: currentIndex) {
            prefetchCurrentImages()
        }
        .task {
            guard autoPlaySlideshow, imageURLs.count > 1 else { return }
            startSlideshow()
        }
        .onDisappear {
            stopSlideshow()
            reportExitIfNeeded()
        }
    }

    private func magnificationGesture(in containerSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if abs(value - 1) > 0.01 {
                    stopSlideshow()
                }
                let next = clampScale(committedScale * value)
                scale = next
                offset = clampedOffset(offset, for: next, in: containerSize)
            }
            .onEnded { value in
                let next = clampScale(committedScale * value)
                scale = next
                committedScale = next
                if next <= minScale {
                    resetZoom()
                } else {
                    offset = clampedOffset(offset, for: next, in: containerSize)
                    committedOffset = offset
                }
            }
    }

    private func dragGesture(in containerSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if slideDistance(for: value.translation) > 4 {
                    stopSlideshow()
                }
                if scale > minScale {
                    let next = CGSize(
                        width: committedOffset.width + value.translation.width,
                        height: committedOffset.height + value.translation.height
                    )
                    offset = clampedOffset(next, for: scale, in: containerSize)
                    return
                }

                if slideDistance(for: value.translation) < 6 {
                    activeSlideDirection = nil
                    slideTranslation = .zero
                    return
                }

                let direction = activeSlideDirection ?? resolvedSlideDirection(for: value.translation)
                activeSlideDirection = direction
                slideTranslation = adjustedSlideTranslation(value.translation, direction: direction)
            }
            .onEnded { value in
                guard scale > minScale else {
                    settleSlide(translation: value.translation, predictedEndTranslation: value.predictedEndTranslation, in: containerSize)
                    return
                }
                committedOffset = offset
            }
    }

    private func toggleZoom(in containerSize: CGSize) {
        stopSlideshow()
        if scale > minScale {
            resetZoom()
            return
        }

        scale = 2
        committedScale = 2
        offset = clampedOffset(offset, for: scale, in: containerSize)
        committedOffset = offset
    }

    private func resetZoom() {
        scale = minScale
        committedScale = minScale
        offset = .zero
        committedOffset = .zero
        slideTranslation = .zero
        activeSlideDirection = nil
    }

    private func clampScale(_ value: CGFloat) -> CGFloat {
        min(max(value, minScale), maxScale)
    }

    private func clampedOffset(_ value: CGSize, for currentScale: CGFloat, in containerSize: CGSize) -> CGSize {
        guard currentScale > minScale else {
            return .zero
        }

        let maxX = (containerSize.width * (currentScale - 1)) / 2
        let maxY = (containerSize.height * (currentScale - 1)) / 2

        return CGSize(
            width: min(max(value.width, -maxX), maxX),
            height: min(max(value.height, -maxY), maxY)
        )
    }

    private func prefetchCurrentImages() {
        guard !imageURLs.isEmpty else { return }

        let indexes = [currentIndex - 1, currentIndex, currentIndex + 1]
            .filter { $0 >= 0 && $0 < imageURLs.count }
        let urls = indexes.map { imageURLs[$0] }
        viewModel.prefetchImages(urls)
    }

    @ViewBuilder
    private func previewLayer(url: URL, size: CGSize) -> some View {
        HiddenCachedImage(url: url) { image in
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size.width, height: size.height)
        } placeholder: {
            ProgressView()
                .frame(width: size.width, height: size.height)
        } failure: {
            VStack(spacing: 10) {
                Image(systemName: "photo")
                    .font(.system(size: 24, weight: .semibold))
                Text("图片加载失败")
            }
            .foregroundStyle(.white.opacity(0.8))
            .frame(width: size.width, height: size.height)
        }
    }

    private var primaryImageOffset: CGSize {
        scale > minScale ? offset : slideTranslation
    }

    private func secondaryImageOffset(for direction: SlideDirection, in containerSize: CGSize) -> CGSize {
        switch direction {
        case .left:
            return CGSize(width: containerSize.width + slideTranslation.width, height: 0)
        case .right:
            return CGSize(width: -containerSize.width + slideTranslation.width, height: 0)
        case .up:
            return CGSize(width: 0, height: containerSize.height + slideTranslation.height)
        case .down:
            return CGSize(width: 0, height: -containerSize.height + slideTranslation.height)
        }
    }

    private func adjustedSlideTranslation(_ translation: CGSize, direction: SlideDirection?) -> CGSize {
        guard let direction else { return .zero }

        let hasTarget = targetIndex(for: direction) != nil
        let resistance = hasTarget ? 1.0 : edgeResistance
        let projected = projectedSlideTranslation(from: translation, direction: direction)
        let gestureScale = isVertical(direction) ? verticalGestureScale : 1.0

        switch direction {
        case .left, .right:
            let width = projected.width * resistance
            let adjustedWidth = hasTarget ? width : cappedTranslation(width, limit: edgeTranslationCap)
            return CGSize(width: adjustedWidth, height: 0)
        case .up, .down:
            let height = projected.height * resistance * gestureScale
            let adjustedHeight = hasTarget ? height : cappedTranslation(height, limit: edgeTranslationCap)
            return CGSize(width: 0, height: adjustedHeight)
        }
    }

    private func settleSlide(translation: CGSize, predictedEndTranslation: CGSize, in containerSize: CGSize) {
        guard imageURLs.count > 1, !isSwitchingImage else {
            withAnimation(resetAnimation(for: activeSlideDirection)) {
                slideTranslation = .zero
                activeSlideDirection = nil
            }
            return
        }

        let direction = activeSlideDirection ?? resolvedSlideDirection(for: predictedEndTranslation)
        guard let direction, let targetIndex = targetIndex(for: direction) else {
            withAnimation(resetAnimation(for: direction)) {
                slideTranslation = .zero
                activeSlideDirection = nil
            }
            return
        }

        let effectiveTranslation = adjustedSlideTranslation(
            projectedEndTranslation(current: translation, predicted: predictedEndTranslation),
            direction: direction
        )

        guard slideDistance(for: effectiveTranslation) >= swipeThreshold else {
            withAnimation(resetAnimation(for: direction)) {
                slideTranslation = .zero
                activeSlideDirection = nil
            }
            return
        }

        isSwitchingImage = true
        beginSlideTransition(to: targetIndex, direction: direction, in: containerSize)
    }

    private func targetIndex(for direction: SlideDirection) -> Int? {
        switch direction {
        case .left, .up:
            let nextIndex = currentIndex + 1
            return nextIndex < imageURLs.count ? nextIndex : nil
        case .right, .down:
            let previousIndex = currentIndex - 1
            return previousIndex >= 0 ? previousIndex : nil
        }
    }

    private func resolvedSlideDirection(for translation: CGSize) -> SlideDirection? {
        let absWidth = abs(translation.width)
        let absHeight = abs(translation.height)
        guard max(absWidth, absHeight) >= 6 else { return nil }

        if absWidth >= absHeight {
            return translation.width < 0 ? .left : .right
        }
        return translation.height < 0 ? .up : .down
    }

    private func projectedSlideTranslation(from translation: CGSize, direction: SlideDirection) -> CGSize {
        switch direction {
        case .left, .right:
            return CGSize(width: translation.width, height: 0)
        case .up, .down:
            return CGSize(width: 0, height: translation.height)
        }
    }

    private func projectedEndTranslation(current: CGSize, predicted: CGSize) -> CGSize {
        CGSize(
            width: abs(predicted.width) > abs(current.width) ? predicted.width : current.width,
            height: abs(predicted.height) > abs(current.height) ? predicted.height : current.height
        )
    }

    private func completedSlideTranslation(for direction: SlideDirection, in containerSize: CGSize) -> CGSize {
        switch direction {
        case .left:
            return CGSize(width: -containerSize.width, height: 0)
        case .right:
            return CGSize(width: containerSize.width, height: 0)
        case .up:
            return CGSize(width: 0, height: -containerSize.height)
        case .down:
            return CGSize(width: 0, height: containerSize.height)
        }
    }

    private func slideDistance(for translation: CGSize) -> CGFloat {
        max(abs(translation.width), abs(translation.height))
    }

    private func switchAnimationDuration(for direction: SlideDirection) -> CGFloat {
        isVertical(direction) ? 0.16 : 0.17
    }

    private func resetAnimationDuration(for direction: SlideDirection?) -> CGFloat {
        guard let direction else { return 0.14 }
        return isVertical(direction) ? 0.13 : 0.14
    }

    private func isVertical(_ direction: SlideDirection) -> Bool {
        switch direction {
        case .up, .down:
            return true
        case .left, .right:
            return false
        }
    }

    private func cappedTranslation(_ value: CGFloat, limit: CGFloat) -> CGFloat {
        min(max(value, -limit), limit)
    }

    private func toggleSlideshow() {
        if isSlideshowPlaying {
            stopSlideshow()
        } else {
            startSlideshow()
        }
    }

    private func startSlideshow() {
        guard imageURLs.count > 1 else { return }
        resetZoom()
        isSlideshowPlaying = true
        restartSlideshowTask()
    }

    private func stopSlideshow() {
        isSlideshowPlaying = false
        slideshowTask?.cancel()
        slideshowTask = nil
    }

    private func restartSlideshowTask() {
        slideshowTask?.cancel()
        guard isSlideshowPlaying else { return }

        slideshowTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: slideshowIntervalNanoseconds)
                guard !Task.isCancelled, isSlideshowPlaying else { return }

                guard advanceSlideshowIfNeeded() else {
                    stopSlideshow()
                    return
                }
            }
        }
    }

    private func advanceSlideshowIfNeeded() -> Bool {
        guard !isSwitchingImage else { return true }
        guard scale <= minScale else {
            resetZoom()
            return true
        }

        let nextIndex = currentIndex + 1
        guard nextIndex < imageURLs.count else {
            return false
        }

        beginSlideTransition(to: nextIndex, direction: .left, in: containerSize)
        return true
    }

    private func beginSlideTransition(to targetIndex: Int, direction: SlideDirection, in containerSize: CGSize) {
        let transitionSize = if containerSize.width > 0 && containerSize.height > 0 {
            containerSize
        } else {
            CGSize(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
        }

        isSwitchingImage = true
        activeSlideDirection = direction

        withAnimation(switchAnimation(for: direction)) {
            slideTranslation = completedSlideTranslation(for: direction, in: transitionSize)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + switchAnimationDuration(for: direction)) {
            currentIndex = targetIndex
            slideTranslation = .zero
            activeSlideDirection = nil
            isSwitchingImage = false
        }
    }

    private func reportExitIfNeeded() {
        guard !didReportExit else { return }
        didReportExit = true
        onExit?(currentIndex)
    }
}

private struct FavoriteAlbumTile: View {
    let album: HiddenAlbum

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncCoverImage(url: album.coverURL)
                .frame(height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(album.title)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
    }
}

private struct RandomNineAlbumTile: View {
    let album: HiddenAlbum
    let isFavorite: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                AsyncCoverImage(url: album.coverURL)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                if isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Color.black.opacity(0.4), in: Circle())
                        .padding(6)
                }
            }

            Text(album.title)
                .font(.caption2)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }
}

struct AsyncCoverImage: View {
    let url: URL
    var fitToContainer: Bool = false

    var body: some View {
        ZStack {
            Rectangle().fill(Color(.tertiarySystemFill))

            HiddenCachedImage(url: url) { image in
                Image(uiImage: image)
                    .resizable()
                    .modifier(CoverScaleModifier(fitToContainer: fitToContainer))
            } placeholder: {
                ProgressView()
            } failure: {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .clipped()
    }
}

private struct CoverScaleModifier: ViewModifier {
    let fitToContainer: Bool

    func body(content: Content) -> some View {
        if fitToContainer {
            content
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            content
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct AlbumGridImageTile: View {
    let url: URL
    let isFavorite: Bool
    let onPreview: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onPreview) {
                AlbumThumbImage(url: url)
            }
            .buttonStyle(.plain)

            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isFavorite ? .pink : .white)
                    .padding(8)
                    .background(Color.black.opacity(0.35), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(6)
        }
    }
}

private struct HiddenWaterfallLayout {
    let columns: [[HiddenWaterfallItem]]
    let columnWidth: CGFloat
}

private struct HiddenAlbumDetailImageFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct HiddenAlbumDetailViewportPreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct HiddenWaterfallItem: Identifiable {
    let index: Int
    let url: URL

    var id: String {
        "\(index)-\(HiddenSpaceAPI.normalizeImageURL(url).absoluteString)"
    }
}

private struct AlbumWaterfallImageTile: View {
    let url: URL
    let width: CGFloat
    let estimatedAspectRatio: CGFloat
    let isFavorite: Bool
    let onPreview: () -> Void
    let onToggleFavorite: () -> Void
    let onAspectRatioChange: (CGFloat) -> Void

    private var tileHeight: CGFloat {
        width / max(estimatedAspectRatio, 0.35)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onPreview) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(.tertiarySystemFill))

                    HiddenCachedImage(url: url) { image in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: width, height: tileHeight)
                            .onAppear {
                                onAspectRatioChange(image.hiddenAspectRatio)
                            }
                    } placeholder: {
                        ProgressView()
                            .frame(width: width, height: tileHeight)
                    } failure: {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                            .frame(width: width, height: tileHeight)
                    }
                }
                .frame(width: width, height: tileHeight)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isFavorite ? .pink : .white)
                    .padding(8)
                    .background(Color.black.opacity(0.35), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(6)
        }
    }
}

struct AlbumThumbImage: View {
    let url: URL

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(.tertiarySystemFill))

                HiddenCachedImage(url: url) { image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } placeholder: {
                    ProgressView()
                } failure: {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private enum HiddenCachedImagePhase {
    case empty
    case success(UIImage)
    case failure
}

private struct HiddenCachedImage<Content: View, Placeholder: View, Failure: View>: View {
    let url: URL
    let content: (UIImage) -> Content
    let placeholder: () -> Placeholder
    let failure: () -> Failure

    @State private var phase: HiddenCachedImagePhase

    @MainActor
    init(
        url: URL,
        content: @escaping (UIImage) -> Content,
        placeholder: @escaping () -> Placeholder,
        failure: @escaping () -> Failure
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
        self.failure = failure
        if let image = HiddenImagePipeline.shared.cachedImage(for: url) {
            _phase = State(initialValue: .success(image))
        } else {
            _phase = State(initialValue: .empty)
        }
    }

    var body: some View {
        Group {
            switch phase {
            case let .success(image):
                content(image)
            case .failure:
                failure()
            case .empty:
                placeholder()
            }
        }
        .task(id: HiddenSpaceAPI.normalizeImageURL(url).absoluteString) {
            await loadImage()
        }
    }

    private func loadImage() async {
        if let cachedImage = HiddenImagePipeline.shared.cachedImage(for: url) {
            phase = .success(cachedImage)
            return
        }
        phase = .empty
        do {
            let image = try await HiddenImagePipeline.shared.image(for: url)
            phase = .success(image)
        } catch {
            phase = .failure
        }
    }
}
