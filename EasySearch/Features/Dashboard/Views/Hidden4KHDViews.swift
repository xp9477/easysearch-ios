import SwiftUI
import QuartzCore
import WebKit
import AVKit
@preconcurrency import AVFoundation
import UIKit

struct Hidden4KHDFeatureView: View {
    @ObservedObject var viewModel: HiddenSpaceViewModel
    @State private var searchQuery = ""

    private let randomNineColumns = [
        GridItem(.flexible(), spacing: ESUI.Space.xs),
        GridItem(.flexible(), spacing: ESUI.Space.xs),
        GridItem(.flexible(), spacing: ESUI.Space.xs)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ESUI.sectionSpacing) {
                searchAlbumCard
                randomAlbumCard

                NavigationLink(value: HiddenSpaceRoute.fourKHDFavorites) {
                    HStack(spacing: ESUI.Space.sm) {
                        ESFeatureIcon(systemName: "heart.text.square", color: .pink, size: 40)
                        VStack(alignment: .leading, spacing: ESUI.Space.xxs) {
                            Text("喜欢列表")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("图片与 album 收藏")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: ESUI.Space.xs)
                        ESStatusBadge(text: "\(viewModel.totalFavoritesCount)", tone: .accent)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .esCard()
                }
                .buttonStyle(ESCardButtonStyle())
            }
            .padding(.horizontal, ESUI.screenHorizontalPadding)
            .padding(.top, ESUI.Space.md)
            .padding(.bottom, ESUI.Space.lg)
            .esBottomTabPadding()
        }
        .esScreenBackground()
        .navigationTitle("4khd")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.prepareCloudIfNeeded()
            await viewModel.loadRandomAlbumIfNeeded()
        }
        .onChange(of: searchQuery) { newValue in
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                viewModel.resetSearchAlbums()
            }
        }
    }

    @ViewBuilder
    private var searchAlbumCard: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            ESSectionHeader(title: "搜索 album")

            HStack(spacing: ESUI.Space.sm) {
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
                .buttonStyle(.glassProminent)
                .disabled(viewModel.isSearchingAlbums || normalizedSearchQuery.isEmpty)
            }

            if viewModel.isSearchingAlbums {
                ESInfoBanner(title: "正在搜索", systemImage: "magnifyingglass", tone: .accent)
            } else if let searchErrorMessage = viewModel.searchAlbumErrorMessage {
                ESInfoBanner(title: "搜索失败", message: searchErrorMessage, systemImage: "exclamationmark.triangle", tone: .warning)
            } else if let lastQuery = viewModel.lastSearchedAlbumQuery, !viewModel.searchedAlbums.isEmpty {
                VStack(alignment: .leading, spacing: ESUI.Space.sm) {
                    Text("“\(lastQuery)” · \(viewModel.searchedAlbums.count) 个结果")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: favoriteAlbumColumns, spacing: ESUI.Space.sm) {
                        ForEach(viewModel.searchedAlbums) { album in
                            NavigationLink(value: HiddenSpaceRoute.fourKHDAlbum(album)) {
                                FavoriteAlbumTile(album: album)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else if let lastQuery = viewModel.lastSearchedAlbumQuery {
                ESEmptyState(
                    title: "没有搜索到内容",
                    message: "“\(lastQuery)” 暂无匹配 album，可换关键词重试。",
                    systemImage: "rectangle.stack"
                )
            }
        }
        .esCard()
    }

    @ViewBuilder
    private var randomAlbumCard: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            ESSectionHeader(
                title: "随机封面",
                trailing: viewModel.isLoadingRandomAlbum ? "加载中" : "随机 9 张"
            )

            if viewModel.isLoadingRandomAlbum {
                HiddenMediaPlaceholder(mode: .loading("正在抓取随机 9 张..."), systemImage: "photo.stack")
                    .frame(height: 230)
            } else if !viewModel.randomAlbums.isEmpty {
                LazyVGrid(columns: randomNineColumns, spacing: ESUI.Space.xs) {
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
                        await viewModel.loadRandomAlbums()
                    }
                } label: {
                    Label("随机 9 张", systemImage: "shuffle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .disabled(viewModel.isLoadingRandomAlbum)
            } else {
                VStack(spacing: ESUI.Space.sm) {
                    HiddenMediaPlaceholder(mode: .failure(viewModel.randomErrorMessage ?? "暂时没有拿到封面"), systemImage: "photo.stack")
                        .frame(height: 200)
                    Button("重试") {
                        Task {
                            await viewModel.loadRandomAlbums()
                        }
                    }
                    .buttonStyle(.glass)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .esCard()
    }

    private var normalizedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var favoriteAlbumColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: ESUI.Space.sm),
            GridItem(.flexible(), spacing: ESUI.Space.sm)
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
                ESEmptyState(
                    title: "还没有喜欢的内容",
                    message: "在随机封面或 album 详情中点喜欢后会出现在这里。",
                    systemImage: "heart"
                )
                .frame(maxWidth: .infinity, minHeight: 280)
            } else {
                VStack(alignment: .leading, spacing: ESUI.sectionSpacing) {
                    randomFavoriteCard
                    favoriteCollectionsSection
                }
                .padding(.horizontal, ESUI.screenHorizontalPadding)
                .padding(.top, ESUI.Space.md)
                .padding(.bottom, ESUI.Space.lg)
            }
        }
        .esScreenBackground()
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
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            ESSectionHeader(
                title: "随机喜欢图片",
                trailing: isLoadingRandomFavorite ? "加载中" : nil
            )

            if let imageURL = randomFavoriteImageURL {
                Button {
                    let previewPool = randomFavoritePreviewPool.isEmpty ? [imageURL] : randomFavoritePreviewPool
                    let normalized = HiddenSpaceAPI.normalizeImageURL(imageURL).absoluteString
                    let index = previewPool.firstIndex(where: { $0.absoluteString == normalized }) ?? 0
                    previewImage = PreviewImage(index: index, urls: previewPool)
                } label: {
                    AsyncCoverImage(url: imageURL, fitToContainer: true)
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous))
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
                .buttonStyle(.glassProminent)
                .disabled(isLoadingRandomFavorite)
            } else if isLoadingRandomFavorite {
                ESLoadingState(message: "正在汇总喜欢图片…")
                    .frame(minHeight: 160)
            } else {
                ESErrorState(
                    title: "暂时没有可随机的图片",
                    message: randomFavoriteError,
                    retryTitle: "重试",
                    retry: {
                        Task {
                            await loadRandomFavorite(force: true)
                        }
                    }
                )
                .frame(minHeight: 160)
            }
        }
        .esCard()
    }

    @ViewBuilder
    private var favoriteCollectionsSection: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            ESSectionHeader(title: "分类查看")

            if !viewModel.favoriteImageURLs.isEmpty {
                NavigationLink(value: HiddenSpaceRoute.fourKHDFavoriteImages) {
                    HiddenFavoriteSectionLinkCard(
                        title: "喜欢的图片",
                        subtitle: "进入子页分页查看，避免总览页一次性加载全部图片",
                        countText: "\(viewModel.favoriteImageURLs.count)",
                        systemImage: "photo.stack",
                        color: .blue
                    )
                }
                .buttonStyle(ESCardButtonStyle())
            }

            if !viewModel.favoriteAlbums.isEmpty {
                NavigationLink(value: HiddenSpaceRoute.fourKHDFavoriteAlbums) {
                    HiddenFavoriteSectionLinkCard(
                        title: "喜欢的 album",
                        subtitle: "进入子页分页查看 album，按页控制封面数量",
                        countText: "\(viewModel.favoriteAlbums.count)",
                        systemImage: "square.stack.3d.up",
                        color: .indigo
                    )
                }
                .buttonStyle(ESCardButtonStyle())
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
        GridItem(.flexible(), spacing: ESUI.Space.xs),
        GridItem(.flexible(), spacing: ESUI.Space.xs),
        GridItem(.flexible(), spacing: ESUI.Space.xs)
    ]
    private let pageSize = 30

    var body: some View {
        ScrollView {
            if viewModel.favoriteImageURLs.isEmpty {
                ESEmptyState(
                    title: "还没有喜欢的图片",
                    message: "在 album 预览中点喜欢后会出现在这里。",
                    systemImage: "photo.on.rectangle.angled"
                )
                .frame(maxWidth: .infinity, minHeight: 280)
            } else {
                VStack(alignment: .leading, spacing: ESUI.Space.md) {
                    ESSectionHeader(title: "喜欢的图片", trailing: "\(viewModel.favoriteImageURLs.count) 张")

                    HiddenPagedFavoritesControls(
                        pageText: "第 \(effectivePage + 1) / \(pageCount) 页",
                        visibleRangeText: "显示 \(visibleRangeText)",
                        canGoPrevious: effectivePage > 0,
                        canGoNext: effectivePage < pageCount - 1,
                        onPrevious: { currentPage = max(effectivePage - 1, 0) },
                        onNext: { currentPage = min(effectivePage + 1, pageCount - 1) }
                    )

                    LazyVGrid(columns: imageColumns, spacing: ESUI.Space.xs) {
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
                .padding(.horizontal, ESUI.screenHorizontalPadding)
                .padding(.vertical, ESUI.Space.md)
            }
        }
        .esScreenBackground()
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
        GridItem(.flexible(), spacing: ESUI.Space.sm),
        GridItem(.flexible(), spacing: ESUI.Space.sm)
    ]
    private let pageSize = 18

    var body: some View {
        ScrollView {
            if viewModel.favoriteAlbums.isEmpty {
                ESEmptyState(
                    title: "还没有喜欢的 album",
                    message: "在随机封面或详情中点喜欢后会出现在这里。",
                    systemImage: "square.stack.3d.up.slash"
                )
                .frame(maxWidth: .infinity, minHeight: 280)
            } else {
                VStack(alignment: .leading, spacing: ESUI.Space.md) {
                    ESSectionHeader(title: "喜欢的 album", trailing: "\(viewModel.favoriteAlbums.count) 个")

                    HiddenPagedFavoritesControls(
                        pageText: "第 \(effectivePage + 1) / \(pageCount) 页",
                        visibleRangeText: "显示 \(visibleRangeText)",
                        canGoPrevious: effectivePage > 0,
                        canGoNext: effectivePage < pageCount - 1,
                        onPrevious: { currentPage = max(effectivePage - 1, 0) },
                        onNext: { currentPage = min(effectivePage + 1, pageCount - 1) }
                    )

                    LazyVGrid(columns: albumColumns, spacing: ESUI.Space.sm) {
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
                .padding(.horizontal, ESUI.screenHorizontalPadding)
                .padding(.vertical, ESUI.Space.md)
            }
        }
        .esScreenBackground()
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
    var color: Color = .accentColor

    var body: some View {
        HStack(spacing: ESUI.Space.sm) {
            ESFeatureIcon(systemName: systemImage, color: color, size: 42)

            VStack(alignment: .leading, spacing: ESUI.Space.xxs) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: ESUI.Space.xs)

            VStack(alignment: .trailing, spacing: ESUI.Space.xxs) {
                Text(countText)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .esCard()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
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
        HStack(spacing: ESUI.Space.sm) {
            VStack(alignment: .leading, spacing: ESUI.Space.xxs) {
                Text(pageText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(visibleRangeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("上一页", action: onPrevious)
                .buttonStyle(.glass)
                .disabled(!canGoPrevious)

            Button("下一页", action: onNext)
                .buttonStyle(.glassProminent)
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
    private let columnSpacing: CGFloat = ESUI.Space.sm
    private let itemSpacing: CGFloat = ESUI.Space.xs
    private let returnScrollViewportPadding: CGFloat = 72

    var body: some View {
        ScrollViewReader { scrollProxy in
            GeometryReader { containerProxy in
                ScrollView {
                    content(availableWidth: max(containerProxy.size.width - (ESUI.screenHorizontalPadding * 2), 0))
                }
                .padding(.horizontal, ESUI.screenHorizontalPadding)
                .padding(.vertical, ESUI.Space.md)
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
        .esScreenBackground()
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
            ESLoadingState(message: "正在加载 album 全部图片…")
                .frame(minHeight: 220)
        } else if let errorMessage {
            ESErrorState(
                title: "加载失败",
                message: errorMessage,
                retryTitle: "重试",
                retry: {
                    Task {
                        await loadImages(force: true)
                    }
                }
            )
            .frame(minHeight: 220)
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
    @StateObject private var slideAnimator = ESSlideAnimator()
    @State private var activeSlideDirection: SlideDirection?
    @State private var isSwitchingImage = false
    @State private var gestureBaseTranslation: CGSize = .zero
    @State private var isDraggingSlide = false
    @State private var lastDragSample: (translation: CGSize, time: TimeInterval)?
    @State private var dragVelocity: CGFloat = 0
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
    private let edgeTranslationCap: CGFloat = 90
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

    private var slideTranslation: CGSize {
        slideAnimator.translation
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
                .padding(.horizontal, ESUI.Space.md)
                .padding(.top, ESUI.Space.sm)

                Spacer()

                if !imageURLs.isEmpty {
                    Text("\(currentIndex + 1) / \(imageURLs.count)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, ESUI.Space.sm)
                        .padding(.vertical, ESUI.Space.xs)
                        .background(Color.black.opacity(0.45), in: Capsule())
                        .padding(.bottom, ESUI.Space.xl)
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

                beginSlideDragIfNeeded()
                trackDragVelocity(value.translation)

                let combined = CGSize(
                    width: gestureBaseTranslation.width + value.translation.width,
                    height: gestureBaseTranslation.height + value.translation.height
                )

                guard slideDistance(for: combined) >= 6 else {
                    activeSlideDirection = nil
                    slideAnimator.track(.zero)
                    return
                }

                let direction = activeSlideDirection ?? resolvedSlideDirection(for: combined)
                activeSlideDirection = direction
                slideAnimator.track(adjustedSlideTranslation(combined, direction: direction))
            }
            .onEnded { value in
                guard scale > minScale else {
                    let combined = CGSize(
                        width: gestureBaseTranslation.width + value.translation.width,
                        height: gestureBaseTranslation.height + value.translation.height
                    )
                    endSlideDrag()
                    settleSlide(translation: combined, in: containerSize)
                    return
                }
                committedOffset = offset
            }
    }

    /// 手指落下时抢回正在跑的落位动画,把当前呈现位置作为新的拖拽基准。
    /// 这一步是"可打断"的核心:动画不会先跑完再理会用户。
    private func beginSlideDragIfNeeded() {
        guard !isDraggingSlide else { return }
        isDraggingSlide = true
        gestureBaseTranslation = slideAnimator.takeOver()
        isSwitchingImage = false
        dragVelocity = 0
        lastDragSample = nil
    }

    private func endSlideDrag() {
        isDraggingSlide = false
        gestureBaseTranslation = .zero
        lastDragSample = nil
    }

    /// 采样最近两帧算瞬时速度。`predictedEndTranslation` 在中途反向时会失真,
    /// 自己采样才能拿到真实的释放速度。
    private func trackDragVelocity(_ translation: CGSize) {
        let now = CACurrentMediaTime()
        defer { lastDragSample = (translation, now) }

        guard let previous = lastDragSample else { return }
        let elapsed = now - previous.time
        guard elapsed > 0.001 else { return }

        let deltaX = translation.width - previous.translation.width
        let deltaY = translation.height - previous.translation.height
        let delta = abs(deltaX) >= abs(deltaY) ? deltaX : deltaY
        let instant = CGFloat(Double(delta) / elapsed)

        // 轻度平滑,避免最后一帧抖动主导判定。
        dragVelocity = dragVelocity * 0.3 + instant * 0.7
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
        slideAnimator.reset()
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
        let projected = projectedSlideTranslation(from: translation, direction: direction)
        let gestureScale = isVertical(direction) ? verticalGestureScale : 1.0

        switch direction {
        case .left, .right:
            // 到头时用橡皮筋渐进阻尼,而不是线性衰减后硬停。
            let width = hasTarget
                ? projected.width
                : CGFloat(ESGestureProjection.rubberBand(Double(projected.width), limit: Double(edgeTranslationCap)))
            return CGSize(width: width, height: 0)
        case .up, .down:
            let raw = projected.height * gestureScale
            let height = hasTarget
                ? raw
                : CGFloat(ESGestureProjection.rubberBand(Double(raw), limit: Double(edgeTranslationCap)))
            return CGSize(width: 0, height: height)
        }
    }

    private func settleSlide(translation: CGSize, in containerSize: CGSize) {
        guard imageURLs.count > 1 else {
            cancelSlide()
            return
        }

        let direction = activeSlideDirection ?? resolvedSlideDirection(for: translation)
        guard let direction, let targetIndex = targetIndex(for: direction) else {
            cancelSlide()
            return
        }

        // 是否翻页由"位移 + 速度投射的落点"共同决定,
        // 所以快速轻扫即使位移很小也算数,慢速长拖则按位移判定。
        let currentDistance = slideDistance(for: slideAnimator.translation)
        let projected = CGFloat(ESGestureProjection.projectedOffset(velocity: Double(dragVelocity)))
        let projectedDistance = currentDistance + abs(projected)
        let isFlick = abs(dragVelocity) > 320 && isVelocityAligned(dragVelocity, with: direction)

        guard projectedDistance >= swipeThreshold || isFlick else {
            cancelSlide()
            return
        }

        beginSlideTransition(
            to: targetIndex,
            direction: direction,
            in: containerSize,
            initialVelocity: dragVelocity
        )
    }

    /// 未达翻页条件:带着当前速度弹回原位,而不是硬切回 0。
    private func cancelSlide() {
        slideAnimator.settle(
            to: .zero,
            vertical: isVertical(activeSlideDirection ?? .left),
            velocity: dragVelocity,
            spring: .snap
        ) {
            activeSlideDirection = nil
        }
        isSwitchingImage = false
    }

    /// 速度方向必须与滑动方向一致,否则用户是在往回收手,不该翻页。
    private func isVelocityAligned(_ velocity: CGFloat, with direction: SlideDirection) -> Bool {
        switch direction {
        case .left, .up:
            return velocity < 0
        case .right, .down:
            return velocity > 0
        }
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

    private func isVertical(_ direction: SlideDirection) -> Bool {
        switch direction {
        case .up, .down:
            return true
        case .left, .right:
            return false
        }
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
        guard !isSwitchingImage, !isDraggingSlide else { return true }
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

    private func beginSlideTransition(
        to targetIndex: Int,
        direction: SlideDirection,
        in containerSize: CGSize,
        initialVelocity: CGFloat = 0
    ) {
        let transitionSize = if containerSize.width > 0 && containerSize.height > 0 {
            containerSize
        } else {
            CGSize(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
        }

        isSwitchingImage = true
        activeSlideDirection = direction
        ESHaptics.tap()

        // 落位动画继承释放速度,并在真正到位后才提交索引。
        // 期间手指再次按下会直接接管当前位置,提交也随之取消。
        slideAnimator.settle(
            to: completedSlideTranslation(for: direction, in: transitionSize),
            vertical: isVertical(direction),
            velocity: initialVelocity,
            spring: .snap
        ) {
            currentIndex = targetIndex
            slideAnimator.reset()
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
        VStack(alignment: .leading, spacing: ESUI.Space.xs) {
            AsyncCoverImage(url: album.coverURL, fitToContainer: true)
                .frame(maxWidth: .infinity)
                .frame(height: 110)
                .clipShape(RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous))
                .clipped()

            Text(album.title)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
                    .clipShape(RoundedRectangle(cornerRadius: ESUI.Space.xs, style: .continuous))

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

struct HiddenMediaPlaceholder: View {
    enum Mode {
        case loading(String?)
        case empty(String)
        case failure(String)
    }

    let mode: Mode
    var systemImage: String = "photo"

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                .fill(ESUI.fill)

            VStack(spacing: ESUI.Space.xs) {
                switch mode {
                case let .loading(text):
                    ProgressView()
                        .controlSize(.regular)
                    if let text {
                        Text(text)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                case let .empty(text):
                    Image(systemName: systemImage)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case let .failure(text):
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text(text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .padding(ESUI.Space.md)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct AsyncCoverImage: View {
    let url: URL
    var fitToContainer: Bool = false

    var body: some View {
        ZStack {
            HiddenMediaPlaceholder(mode: .loading(nil), systemImage: "photo")

            HiddenCachedImage(url: url) { image in
                Image(uiImage: image)
                    .resizable()
                    .modifier(CoverScaleModifier(fitToContainer: fitToContainer))
            } placeholder: {
                HiddenMediaPlaceholder(mode: .loading(nil), systemImage: "photo")
            } failure: {
                HiddenMediaPlaceholder(mode: .failure("图片加载失败"), systemImage: "photo")
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
                    RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                        .fill(ESUI.fill)

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
                .clipShape(RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous))
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
                RoundedRectangle(cornerRadius: ESUI.Space.xs, style: .continuous)
                    .fill(ESUI.fill)

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
            .clipShape(RoundedRectangle(cornerRadius: ESUI.Space.xs, style: .continuous))
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
