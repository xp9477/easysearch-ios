import SwiftUI
import WebKit
import AVKit
import AVFoundation
import Security
import UIKit

public struct DashboardView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var registry: FeatureRegistry
    private let isTabActive: Bool
    @State private var path = NavigationPath()
    @State private var navigationStackIdentity = UUID()
    @State private var dashboardTapCount = 0
    @State private var hiddenModulesUnlocked = false
    @State private var selectedFeatureID: String?

    public init(isTabActive: Bool = true) {
        self.isTabActive = isTabActive
    }

    public var body: some View {
        NavigationStack(path: $path) {
            List {
                if availableFeatures.isEmpty {
                    Section {
                        Label("暂无模块", systemImage: "square.grid.2x2")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(availableFeatures, id: \.id) { feature in
                            NavigationLink(value: feature.id) {
                                FeatureRow(feature: feature)
                            }
                        }
                    }
                }
            }
            .navigationTitle("模块")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("模块")
                        .font(.headline)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            unlockHiddenModulesIfNeeded()
                        }
                }
            }
            .navigationDestination(for: String.self) { featureId in
                if let feature = registry.features.first(where: { $0.id == featureId }) {
                    feature.entryView
                        .navigationBarTitleDisplayMode(.inline)
                        .onAppear {
                            selectedFeatureID = featureId
                        }
                } else {
                    Text("模块不存在")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .id(navigationStackIdentity)
        .overlay {
            if scenePhase != .active && shouldMaskHiddenFeatures {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
            }
        }
        .onChange(of: scenePhase) { phase in
            guard phase != .active else { return }
            lockHiddenModulesForPrivacyIfNeeded()
        }
        .onChange(of: path.count) { count in
            if count == 0 {
                collapseHiddenSpaceAfterExitIfNeeded()
            }
        }
        .onChange(of: isTabActive) { isActive in
            guard !isActive else { return }
            collapseHiddenSpaceOnTabLeaveIfNeeded()
        }
    }

    private func unlockHiddenModulesIfNeeded() {
        dashboardTapCount += 1
        guard dashboardTapCount >= 12 else { return }
        dashboardTapCount = 0
        hiddenModulesUnlocked = true
    }

    private var availableFeatures: [any AppFeature] {
        if hiddenModulesUnlocked {
            return registry.moduleListFeatures + registry.hiddenFeatures
        }
        return registry.moduleListFeatures
    }

    private var hiddenFeatureIDs: Set<String> {
        Set(registry.hiddenFeatures.map { $0.id })
    }

    private var shouldMaskHiddenFeatures: Bool {
        hiddenModulesUnlocked || isInsideHiddenFeature
    }

    private var isInsideHiddenFeature: Bool {
        guard let selectedFeatureID else { return false }
        return hiddenFeatureIDs.contains(selectedFeatureID)
    }

    private func lockHiddenModulesForPrivacyIfNeeded() {
        guard shouldMaskHiddenFeatures else { return }
        dashboardTapCount = 0
        hiddenModulesUnlocked = false
        if isInsideHiddenFeature {
            selectedFeatureID = nil
            resetNavigationStack()
        }
    }

    private func collapseHiddenSpaceAfterExitIfNeeded() {
        if isInsideHiddenFeature {
            dashboardTapCount = 0
            hiddenModulesUnlocked = false
        }
        selectedFeatureID = nil
    }

    private func collapseHiddenSpaceOnTabLeaveIfNeeded() {
        guard shouldMaskHiddenFeatures else { return }
        dashboardTapCount = 0
        hiddenModulesUnlocked = false
        selectedFeatureID = nil
        resetNavigationStack()
    }

    private func resetNavigationStack() {
        path = NavigationPath()
        navigationStackIdentity = UUID()
    }
}

struct HiddenSpaceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                NavigationLink {
                    Hidden4KHDFeatureView()
                } label: {
                    fourKHDFeatureCard
                }
                .buttonStyle(.plain)

                NavigationLink {
                    HiddenJavDBFeatureView()
                } label: {
                    javDBFeatureCard
                }
                .buttonStyle(.plain)

                NavigationLink {
                    HiddenMissAVFeatureView()
                } label: {
                    missAVFeatureCard
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .padding(.bottom, 18)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("隐藏空间")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var fourKHDFeatureCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 54, height: 54)
                Image(systemName: "photo.stack")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("4khd")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("随机封面、album 全图、喜欢列表")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var javDBFeatureCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 54, height: 54)
                Image(systemName: "film.stack")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("javdb")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("随机影片、喜欢影片、详情信息（默认折叠）")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var missAVFeatureCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 54, height: 54)
                Image(systemName: "play.square.stack.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("MISSAV")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("首页直达、番号直达")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

private struct Hidden4KHDFeatureView: View {
    @StateObject private var viewModel = HiddenSpaceViewModel()
    @State private var randomMode: HiddenRandomMode = .single
    @State private var searchQuery = ""

    private let randomNineColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                searchAlbumCard
                randomAlbumCard

                NavigationLink {
                    HiddenFavoriteAlbumsView(viewModel: viewModel)
                } label: {
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
                            NavigationLink {
                                HiddenAlbumDetailView(album: album, viewModel: viewModel)
                            } label: {
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
                    NavigationLink {
                        HiddenAlbumDetailView(album: album, viewModel: viewModel)
                    } label: {
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
                            NavigationLink {
                                HiddenAlbumDetailView(album: album, viewModel: viewModel)
                            } label: {
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

struct HiddenMissAVFeatureView: View {
    @State private var codeQuery = ""
    @State private var webPageItem: HiddenInAppWebPageItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                openHomeCard
                directCodeCard
                tipsCard
            }
            .padding(16)
            .padding(.bottom, 18)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("MISSAV")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $webPageItem) { item in
            HiddenInAppWebPageView(item: item)
        }
    }

    private var openHomeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("站点入口")
                .font(.headline)

            Text("直接进入 MISSAV 首页，后续在站内继续搜索、筛选和播放。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                webPageItem = HiddenInAppWebPageItem(
                    title: "MISSAV",
                    url: HiddenMissAVModule.homeURL
                )
            } label: {
                Label("进入 MISSAV", systemImage: "safari")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var directCodeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("番号直达")
                .font(.headline)

            HStack(spacing: 10) {
                TextField("输入番号，例如 ipzz-508", text: $codeQuery)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .submitLabel(.go)
                    .onSubmit {
                        openCodePageIfPossible()
                    }

                if !codeQuery.isEmpty {
                    Button {
                        codeQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }

                Button("打开") {
                    openCodePageIfPossible()
                }
                .buttonStyle(.borderedProminent)
                .disabled(normalizedCodeQuery.isEmpty)
            }

            Text("适合知道完整番号时直接跳转；如果只记得标题，先进入首页再用站内搜索。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("这里是隐藏空间里的一个子模块，不走 javdb 详情页。", systemImage: "eye.slash")
            Label("离开隐藏空间、切后台或切到其他 tab 时，会和隐藏空间一起退出。", systemImage: "lock")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var normalizedCodeQuery: String {
        codeQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
    }

    private func openCodePageIfPossible() {
        let query = normalizedCodeQuery
        guard let url = HiddenMissAVModule.pageURL(for: query) else { return }

        webPageItem = HiddenInAppWebPageItem(
            title: "MISSAV · \(query.uppercased())",
            url: url
        )
    }
}

private struct HiddenFavoriteAlbumsView: View {
    @ObservedObject var viewModel: HiddenSpaceViewModel
    @State private var previewImage: PreviewImage?
    @State private var randomFavoriteImageURL: URL?
    @State private var randomFavoritePool: [URL] = []
    @State private var isLoadingRandomFavorite = false
    @State private var randomFavoriteError: String?

    private let albumColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]
    private let imageColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

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

                    if !viewModel.favoriteImageURLs.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("喜欢的图片")
                                .font(.headline)

                            LazyVGrid(columns: imageColumns, spacing: 8) {
                                ForEach(Array(viewModel.favoriteImageURLs.enumerated()), id: \.offset) { index, imageURL in
                                    AlbumGridImageTile(
                                        url: imageURL,
                                        isFavorite: true,
                                        onPreview: {
                                            previewImage = PreviewImage(index: index, urls: viewModel.favoriteImageURLs)
                                        },
                                        onToggleFavorite: {
                                            viewModel.toggleFavoriteImage(imageURL)
                                        }
                                    )
                                }
                            }
                        }
                    }

                    if !viewModel.favoriteAlbums.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("喜欢的 album")
                                .font(.headline)

                            LazyVGrid(columns: albumColumns, spacing: 10) {
                                ForEach(viewModel.favoriteAlbums) { album in
                                    NavigationLink {
                                        HiddenAlbumDetailView(album: album, viewModel: viewModel)
                                    } label: {
                                        FavoriteAlbumTile(album: album)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
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
                randomFavoritePool = []
                randomFavoriteError = nil
                return
            }
            await loadRandomFavorite(force: true)
        }
        .fullScreenCover(item: $previewImage) { preview in
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
                    let normalized = HiddenSpaceAPI.normalizeImageURL(imageURL).absoluteString
                    let index = randomFavoritePool.firstIndex(where: { $0.absoluteString == normalized }) ?? 0
                    previewImage = PreviewImage(index: index, urls: randomFavoritePool)
                } label: {
                    AsyncCoverImage(url: imageURL, fitToContainer: true)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

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
            randomFavoritePool = selection.pool
            randomFavoriteImageURL = selection.selected
        } catch {
            randomFavoritePool = []
            randomFavoriteImageURL = nil
            randomFavoriteError = error.localizedDescription
        }
    }
}

private enum HiddenRandomMode: String, CaseIterable, Identifiable {
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

@MainActor
private final class HiddenSpaceViewModel: ObservableObject {
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

            favoriteAlbums = mergeAlbums(primary: remoteAlbums, secondary: favoriteAlbums)
            favoriteImageURLs = mergeImageURLs(primary: remoteImages, secondary: favoriteImageURLs)
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

    func fetchRandomFavoriteImageSelection() async throws -> (selected: URL, pool: [URL]) {
        let pool = await buildFavoriteImagePool()
        guard let selected = pool.randomElement() else {
            throw NSError(
                domain: "HiddenSpaceViewModel",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "喜欢列表里还没有可用图片"]
            )
        }
        return (selected, pool)
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

    private func buildFavoriteImagePool() async -> [URL] {
        var combined = favoriteImageURLs.map(HiddenSpaceAPI.normalizeImageURL)

        for album in favoriteAlbums {
            if let cached = favoriteAlbumImageCache[album.id] {
                combined.append(contentsOf: cached)
                continue
            }

            do {
                let fetched = try await HiddenSpaceAPI.fetchAlbumImageURLs(albumURL: album.url)
                    .map(HiddenSpaceAPI.normalizeImageURL)
                favoriteAlbumImageCache[album.id] = fetched
                combined.append(contentsOf: fetched)
            } catch {
                favoriteAlbumImageCache[album.id] = []
            }
        }

        var deduped: [URL] = []
        var seen = Set<String>()
        for url in combined {
            if seen.insert(url.absoluteString).inserted {
                deduped.append(url)
            }
        }
        return deduped
    }

    private func mergeAlbums(primary: [HiddenAlbum], secondary: [HiddenAlbum]) -> [HiddenAlbum] {
        var seen = Set<String>()
        var merged: [HiddenAlbum] = []

        for album in primary + secondary {
            if seen.insert(album.id).inserted {
                merged.append(album)
            }
        }

        return merged
    }

    private func mergeImageURLs(primary: [URL], secondary: [URL]) -> [URL] {
        var seen = Set<String>()
        var merged: [URL] = []

        for url in (primary + secondary).map(HiddenSpaceAPI.normalizeImageURL) {
            if seen.insert(url.absoluteString).inserted {
                merged.append(url)
            }
        }

        return merged
    }

    private func handleCloudMutationError(_ error: Error) {
        if error.isHiddenSupabaseAuthFailure {
            isCloudAuthenticated = false
            didPrepareCloud = false
        }
    }
}

private struct HiddenAlbumDetailView: View {
    let album: HiddenAlbum
    @ObservedObject var viewModel: HiddenSpaceViewModel

    @State private var imageURLs: [URL] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var previewImage: PreviewImage?
    @State private var imageAspectRatios: [String: CGFloat] = [:]
    @State private var lastPreviewedIndex: Int?
    @State private var pendingScrollIndex: Int?

    private let columnCount = 2
    private let columnSpacing: CGFloat = 10
    private let itemSpacing: CGFloat = 8

    var body: some View {
        ScrollViewReader { scrollProxy in
            GeometryReader { proxy in
                ScrollView {
                    content(availableWidth: max(proxy.size.width - 24, 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .onChange(of: pendingScrollIndex) { index in
                    guard let index else { return }
                    scrollToImage(index, using: scrollProxy)
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
        .fullScreenCover(item: $previewImage, onDismiss: {
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
            scrollProxy.scrollTo(index, anchor: .center)
            pendingScrollIndex = nil
        }
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

private struct AsyncCoverImage: View {
    let url: URL
    var fitToContainer: Bool = false

    var body: some View {
        ZStack {
            Rectangle().fill(Color(.tertiarySystemFill))

            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .modifier(CoverScaleModifier(fitToContainer: fitToContainer))
                case .empty:
                    ProgressView()
                case .failure:
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                @unknown default:
                    EmptyView()
                }
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

private struct AlbumThumbImage: View {
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

@MainActor
private final class HiddenImagePipeline {
    static let shared = HiddenImagePipeline()

    private let cache = NSCache<NSURL, UIImage>()
    private var inFlightTasks: [NSURL: Task<UIImage, Error>] = [:]

    private init() {
        cache.countLimit = 240
        cache.totalCostLimit = 256 * 1024 * 1024
    }

    func image(for url: URL) async throws -> UIImage {
        let normalizedURL = HiddenSpaceAPI.normalizeImageURL(url)
        let key = normalizedURL as NSURL

        if let cached = cache.object(forKey: key) {
            return cached
        }

        if let existingTask = inFlightTasks[key] {
            return try await existingTask.value
        }

        let task = Task<UIImage, Error> {
            var request = URLRequest(url: normalizedURL, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
            request.setValue("image/*", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let image = UIImage(data: data) else {
                throw NSError(
                    domain: "HiddenImagePipeline",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "图片加载失败"]
                )
            }

            return image
        }

        inFlightTasks[key] = task

        do {
            let image = try await task.value
            cache.setObject(image, forKey: key, cost: image.hiddenCacheCost)
            inFlightTasks[key] = nil
            return image
        } catch {
            inFlightTasks[key] = nil
            throw error
        }
    }

    func cachedImage(for url: URL) -> UIImage? {
        let normalizedURL = HiddenSpaceAPI.normalizeImageURL(url)
        return cache.object(forKey: normalizedURL as NSURL)
    }

    func prefetch(_ urls: [URL]) {
        for url in urls {
            Task {
                _ = try? await image(for: url)
            }
        }
    }

    func cachedAspectRatio(for url: URL) -> CGFloat? {
        let normalizedURL = HiddenSpaceAPI.normalizeImageURL(url)
        guard let image = cache.object(forKey: normalizedURL as NSURL) else {
            return nil
        }
        return image.hiddenAspectRatio
    }
}

private extension UIImage {
    var hiddenAspectRatio: CGFloat {
        max(size.width / max(size.height, 1), 0.35)
    }

    var hiddenCacheCost: Int {
        let pixelCount = Int(size.width * scale * size.height * scale)
        return max(pixelCount * 4, 1)
    }
}

private struct FeatureRow: View {
    let feature: any AppFeature

    var body: some View {
        HStack(spacing: 14) {
            featureIcon

            Text(feature.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var featureIcon: some View {
        if feature.id == "uttracker" {
            UTModuleProgressIcon(color: feature.color)
        } else {
            ZStack {
                Circle()
                    .fill(feature.color.opacity(0.12))
                    .frame(width: 44, height: 44)

                Image(systemName: feature.iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(feature.color)
            }
        }
    }
}

private struct UTModuleProgressIcon: View {
    let color: Color

    @Environment(\.scenePhase) private var scenePhase
    @State private var summary = UTTrackerSnapshot.currentWeekSummary()

    private var progress: Double {
        min(max(summary.fullWeekProgress, 0), 1)
    }

    private var percentValue: Int {
        Int((summary.fullWeekProgress * 100).rounded())
    }

    private var ringColor: Color {
        if summary.totalHours <= 0.01 {
            return .secondary.opacity(0.45)
        }
        return summary.isTargetMet ? .green : .orange
    }

    private var displayText: String {
        "\(max(percentValue, 0))"
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.08))
                .frame(width: 44, height: 44)

            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 4)
                .frame(width: 36, height: 36)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .frame(width: 36, height: 36)
                .rotationEffect(.degrees(-90))

            Text(displayText)
                .font(.system(size: displayText.count >= 3 ? 10 : 11, weight: .bold, design: .rounded))
                .foregroundStyle(summary.totalHours <= 0.01 ? .secondary : .primary)
        }
        .frame(width: 44, height: 44)
        .onAppear {
            refreshSummary()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            refreshSummary()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                refreshSummary()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("UT 本周进度")
        .accessibilityValue("\(displayText) 百分比")
    }

    private func refreshSummary() {
        summary = UTTrackerSnapshot.currentWeekSummary()
    }
}

private struct HiddenAlbum: Identifiable, Codable, Hashable {
    let url: URL
    let title: String
    let coverURL: URL

    var id: String { url.absoluteString }
}

private struct PreviewImage: Identifiable {
    let index: Int
    let urls: [URL]
    var autoPlaySlideshow = false

    var id: String {
        guard !urls.isEmpty else { return "empty-\(index)" }
        let safeIndex = min(max(index, 0), urls.count - 1)
        return "\(safeIndex)-\(urls[safeIndex].absoluteString)-\(autoPlaySlideshow ? "slideshow" : "manual")"
    }
}

private enum HiddenSpaceAPI {
    private static let baseURL = URL(string: "https://www.4khd.com/")!
    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile"

    static func fetchRandomAlbum(knownTotalPages: Int?) async throws -> (album: HiddenAlbum, totalPages: Int) {
        let totalPages = try await resolveTotalPages(knownTotalPages: knownTotalPages)

        var attempts = 0
        while attempts < 8 {
            attempts += 1

            let randomPage = Int.random(in: 1...max(totalPages, 1))
            let html = try await fetchHTML(from: listURL(page: randomPage))
            let albums = parseAlbums(from: html)

            if let album = albums.randomElement() {
                return (album, totalPages)
            }
        }

        throw NSError(domain: "HiddenSpaceAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "没有解析到可用封面，请稍后重试"])
    }

    static func fetchAlbumImageURLs(albumURL: URL) async throws -> [URL] {
        let firstHTML = try await fetchHTML(from: albumURL)

        var pageURLs = [albumURL]
        let extraPageURLs = parseAlbumPageLinks(from: firstHTML)
        for url in extraPageURLs where !pageURLs.contains(url) {
            pageURLs.append(url)
        }

        var allImages: [URL] = []
        var seen = Set<String>()

        for pageURL in pageURLs {
            let html = pageURL == albumURL ? firstHTML : (try await fetchHTML(from: pageURL))
            let pageImages = parseAlbumImages(from: html)
            for imageURL in pageImages where seen.insert(imageURL.absoluteString).inserted {
                allImages.append(imageURL)
            }
        }

        guard !allImages.isEmpty else {
            throw NSError(domain: "HiddenSpaceAPI", code: -2, userInfo: [NSLocalizedDescriptionKey: "没有拿到图片列表"])
        }

        return allImages
    }

    static func searchAlbums(query: String) async throws -> [HiddenAlbum] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return [] }

        let html = try await fetchHTML(from: searchURL(query: normalizedQuery))
        return parseAlbums(from: html)
    }

    private static func resolveTotalPages(knownTotalPages: Int?) async throws -> Int {
        if let knownTotalPages, knownTotalPages > 0 {
            return knownTotalPages
        }

        let html = try await fetchHTML(from: baseURL)
        let queryPages = regexCaptureAll(pattern: #"\?query-3-page=(\d+)"#, in: html, dotMatchesLine: false)
            .compactMap { Int($0) }
        if let maxQueryPage = queryPages.max(), maxQueryPage > 0 {
            return maxQueryPage
        }

        let standardPages = regexCaptureAll(pattern: #"/page/(\d+)"#, in: html, dotMatchesLine: false)
            .compactMap { Int($0) }
        if let maxStandardPage = standardPages.max(), maxStandardPage > 0 {
            return maxStandardPage
        }

        return 2800
    }

    private static func listURL(page: Int) -> URL {
        guard page > 1 else { return baseURL }
        return URL(string: "https://www.4khd.com/?query-3-page=\(page)") ?? baseURL
    }

    private static func searchURL(query: String) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "s", value: query)]
        return components?.url ?? baseURL
    }

    private static func fetchHTML(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "HiddenSpaceAPI", code: -3, userInfo: [NSLocalizedDescriptionKey: "页面请求失败"])
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "HiddenSpaceAPI", code: -4, userInfo: [NSLocalizedDescriptionKey: "页面解析失败"])
        }
        return html
    }

    private static func parseAlbums(from html: String) -> [HiddenAlbum] {
        let blocks = regexCaptureAll(
            pattern: #"<li class="wp-block-post[^"]*"[^>]*>(.*?)</li>"#,
            in: html,
            dotMatchesLine: true
        )

        var albums: [HiddenAlbum] = []
        var seen = Set<String>()

        for block in blocks {
            guard let rawLink = regexFirstCapture(pattern: #"href="(https://www\.4khd\.com/content/[^"]+?\.html)""#, in: block, dotMatchesLine: true),
                  let albumURL = normalizedURL(from: rawLink),
                  let rawCover = regexFirstCapture(pattern: #"<img[^>]+src="([^"]+)""#, in: block, dotMatchesLine: true),
                  let coverURL = normalizedURL(from: rawCover) else {
                continue
            }

            let rawTitle = regexFirstCapture(pattern: #"<h2[^>]*>\s*<a[^>]*>(.*?)</a>"#, in: block, dotMatchesLine: true)
            let title = cleanTitle(rawTitle ?? albumURL.lastPathComponent)

            if seen.insert(albumURL.absoluteString).inserted {
                albums.append(HiddenAlbum(url: albumURL, title: title, coverURL: coverURL))
            }
        }

        return albums
    }

    private static func parseAlbumPageLinks(from html: String) -> [URL] {
        let rawLinks = regexCaptureAll(
            pattern: #"<a[^>]+class="[^"]*page-numbers[^"]*"[^>]+href="([^"]+)""#,
            in: html,
            dotMatchesLine: true
        ) + regexCaptureAll(
            pattern: #"<a[^>]+href="([^"]+)"[^>]+class="[^"]*page-numbers[^"]*""#,
            in: html,
            dotMatchesLine: true
        )
        var urls: [URL] = []
        var seen = Set<String>()

        for rawLink in rawLinks {
            guard let url = normalizedURL(from: rawLink),
                  seen.insert(url.absoluteString).inserted else {
                continue
            }
            urls.append(url)
        }
        return urls
    }

    private static func parseAlbumImages(from html: String) -> [URL] {
        let contentSlice = sliceEntryContent(from: html)

        let directURLs = regexCaptureAll(
            pattern: #"(?:href|src|data-src|data-lazy-src)=["']([^"']+)["']"#,
            in: contentSlice,
            dotMatchesLine: true
        )
        let srcsetValues = regexCaptureAll(
            pattern: #"(?:srcset|data-srcset)=["']([^"']+)["']"#,
            in: contentSlice,
            dotMatchesLine: true
        )
        let srcsetURLs = srcsetValues.flatMap(extractURLsFromSrcset)
        let candidateURLs = directURLs + srcsetURLs

        var images: [URL] = []
        var seen = Set<String>()

        for rawURL in candidateURLs {
            guard let url = normalizedURL(from: rawURL),
                  isLikelyImageURL(url),
                  seen.insert(url.absoluteString).inserted else {
                continue
            }
            images.append(url)
        }

        return images
    }

    private static func sliceEntryContent(from html: String) -> String {
        guard let startRange = html.range(of: "entry-content wp-block-post-content") else {
            return html
        }

        let tail = html[startRange.lowerBound...]
        if let endRange = tail.range(of: "page-link-box") {
            return String(tail[..<endRange.lowerBound])
        }
        return String(tail)
    }

    private static func normalizedURL(from raw: String) -> URL? {
        let decoded = decodeHTMLEntities(raw)
            .replacingOccurrences(of: "&#038;", with: "&")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let rawURL: URL?
        if decoded.hasPrefix("//") {
            rawURL = URL(string: "https:" + decoded)
        } else if decoded.hasPrefix("/") {
            rawURL = URL(string: "https://www.4khd.com" + decoded)
        } else {
            rawURL = URL(string: decoded)
        }

        guard let rawURL else { return nil }

        if isLikelyImageURL(rawURL) {
            return normalizeImageURL(rawURL)
        }
        return normalizeAlbumURL(rawURL)
    }

    static func normalizeImageURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        let host = components.host?.lowercased() ?? ""

        // Site HTML often uses i0.wp.com/pic.4khd.com/... which returns 400 directly.
        // Rewrite it to img.4khd.com/... first, then follow redirects.
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

    private static func isLikelyImageURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }

        let host = components.host?.lowercased() ?? ""
        let path = components.path.lowercased()
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()

        if host == "img.4khd.com" || host == "pic.4khd.com" {
            return true
        }
        if host.hasSuffix(".wp.com") && path.contains("/pic.4khd.com/") {
            return true
        }

        return ext == "jpg"
            || ext == "jpeg"
            || ext == "png"
            || ext == "webp"
            || ext == "gif"
            || ext == "avif"
    }

    private static func extractURLsFromSrcset(_ srcset: String) -> [String] {
        srcset
            .split(separator: ",")
            .compactMap { candidate in
                candidate
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .split(separator: " ")
                    .first
                    .map(String.init)
            }
    }

    private static func cleanTitle(_ text: String) -> String {
        let stripped = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        let decoded = decodeHTMLEntities(stripped)
        return decoded.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        guard let data = text.data(using: .utf8) else { return text }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        if let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            return attributed.string
        }
        return text
    }

    private static func regexFirstCapture(pattern: String, in text: String, dotMatchesLine: Bool) -> String? {
        regexCaptureAll(pattern: pattern, in: text, dotMatchesLine: dotMatchesLine).first
    }

    private static func regexCaptureAll(pattern: String, in text: String, dotMatchesLine: Bool) -> [String] {
        var options: NSRegularExpression.Options = [.caseInsensitive]
        if dotMatchesLine {
            options.insert(.dotMatchesLineSeparators)
        }

        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        return matches.compactMap { match in
            guard match.numberOfRanges > 1,
                  let captureRange = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return String(text[captureRange])
        }
    }
}

private struct HiddenJavDBFeatureView: View {
    @StateObject private var viewModel = HiddenJavDBViewModel()
    @State private var randomMode: HiddenJavDBRandomMode = .single
    @State private var showRandomDetails = false
    @State private var searchQuery = ""

    private let searchColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                searchMovieCard
                randomMovieCard

                NavigationLink {
                    HiddenJavDBFavoriteMoviesView(viewModel: viewModel)
                } label: {
                    HStack {
                        Label("喜欢影片", systemImage: "heart.text.square")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(viewModel.favoriteMovies.count)")
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
        .navigationTitle("javdb")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.prepareCloudIfNeeded()
            await viewModel.loadRandomMovieIfNeeded(mode: randomMode)
        }
        .onChange(of: randomMode) { mode in
            showRandomDetails = false
            Task {
                await viewModel.loadRandomMovies(mode: mode)
            }
        }
        .onChange(of: searchQuery) { newValue in
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                viewModel.resetSearchMovies()
            }
        }
    }

    @ViewBuilder
    private var searchMovieCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("搜索影片")
                .font(.headline)

            HStack(spacing: 10) {
                TextField("输入番号或标题", text: $searchQuery)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .submitLabel(.search)
                    .onSubmit {
                        performMovieSearch()
                    }

                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                        viewModel.resetSearchMovies()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }

                Button("搜索") {
                    performMovieSearch()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isSearchingMovies || normalizedSearchQuery.isEmpty)
            }

            if viewModel.isSearchingMovies {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("正在搜索...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if let searchErrorMessage = viewModel.searchMovieErrorMessage {
                Text(searchErrorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let lastQuery = viewModel.lastSearchedMovieQuery, !viewModel.searchedMovies.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("“\(lastQuery)” · \(viewModel.searchedMovies.count) 个结果")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: searchColumns, spacing: 10) {
                        ForEach(viewModel.searchedMovies) { movie in
                            NavigationLink {
                                HiddenJavDBMovieDetailView(movie: movie, viewModel: viewModel)
                            } label: {
                                HiddenJavDBFavoriteMovieTile(
                                    movie: movie,
                                    detail: nil,
                                    errorMessage: nil,
                                    isLoadingDetail: false,
                                    showDetails: false
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else if let lastQuery = viewModel.lastSearchedMovieQuery {
                Text("“\(lastQuery)” 没有搜索到影片")
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
    private var randomMovieCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("功能 2 · 随机影片")
                    .font(.headline)
                Spacer()
                if viewModel.isLoadingRandomMovie {
                    ProgressView()
                }
            }

            Picker("随机模式", selection: $randomMode) {
                ForEach(HiddenJavDBRandomMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if randomMode == .single {
                if viewModel.isLoadingRandomMovie {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text(randomMode.loadingText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else if let movie = viewModel.randomMovie {
                    NavigationLink {
                        HiddenJavDBMovieDetailView(movie: movie, viewModel: viewModel)
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            AsyncCoverImage(url: movie.coverURL, fitToContainer: true)
                                .frame(height: 230)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(movie.displayTitle)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                Text(movie.code)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 12) {
                        Button {
                            Task {
                                await viewModel.loadRandomMovies(mode: randomMode)
                            }
                        } label: {
                            Label("随机 1 部", systemImage: "shuffle")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isLoadingRandomMovie)

                        Button {
                            viewModel.toggleFavorite(movie)
                        } label: {
                            Label(viewModel.isFavorite(movie) ? "已喜欢" : "喜欢", systemImage: viewModel.isFavorite(movie) ? "heart.fill" : "heart")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(viewModel.isFavorite(movie) ? .pink : .primary)
                    }

                    Button(showRandomDetails ? "隐藏详细信息" : "显示详细信息") {
                        showRandomDetails.toggle()
                    }
                    .buttonStyle(.bordered)

                    if showRandomDetails {
                        HiddenJavDBMovieDetailSummaryView(
                            movie: movie,
                            detail: viewModel.detailsByMovieID[movie.id],
                            errorMessage: viewModel.detailErrorsByMovieID[movie.id],
                            isLoading: viewModel.detailLoadingIDs.contains(movie.id)
                        )
                        .task(id: movie.id) {
                            await viewModel.loadDetailIfNeeded(for: movie)
                        }
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "film")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(viewModel.randomErrorMessage ?? "暂时没有拿到影片")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("重试") {
                            Task {
                                await viewModel.loadRandomMovies(mode: randomMode)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                }
            } else {
                if !viewModel.randomMovies.isEmpty {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(viewModel.randomMovies.prefix(9))) { movie in
                            NavigationLink {
                                HiddenJavDBMovieDetailView(movie: movie, viewModel: viewModel)
                            } label: {
                                HiddenJavDBRandomListMovieTile(movie: movie, isFavorite: viewModel.isFavorite(movie))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if viewModel.isLoadingRandomMovie {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("已加载 \(viewModel.randomMovies.count)/9")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        Task {
                            await viewModel.loadRandomMovies(mode: randomMode)
                        }
                    } label: {
                        Label("随机 9 部", systemImage: "shuffle")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isLoadingRandomMovie)
                } else if viewModel.isLoadingRandomMovie {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text(randomMode.loadingText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "film")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(viewModel.randomErrorMessage ?? "暂时没有拿到影片")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("重试") {
                            Task {
                                await viewModel.loadRandomMovies(mode: randomMode)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                }
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

    private func performMovieSearch() {
        let query = normalizedSearchQuery
        guard !query.isEmpty else {
            viewModel.resetSearchMovies()
            return
        }

        Task {
            await viewModel.searchMovies(query: query)
        }
    }
}

private struct HiddenJavDBFavoriteMoviesView: View {
    @ObservedObject var viewModel: HiddenJavDBViewModel
    @State private var showDetails = false
    @State private var isResolvingRandomPlayback = false
    @State private var randomPlaybackErrorMessage: String?
    @State private var inAppPlayerItem: HiddenInAppPlayerItem?

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ScrollView {
            if viewModel.favoriteMovies.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "heart")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("还没有喜欢的影片")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Button {
                            Task {
                                await playRandomFavoriteMovie()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if isResolvingRandomPlayback {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "shuffle")
                                }
                                Text(isResolvingRandomPlayback ? "正在随机播放..." : "随机播放")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isResolvingRandomPlayback || viewModel.favoriteMovies.isEmpty)

                        Button(showDetails ? "隐藏详细信息" : "显示详细信息") {
                            showDetails.toggle()
                        }
                        .buttonStyle(.bordered)

                        Spacer(minLength: 0)
                    }

                    if let randomPlaybackErrorMessage {
                        Text(randomPlaybackErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(viewModel.favoriteMovies) { movie in
                            NavigationLink {
                                HiddenJavDBMovieDetailView(movie: movie, viewModel: viewModel)
                            } label: {
                                HiddenJavDBFavoriteMovieTile(
                                    movie: movie,
                                    detail: viewModel.detailsByMovieID[movie.id],
                                    errorMessage: viewModel.detailErrorsByMovieID[movie.id],
                                    isLoadingDetail: viewModel.detailLoadingIDs.contains(movie.id),
                                    showDetails: showDetails
                                )
                            }
                            .buttonStyle(.plain)
                            .task(id: showDetails) {
                                guard showDetails else { return }
                                await viewModel.loadDetailIfNeeded(for: movie)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("喜欢影片")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $inAppPlayerItem) { item in
            HiddenInAppVideoPlayerView(
                item: item,
                onSaveFavoritePlayback: { playback in
                    viewModel.saveFavoritePlayback(playback)
                },
                onUndoFavoritePlaybackSave: { context in
                    viewModel.undoFavoritePlaybackSave(context)
                }
            )
        }
    }

    private func playRandomFavoriteMovie() async {
        guard !isResolvingRandomPlayback else { return }

        let favoriteMovies = viewModel.favoriteMovies.shuffled()
        guard !favoriteMovies.isEmpty else { return }

        isResolvingRandomPlayback = true
        randomPlaybackErrorMessage = nil

        defer {
            isResolvingRandomPlayback = false
        }

        var lastErrorMessage: String?
        for movie in favoriteMovies {
            let markerPositions = viewModel.playbackMarkerPositions(for: movie)

            do {
                if let resolvedPlayback = try await resolvePreferredPlayback(for: movie) {
                    inAppPlayerItem = HiddenInAppPlayerItem(
                        movie: movie,
                        sourceName: resolvedPlayback.sourceName,
                        streamURL: resolvedPlayback.streamURL,
                        refererURL: resolvedPlayback.refererURL,
                        startPositionSeconds: 0,
                        markerPositions: markerPositions
                    )
                    return
                }
            } catch {
                lastErrorMessage = error.localizedDescription
            }

            if let savedPlayback = viewModel.favoritePlaybacks(for: movie).first {
                inAppPlayerItem = HiddenInAppPlayerItem(
                    movie: movie,
                    sourceName: savedPlayback.sourceName,
                    streamURL: savedPlayback.streamURL,
                    refererURL: savedPlayback.refererURL,
                    startPositionSeconds: 0,
                    markerPositions: markerPositions
                )
                return
            }
        }

        randomPlaybackErrorMessage = lastErrorMessage ?? "没有找到可直接播放的喜欢影片"
    }

    private func resolvePreferredPlayback(for movie: HiddenJavDBMovie) async throws -> (sourceName: String, streamURL: URL, refererURL: URL)? {
        var lastError: Error?

        for site in HiddenJavDBWatchSite.defaultSites where site.launchMode == .nativeStream {
            guard let pageURL = site.url(for: movie.code) else { continue }

            do {
                let target = try await HiddenJavDBAPI.resolveWatchPlaybackTarget(for: site, pageURL: pageURL)
                if case let .stream(streamURL, refererURL) = target {
                    return (site.name, streamURL, refererURL)
                }
            } catch {
                lastError = error
            }
        }

        if let lastError {
            throw lastError
        }

        return nil
    }
}

private struct HiddenJavDBMovieDetailView: View {
    let movie: HiddenJavDBMovie
    @ObservedObject var viewModel: HiddenJavDBViewModel

    @State private var imageURLs: [URL] = []
    @State private var isLoadingImages = false
    @State private var imageErrorMessage: String?
    @State private var previewImage: HiddenJavDBPreviewImage?
    @State private var showDetails = false
    @State private var isResolvingWatchPlayback = false
    @State private var resolvingWatchSiteName: String?
    @State private var watchPlaybackErrorMessage: String?
    @State private var inAppPlayerItem: HiddenInAppPlayerItem?
    @State private var inAppWebPageItem: HiddenInAppWebPageItem?

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]
    private let watchButtonColumns = [
        GridItem(.adaptive(minimum: 110), spacing: 8)
    ]
    private var favoritePlaybackEntries: [HiddenJavDBFavoritePlayback] {
        viewModel.favoritePlaybacks(for: movie)
    }
    private var movieDetail: HiddenJavDBMovieDetail? {
        viewModel.detailsByMovieID[movie.id]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                AsyncCoverImage(url: movie.coverURL, fitToContainer: true)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button(showDetails ? "隐藏详细信息" : "显示详细信息") {
                    showDetails.toggle()
                }
                .buttonStyle(.bordered)

                if showDetails {
                    HiddenJavDBMovieDetailSummaryView(
                        movie: movie,
                        detail: viewModel.detailsByMovieID[movie.id],
                        errorMessage: viewModel.detailErrorsByMovieID[movie.id],
                        isLoading: viewModel.detailLoadingIDs.contains(movie.id)
                    )
                    .task(id: movie.id) {
                        await viewModel.loadDetailIfNeeded(for: movie)
                    }
                }

                watchSection
                favoritePlaybackSection
                screenshotsSection
                relatedMovieSections
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(movie.code)
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
            await loadImages(force: false)
        }
        .task(id: movie.id) {
            await viewModel.loadDetailIfNeeded(for: movie)
        }
        .fullScreenCover(item: $previewImage) { preview in
            HiddenJavDBImagePreviewView(imageURLs: preview.urls, initialIndex: preview.index)
        }
        .fullScreenCover(item: $inAppPlayerItem) { item in
            HiddenInAppVideoPlayerView(
                item: item,
                onSaveFavoritePlayback: { playback in
                    viewModel.saveFavoritePlayback(playback)
                },
                onUndoFavoritePlaybackSave: { context in
                    viewModel.undoFavoritePlaybackSave(context)
                }
            )
        }
        .fullScreenCover(item: $inAppWebPageItem) { item in
            HiddenInAppWebPageView(item: item)
        }
    }

    private var watchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("在线观看")
                .font(.headline)

            LazyVGrid(columns: watchButtonColumns, spacing: 8) {
                ForEach(HiddenJavDBWatchSite.defaultSites) { site in
                    if let url = site.url(for: movie.code) {
                        if site.launchMode != .external {
                            Button {
                                Task {
                                    await openWatchSite(site: site, pageURL: url)
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    if isResolvingWatchPlayback && resolvingWatchSiteName == site.name {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    }
                                    Text(isResolvingWatchPlayback && resolvingWatchSiteName == site.name ? "载入中..." : site.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color(.tertiarySystemFill))
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(isResolvingWatchPlayback)
                        } else {
                            Link(destination: url) {
                                Text(site.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(Color(.tertiarySystemFill))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if let watchPlaybackErrorMessage {
                Text(watchPlaybackErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    @ViewBuilder
    private var favoritePlaybackSection: some View {
        if !favoritePlaybackEntries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("喜欢点")
                        .font(.headline)
                    Spacer()
                    Text("\(favoritePlaybackEntries.count) 个")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(favoritePlaybackEntries) { playback in
                        HiddenJavDBFavoritePlaybackTile(
                            playback: playback,
                            onPlay: {
                                openFavoritePlayback(playback)
                            },
                            onRemove: {
                                viewModel.removeFavoritePlayback(playback)
                            }
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

    private var screenshotsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("截图")
                    .font(.headline)
                Spacer()
                if isLoadingImages {
                    ProgressView()
                }
            }

            if isLoadingImages {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("正在加载截图...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else if let imageErrorMessage {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text(imageErrorMessage)
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
                .frame(maxWidth: .infinity, minHeight: 180)
            } else if imageURLs.isEmpty {
                Text("没有拿到可用截图")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(imageURLs.enumerated()), id: \.offset) { index, imageURL in
                        Button {
                            previewImage = HiddenJavDBPreviewImage(index: index, urls: imageURLs)
                        } label: {
                            AlbumThumbImage(url: imageURL)
                        }
                        .buttonStyle(.plain)
                    }
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
    private var relatedMovieSections: some View {
        if let movieDetail {
            if !movieDetail.otherActressMovies.isEmpty {
                relatedMovieSection(
                    title: "她们还演出过",
                    movies: movieDetail.otherActressMovies
                )
            }

            if !movieDetail.recommendedMovies.isEmpty {
                relatedMovieSection(
                    title: "可能你也喜欢",
                    movies: movieDetail.recommendedMovies
                )
            }
        } else if viewModel.detailLoadingIDs.contains(movie.id) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("正在加载关联影片...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
        }
    }

    private func relatedMovieSection(title: String, movies: [HiddenJavDBMovie]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(movies.count) 部")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 10) {
                    ForEach(movies) { relatedMovie in
                        NavigationLink {
                            HiddenJavDBMovieDetailView(movie: relatedMovie, viewModel: viewModel)
                        } label: {
                            HiddenJavDBFavoriteMovieTile(
                                movie: relatedMovie,
                                detail: nil,
                                errorMessage: nil,
                                isLoadingDetail: false,
                                showDetails: false
                            )
                            .frame(width: 152, alignment: .top)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func loadImages(force: Bool) async {
        if !force && (!imageURLs.isEmpty || isLoadingImages) {
            return
        }

        isLoadingImages = true
        imageErrorMessage = nil

        defer {
            isLoadingImages = false
        }

        do {
            imageURLs = try await HiddenJavDBAPI.fetchMovieImages(movieURL: movie.url)
        } catch {
            imageErrorMessage = error.localizedDescription
        }
    }

    private func openWatchSite(site: HiddenJavDBWatchSite, pageURL: URL) async {
        if isResolvingWatchPlayback {
            return
        }

        isResolvingWatchPlayback = true
        resolvingWatchSiteName = site.name
        watchPlaybackErrorMessage = nil

        defer {
            isResolvingWatchPlayback = false
            resolvingWatchSiteName = nil
        }

        do {
            let target = try await HiddenJavDBAPI.resolveWatchPlaybackTarget(for: site, pageURL: pageURL)
            switch target {
            case let .stream(streamURL, refererURL):
                inAppPlayerItem = makePlayerItem(
                    sourceName: site.name,
                    streamURL: streamURL,
                    refererURL: refererURL,
                    startPositionSeconds: 0
                )
            case let .webPage(webURL):
                inAppWebPageItem = HiddenInAppWebPageItem(
                    title: "\(site.name) · \(movie.code)",
                    url: webURL
                )
            }
        } catch {
            watchPlaybackErrorMessage = error.localizedDescription
        }
    }

    private func openFavoritePlayback(_ playback: HiddenJavDBFavoritePlayback) {
        watchPlaybackErrorMessage = nil
        inAppPlayerItem = makePlayerItem(
            sourceName: playback.sourceName,
            streamURL: playback.streamURL,
            refererURL: playback.refererURL,
            startPositionSeconds: playback.positionSeconds
        )
    }

    private func makePlayerItem(
        sourceName: String,
        streamURL: URL,
        refererURL: URL,
        startPositionSeconds: Double
    ) -> HiddenInAppPlayerItem {
        HiddenInAppPlayerItem(
            movie: movie,
            sourceName: sourceName,
            streamURL: streamURL,
            refererURL: refererURL,
            startPositionSeconds: startPositionSeconds,
            markerPositions: viewModel.playbackMarkerPositions(for: movie)
        )
    }
}

private struct HiddenJavDBMovieDetailSummaryView: View {
    let movie: HiddenJavDBMovie
    let detail: HiddenJavDBMovieDetail?
    let errorMessage: String?
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("正在加载详细信息...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if let detail {
                HiddenJavDBDetailRow(title: "片名", value: detail.title)
                HiddenJavDBDetailRow(title: "编号", value: detail.code)
                HiddenJavDBDetailRow(title: "演员", value: detail.actressesText)
                HiddenJavDBDetailRow(title: "发行日期", value: detail.releaseDate ?? "未知")
                HiddenJavDBDetailRow(title: "片长", value: detail.durationText)
                HiddenJavDBDetailRow(title: "制作商", value: detail.studio ?? "未知")
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                HiddenJavDBDetailRow(title: "片名", value: movie.displayTitle)
                HiddenJavDBDetailRow(title: "编号", value: movie.code)
                HiddenJavDBDetailRow(title: "演员", value: movie.actressesText)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

private struct HiddenJavDBDetailRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)

            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}

private struct HiddenJavDBFavoritePlaybackTile: View {
    let playback: HiddenJavDBFavoritePlayback
    let onPlay: () -> Void
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onPlay) {
                HiddenPlaybackThumbnailView(playback: playback)
            }
            .buttonStyle(.plain)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Color.black.opacity(0.56), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(6)
        }
    }
}

private struct HiddenPlaybackThumbnailView: View {
    let playback: HiddenJavDBFavoritePlayback

    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var didFail = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.tertiarySystemFill))

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.12), Color.black.opacity(0.62)],
                startPoint: .top,
                endPoint: .bottom
            )

            if image == nil {
                thumbnailPlaceholder
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(HiddenPlaybackTimeFormatter.string(from: playback.positionSeconds))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.42), in: Capsule())

                Text(playback.sourceName)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
            }
            .padding(8)
        }
        .frame(height: 102)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task(id: playback.id) {
            await loadThumbnailIfNeeded()
        }
    }

    @ViewBuilder
    private var thumbnailPlaceholder: some View {
        VStack {
            Spacer()

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                    .padding(8)
                    .background(Color.black.opacity(0.36), in: Capsule())
            } else {
                VStack(spacing: 6) {
                    Image(systemName: didFail ? "play.rectangle" : "film.stack")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))

                    Text(didFail ? "取帧失败" : "正在取帧")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.82))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor
    private func loadThumbnailIfNeeded() async {
        guard image == nil, !isLoading else { return }
        isLoading = true
        didFail = false
        defer { isLoading = false }

        do {
            image = try await HiddenPlaybackThumbnailPipeline.shared.image(for: playback)
        } catch {
            didFail = true
        }
    }
}

private actor HiddenPlaybackThumbnailPipeline {
    static let shared = HiddenPlaybackThumbnailPipeline()

    private let cache = NSCache<NSString, UIImage>()
    private var inFlightTasks: [String: Task<UIImage, Error>] = [:]

    init() {
        cache.countLimit = 36
        cache.totalCostLimit = 24 * 1024 * 1024
    }

    func image(for playback: HiddenJavDBFavoritePlayback) async throws -> UIImage {
        let key = cacheKey(for: playback)
        let nsKey = key as NSString

        if let cachedImage = cache.object(forKey: nsKey) {
            return cachedImage
        }

        if let existingTask = inFlightTasks[key] {
            return try await existingTask.value
        }

        let task = Task(priority: .utility) {
            try await Self.generateThumbnail(for: playback)
        }
        inFlightTasks[key] = task
        defer { inFlightTasks[key] = nil }

        let image = try await task.value
        let cost = Self.imageCost(for: image)
        cache.setObject(image, forKey: nsKey, cost: cost)
        return image
    }

    private func cacheKey(for playback: HiddenJavDBFavoritePlayback) -> String {
        let normalizedTime = Int(playback.positionSeconds.rounded(.toNearestOrAwayFromZero))
        return "\(playback.movie.id)|\(playback.sourceName)|\(normalizedTime)"
    }

    private static func generateThumbnail(for playback: HiddenJavDBFavoritePlayback) async throws -> UIImage {
        try await Task.detached(priority: .utility) {
            let resolvedSource = try await HiddenJavDBAPI.resolvePlayableStream(for: playback)
            let headers: [String: String] = [
                "Referer": resolvedSource.refererURL.absoluteString,
                "Origin": "\(resolvedSource.refererURL.scheme ?? "https")://\(resolvedSource.refererURL.host ?? "missav.ws")",
                "User-Agent": HiddenJavDBAPI.userAgent
            ]
            let asset = AVURLAsset(
                url: resolvedSource.streamURL,
                options: [
                    "AVURLAssetHTTPHeaderFieldsKey": headers
                ]
            )
            let _ = try await asset.load(.isPlayable)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard !tracks.isEmpty else {
                throw NSError(
                    domain: "HiddenPlaybackThumbnailPipeline",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "未找到可用视频轨道"]
                )
            }
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 320, height: 180)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.6, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.6, preferredTimescale: 600)

            let duration = try? await asset.load(.duration)
            var lastError: Error?
            for time in thumbnailCandidateTimes(for: playback.positionSeconds, duration: duration) {
                do {
                    let cgImage = try generator.copyCGImage(
                        at: CMTime(seconds: time, preferredTimescale: 600),
                        actualTime: nil
                    )
                    return UIImage(cgImage: cgImage)
                } catch {
                    lastError = error
                }
            }

            throw lastError ?? NSError(
                domain: "HiddenPlaybackThumbnailPipeline",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "未取到可用视频帧"]
            )
        }.value
    }

    private static func thumbnailCandidateTimes(for positionSeconds: Double, duration: CMTime?) -> [Double] {
        let normalizedDuration = duration.flatMap { loadedDuration -> Double? in
            let seconds = CMTimeGetSeconds(loadedDuration)
            return seconds.isFinite && seconds > 0 ? seconds : nil
        }

        let rawCandidates = [
            max(0, positionSeconds),
            max(0, positionSeconds - 1.2),
            max(0, positionSeconds - 0.4),
            max(0, positionSeconds + 0.4),
            max(0, positionSeconds + 1.2),
            0.8,
            0
        ]

        var seen = Set<Int>()
        return rawCandidates.compactMap { rawValue in
            let clampedValue: Double
            if let normalizedDuration {
                clampedValue = min(max(0, rawValue), max(normalizedDuration - 0.2, 0))
            } else {
                clampedValue = max(0, rawValue)
            }

            let key = Int((clampedValue * 10).rounded())
            guard seen.insert(key).inserted else { return nil }
            return clampedValue
        }
    }

    private static func imageCost(for image: UIImage) -> Int {
        Int(image.size.width * image.scale * image.size.height * image.scale * 4)
    }
}

private struct HiddenJavDBFavoriteMovieTile: View {
    let movie: HiddenJavDBMovie
    let detail: HiddenJavDBMovieDetail?
    let errorMessage: String?
    let isLoadingDetail: Bool
    let showDetails: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncCoverImage(url: movie.coverURL)
                .frame(height: 126)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(movie.code)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(movie.displayTitle)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)

            if showDetails {
                if isLoadingDetail {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let detail {
                    Text(detail.actressesText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

private struct HiddenJavDBRandomListMovieTile: View {
    let movie: HiddenJavDBMovie
    let isFavorite: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AsyncCoverImage(url: movie.coverURL, fitToContainer: true)
                .frame(maxWidth: .infinity)
                .frame(height: 226)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if isFavorite {
                Image(systemName: "heart.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(Color.black.opacity(0.45), in: Circle())
                    .padding(8)
            }

            HStack {
                Text(movie.code)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.45), in: Capsule())
                    .padding(8)
                Spacer()
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct HiddenJavDBWatchSite: Identifiable, Hashable {
    enum LaunchMode: Equatable {
        case nativeStream
        case embeddedWeb
        case external
    }

    let name: String
    let urlTemplate: String
    var id: String { name }

    static let defaultSites: [HiddenJavDBWatchSite] = [
        HiddenJavDBWatchSite(name: "MISSAV", urlTemplate: "https://missav.ws/{{code}}/"),
        HiddenJavDBWatchSite(name: "Jable", urlTemplate: "https://jable.tv/search/{{code}}/")
    ]

    var launchMode: LaunchMode {
        switch name {
        case "MISSAV", "Jable":
            return .nativeStream
        case "Jav.Guru":
            return .embeddedWeb
        default:
            return .external
        }
    }

    func url(for rawCode: String) -> URL? {
        let code = HiddenJavDBWatchSite.normalizedCode(rawCode)
        guard !code.isEmpty else { return nil }
        let formattedCode: String
        if name == "FANZA 動画" {
            formattedCode = HiddenJavDBWatchSite.fanzaCode(from: code)
        } else if name == "JavBus" && code.uppercased().hasPrefix("MIUM") {
            formattedCode = "300" + code
        } else {
            formattedCode = code
        }
        let urlString = urlTemplate.replacingOccurrences(of: "{{code}}", with: formattedCode)
        return URL(string: urlString)
    }

    private static func normalizedCode(_ rawCode: String) -> String {
        rawCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .uppercased()
    }

    private static func fanzaCode(from code: String) -> String {
        let parts = code.split(separator: "-", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return code.lowercased() }
        let prefix = parts[0].lowercased()
        let numberPart = parts[1]
        let number = numberPart.count < 5
            ? String(repeating: "0", count: 5 - numberPart.count) + numberPart
            : numberPart
        if prefix.hasPrefix("start") {
            return "1\(prefix)\(number)"
        }
        return "\(prefix)\(number)"
    }
}

private struct HiddenInAppPlayerItem: Identifiable {
    let movie: HiddenJavDBMovie
    let sourceName: String
    let streamURL: URL
    let refererURL: URL
    let startPositionSeconds: Double
    let markerPositions: [Double]
    let id = UUID()
}

private struct HiddenInAppWebPageItem: Identifiable {
    let title: String
    let url: URL
    let id = UUID()
}

private enum HiddenMissAVModule {
    static let homeURL = URL(string: "https://missav.ws")!

    static func pageURL(for rawCode: String) -> URL? {
        HiddenJavDBWatchSite.defaultSites
            .first(where: { $0.name == "MISSAV" })?
            .url(for: rawCode)
    }
}

private struct HiddenInAppVideoPlayerView: View {
    let item: HiddenInAppPlayerItem
    let onSaveFavoritePlayback: (HiddenJavDBFavoritePlayback) -> HiddenJavDBFavoritePlaybackSaveContext
    let onUndoFavoritePlaybackSave: (HiddenJavDBFavoritePlaybackSaveContext) -> [Double]

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer
    @State private var playbackRate: Float = 1.0
    @State private var isMuted = true
    @State private var showUnmuteConfirm = false
    @State private var isPlaying = true
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isScrubbing = false
    @State private var scrubPosition: Double = 0
    @State private var isProgrammaticSeeking = false
    @State private var controlsVisible = true
    @State private var controlsAutoHideTask: Task<Void, Never>?
    @State private var seekTask: Task<Void, Never>?
    @State private var favoriteSaveResetTask: Task<Void, Never>?
    @State private var recentlySavedPlaybackContext: HiddenJavDBFavoritePlaybackSaveContext?
    @State private var recentlySavedPosition: Double?
    @State private var favoriteUndoCountdown = 0
    @State private var activeHoldPlaybackRate: Float?
    @State private var didApplyInitialStartPosition = false
    @State private var markerPositions: [Double]

    private let temporaryBoostRate: Float = 3.0

    init(
        item: HiddenInAppPlayerItem,
        onSaveFavoritePlayback: @escaping (HiddenJavDBFavoritePlayback) -> HiddenJavDBFavoritePlaybackSaveContext,
        onUndoFavoritePlaybackSave: @escaping (HiddenJavDBFavoritePlaybackSaveContext) -> [Double]
    ) {
        self.item = item
        self.onSaveFavoritePlayback = onSaveFavoritePlayback
        self.onUndoFavoritePlaybackSave = onUndoFavoritePlaybackSave

        let headers: [String: String] = [
            "Referer": item.refererURL.absoluteString,
            "Origin": "\(item.refererURL.scheme ?? "https")://\(item.refererURL.host ?? "missav.ws")",
            "User-Agent": HiddenJavDBAPI.userAgent
        ]
        let asset = AVURLAsset(
            url: item.streamURL,
            options: [
                "AVURLAssetHTTPHeaderFieldsKey": headers
            ]
        )
        let playerItem = AVPlayerItem(asset: asset)
        _player = State(initialValue: AVPlayer(playerItem: playerItem))
        _markerPositions = State(initialValue: Self.normalizedMarkerPositions(item.markerPositions))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            HiddenAVPlayerContainerView(player: player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleControlsVisibility()
                }

            VStack(spacing: 0) {
                topOverlay
                Spacer()
                centerControls
                Spacer()
                bottomOverlay
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(controlsVisible ? 1 : 0)
            .allowsHitTesting(controlsVisible)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .onAppear {
            configureAudioSession()
            player.isMuted = true
            player.defaultRate = effectivePlaybackRate
            player.playImmediately(atRate: effectivePlaybackRate)
            syncPlaybackState()
            scheduleControlsAutoHide()
        }
        .onDisappear {
            seekTask?.cancel()
            controlsAutoHideTask?.cancel()
            favoriteSaveResetTask?.cancel()
            activeHoldPlaybackRate = nil
            player.pause()
        }
        .task(id: item.id) {
            await applyInitialStartPositionIfNeeded()
        }
        .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in
            syncPlaybackState()
        }
        .alert("开启声音", isPresented: $showUnmuteConfirm) {
            Button("取消", role: .cancel) {}
            Button("确认") {
                isMuted = false
                player.isMuted = false
                scheduleControlsAutoHide()
            }
        } message: {
            Text("播放器默认静音。确认后将开启声音。")
        }
    }

    private var topOverlay: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Color.black.opacity(0.72), Color.black.opacity(0.18), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 132)
            .overlay(alignment: .top) {
                HStack(alignment: .top, spacing: 12) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.14), in: Circle())
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.movie.displayTitle)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        HStack(spacing: 8) {
                            playerBadge(text: item.sourceName)
                            playerBadge(text: item.movie.code)
                            playerBadge(text: formattedRate(effectivePlaybackRate))
                            if !markerPositions.isEmpty {
                                playerBadge(text: "\(markerPositions.count) 个点")
                            }
                            if isMuted {
                                playerBadge(text: "静音")
                            }
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
            }
        }
        .allowsHitTesting(true)
    }

    private var centerControls: some View {
        HStack(spacing: 26) {
            largeCircleButton(systemImage: "gobackward.15") {
                seek(by: -15)
            }

            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 72, height: 72)
                    .background(Color.white, in: Circle())
                    .shadow(color: Color.black.opacity(0.35), radius: 18, y: 10)
            }
            .buttonStyle(.plain)

            largeCircleButton(systemImage: "goforward.15") {
                seek(by: 15)
            }
        }
    }

    private var bottomOverlay: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.2), Color.black.opacity(0.82)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 248)
            .overlay(alignment: .bottom) {
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        HStack {
                            Text(formattedDuration(isScrubbing ? scrubPosition : currentTime))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.88))
                            Spacer()
                            Text(formattedDuration(duration))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.88))
                        }

                        Slider(
                            value: Binding(
                                get: { isScrubbing ? scrubPosition : currentTime },
                                set: { scrubPosition = $0 }
                            ),
                            in: 0...max(duration, 1),
                            onEditingChanged: handleScrub(editing:)
                        )
                        .tint(.white)
                        .overlay {
                            HiddenPlaybackMarkerTrackView(
                                markerPositions: markerPositions,
                                duration: duration
                            )
                            .padding(.horizontal, 12)
                            .allowsHitTesting(false)
                        }
                    }

                    HStack(spacing: 10) {
                        compactSeekButton(title: "-1m", systemImage: "backward.fill") {
                            seek(by: -60)
                        }
                        compactSeekButton(title: "+1m", systemImage: "forward.fill") {
                            seek(by: 60)
                        }
                    }

                    HStack(spacing: 10) {
                        Button {
                            saveFavoritePlaybackPosition()
                        } label: {
                            Label(recentlySavedPlaybackContext == nil ? "喜欢此处" : "已记录", systemImage: recentlySavedPlaybackContext == nil ? "heart.fill" : "checkmark.circle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)

                        Button {
                            toggleMute()
                        } label: {
                            Label(isMuted ? "开启声音" : "静音", systemImage: isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)

                        Menu {
                            speedButton(rate: 0.5, title: "0.5x")
                            speedButton(rate: 1.0, title: "1x")
                            speedButton(rate: 2.0, title: "2x")
                            speedButton(rate: 4.0, title: "4x")
                            speedButton(rate: 10.0, title: "10x")
                        } label: {
                            Label("倍速 \(formattedRate(playbackRate))", systemImage: "speedometer")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.12), in: Capsule())
                        }

                        holdSpeedButton
                    }

                    if let recentlySavedPosition, recentlySavedPlaybackContext != nil {
                        HStack(spacing: 10) {
                            Text("已记录 \(HiddenPlaybackTimeFormatter.string(from: recentlySavedPosition))，\(max(favoriteUndoCountdown, 1)) 秒内可撤回")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.76))
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button("撤回") {
                                undoFavoritePlaybackSave()
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.14), in: Capsule())
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .allowsHitTesting(true)
    }

    @ViewBuilder
    private func playerBadge(text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private func largeCircleButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Color.black.opacity(0.42), in: Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var holdSpeedButton: some View {
        Text(activeHoldPlaybackRate == nil ? "按住 3x" : "3x 加速中")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(activeHoldPlaybackRate == nil ? Color.white.opacity(0.12) : Color.orange.opacity(0.72))
            )
            .contentShape(Capsule())
            .onLongPressGesture(minimumDuration: 0.08, maximumDistance: 36, pressing: handleTemporaryBoostPressingChanged) {}
    }

    @ViewBuilder
    private func speedButton(rate: Float, title: String) -> some View {
        Button {
            playbackRate = rate
            applyPlaybackRate()
        } label: {
            HStack {
                Text(title)
                if abs(playbackRate - rate) < 0.001 {
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    @ViewBuilder
    private func compactSeekButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func togglePlayback() {
        if isPlaying {
            player.pause()
            isPlaying = false
            controlsAutoHideTask?.cancel()
        } else {
            player.playImmediately(atRate: effectivePlaybackRate)
            isPlaying = true
            scheduleControlsAutoHide()
        }
    }

    private func toggleMute() {
        if isMuted {
            showUnmuteConfirm = true
        } else {
            isMuted = true
            player.isMuted = true
            scheduleControlsAutoHide()
        }
    }

    private func seek(by seconds: Double) {
        let baseTime = resolvedCurrentPlaybackTime
        guard baseTime.isFinite else { return }

        var target = max(0, baseTime + seconds)
        if duration.isFinite, duration > 0 {
            target = min(target, duration)
        }

        updateDisplayedPlaybackPosition(to: target)
        seekPlayer(to: target)
        showControlsTemporarily()
    }

    private func applyPlaybackRate() {
        setPlayerRate(effectivePlaybackRate)
        showControlsTemporarily()
    }

    private func formattedRate(_ value: Float) -> String {
        if abs(value - round(value)) < 0.001 {
            return "\(Int(round(value)))x"
        }
        return "\(value)x"
    }

    private func formattedDuration(_ seconds: Double) -> String {
        HiddenPlaybackTimeFormatter.string(from: seconds)
    }

    private func handleScrub(editing: Bool) {
        isScrubbing = editing

        if editing {
            seekTask?.cancel()
            isProgrammaticSeeking = false
            controlsAutoHideTask?.cancel()
            scrubPosition = currentTime
            return
        }

        let target = normalizedPlaybackTime(scrubPosition)
        updateDisplayedPlaybackPosition(to: target)
        seekPlayer(to: target)
    }

    private func syncPlaybackState() {
        let latestDuration = CMTimeGetSeconds(player.currentItem?.duration ?? .invalid)
        if latestDuration.isFinite, latestDuration > 0 {
            duration = latestDuration
        }

        let latestTime = CMTimeGetSeconds(player.currentTime())
        if latestTime.isFinite, !isProgrammaticSeeking {
            let normalizedTime = normalizedPlaybackTime(latestTime)
            currentTime = normalizedTime
            if !isScrubbing {
                scrubPosition = normalizedTime
            }
        }

        isPlaying = player.timeControlStatus == .playing
    }

    private func toggleControlsVisibility() {
        withAnimation(.easeInOut(duration: 0.2)) {
            controlsVisible.toggle()
        }

        if controlsVisible {
            scheduleControlsAutoHide()
        } else {
            controlsAutoHideTask?.cancel()
        }
    }

    private func showControlsTemporarily() {
        withAnimation(.easeInOut(duration: 0.2)) {
            controlsVisible = true
        }
        scheduleControlsAutoHide()
    }

    private func scheduleControlsAutoHide() {
        controlsAutoHideTask?.cancel()
        guard isPlaying, !isScrubbing, !isProgrammaticSeeking else { return }

        controlsAutoHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, isPlaying, !isScrubbing, !isProgrammaticSeeking else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                controlsVisible = false
            }
        }
    }

    @MainActor
    private func applyInitialStartPositionIfNeeded() async {
        guard !didApplyInitialStartPosition, item.startPositionSeconds > 0.5 else { return }
        didApplyInitialStartPosition = true

        let targetTime = CMTime(seconds: item.startPositionSeconds, preferredTimescale: 600)
        isProgrammaticSeeking = true
        for _ in 0..<20 {
            if Task.isCancelled {
                isProgrammaticSeeking = false
                return
            }

            if player.currentItem?.status == .readyToPlay {
                await player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
                updateDisplayedPlaybackPosition(to: item.startPositionSeconds)
                isProgrammaticSeeking = false
                return
            }

            try? await Task.sleep(nanoseconds: 150_000_000)
        }

        await player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
        updateDisplayedPlaybackPosition(to: item.startPositionSeconds)
        isProgrammaticSeeking = false
    }

    private func saveFavoritePlaybackPosition() {
        let latestTime = isScrubbing ? scrubPosition : currentTime
        let positionSeconds = max(0, latestTime.isFinite ? latestTime : CMTimeGetSeconds(player.currentTime()))
        let playback = HiddenJavDBFavoritePlayback(
            movie: item.movie,
            sourceName: item.sourceName,
            streamURL: item.streamURL,
            refererURL: item.refererURL,
            positionSeconds: positionSeconds
        )

        let saveContext = onSaveFavoritePlayback(playback)
        markerPositions = Self.normalizedMarkerPositions(saveContext.markerPositions)
        recentlySavedPlaybackContext = saveContext
        recentlySavedPosition = saveContext.savedPlayback.positionSeconds
        scheduleFavoriteUndoCountdown()
        showControlsTemporarily()
    }

    private var effectivePlaybackRate: Float {
        activeHoldPlaybackRate ?? playbackRate
    }

    private var resolvedCurrentPlaybackTime: Double {
        let candidate = isScrubbing ? scrubPosition : currentTime
        if candidate.isFinite {
            return normalizedPlaybackTime(candidate)
        }
        return normalizedPlaybackTime(CMTimeGetSeconds(player.currentTime()))
    }

    private func normalizedPlaybackTime(_ value: Double) -> Double {
        let nonNegativeValue = max(0, value.isFinite ? value : 0)
        guard duration.isFinite, duration > 0 else { return nonNegativeValue }
        return min(nonNegativeValue, duration)
    }

    private func updateDisplayedPlaybackPosition(to value: Double) {
        let normalizedValue = normalizedPlaybackTime(value)
        currentTime = normalizedValue
        scrubPosition = normalizedValue
    }

    private func seekPlayer(to target: Double) {
        seekTask?.cancel()
        isProgrammaticSeeking = true

        let targetTime = CMTime(seconds: target, preferredTimescale: 600)
        let resumePlayback = isPlaying
        let rateAfterSeek = effectivePlaybackRate

        seekTask = Task { @MainActor in
            await player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
            guard !Task.isCancelled else { return }

            updateDisplayedPlaybackPosition(to: target)
            isProgrammaticSeeking = false

            if resumePlayback {
                player.playImmediately(atRate: rateAfterSeek)
            }
            scheduleControlsAutoHide()
        }
    }

    private func setPlayerRate(_ rate: Float) {
        player.defaultRate = rate
        if player.timeControlStatus == .playing {
            player.rate = rate
        }
    }

    private func handleTemporaryBoostPressingChanged(_ isPressing: Bool) {
        if isPressing {
            beginTemporarySpeedBoost()
        } else {
            endTemporarySpeedBoostIfNeeded()
        }
    }

    private func beginTemporarySpeedBoost() {
        guard activeHoldPlaybackRate == nil else { return }
        activeHoldPlaybackRate = max(playbackRate, temporaryBoostRate)
        setPlayerRate(effectivePlaybackRate)
        showControlsTemporarily()
    }

    private func endTemporarySpeedBoostIfNeeded() {
        guard activeHoldPlaybackRate != nil else { return }
        activeHoldPlaybackRate = nil
        setPlayerRate(playbackRate)
        showControlsTemporarily()
    }

    private func scheduleFavoriteUndoCountdown() {
        favoriteSaveResetTask?.cancel()
        favoriteUndoCountdown = 3

        favoriteSaveResetTask = Task { @MainActor in
            for remaining in stride(from: 3, through: 1, by: -1) {
                favoriteUndoCountdown = remaining
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
            }

            recentlySavedPlaybackContext = nil
            recentlySavedPosition = nil
            favoriteUndoCountdown = 0
        }
    }

    private func undoFavoritePlaybackSave() {
        guard let context = recentlySavedPlaybackContext else { return }
        markerPositions = Self.normalizedMarkerPositions(onUndoFavoritePlaybackSave(context))
        recentlySavedPlaybackContext = nil
        recentlySavedPosition = nil
        favoriteUndoCountdown = 0
        favoriteSaveResetTask?.cancel()
        showControlsTemporarily()
    }

    private static func normalizedMarkerPositions(_ positions: [Double]) -> [Double] {
        let sorted = positions
            .filter { $0.isFinite && $0 >= 0 }
            .sorted()

        var normalized: [Double] = []
        normalized.reserveCapacity(sorted.count)

        for position in sorted {
            if let last = normalized.last, abs(last - position) < 2 {
                continue
            }
            normalized.append(position)
        }

        return normalized
    }
}

private struct HiddenPlaybackMarkerTrackView: View {
    let markerPositions: [Double]
    let duration: Double

    var body: some View {
        GeometryReader { geometry in
            if duration.isFinite, duration > 0 {
                ForEach(Array(normalizedFractions.enumerated()), id: \.offset) { _, fraction in
                    Capsule(style: .continuous)
                        .fill(Color.pink.opacity(0.95))
                        .frame(width: 3, height: 10)
                        .shadow(color: Color.black.opacity(0.32), radius: 2, y: 1)
                        .position(
                            x: max(1.5, min(geometry.size.width - 1.5, geometry.size.width * fraction)),
                            y: geometry.size.height / 2
                        )
                }
            }
        }
    }

    private var normalizedFractions: [Double] {
        guard duration.isFinite, duration > 0 else { return [] }
        return markerPositions.compactMap { position in
            guard position.isFinite, position >= 0 else { return nil }
            return min(max(position / duration, 0), 1)
        }
    }
}

private final class HiddenInAppWebViewState: ObservableObject {
    @Published var progress: Double = 0
    @Published var isLoading = true
    @Published var pageTitle = ""
    @Published var currentURL: URL?
    @Published var reloadToken = UUID()
}

private struct HiddenInAppWebPageView: View {
    let item: HiddenInAppWebPageItem

    @Environment(\.dismiss) private var dismiss
    @StateObject private var webState = HiddenInAppWebViewState()

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            HiddenInAppWebBrowserView(url: item.url, state: webState)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.black.opacity(0.82), Color.black.opacity(0.2), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 136)
                .overlay(alignment: .top) {
                    VStack(spacing: 10) {
                        HStack(spacing: 12) {
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 40, height: 40)
                                    .background(Color.white.opacity(0.14), in: Circle())
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)

                                Text(webState.pageTitle.nonEmpty ?? webState.currentURL?.host ?? item.url.host ?? item.url.absoluteString)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.72))
                                    .lineLimit(1)
                            }

                            Spacer()

                            Button {
                                webState.reloadToken = UUID()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 40, height: 40)
                                    .background(Color.white.opacity(0.14), in: Circle())
                            }
                            .buttonStyle(.plain)

                            Link(destination: webState.currentURL ?? item.url) {
                                Image(systemName: "safari")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 40, height: 40)
                                    .background(Color.white.opacity(0.14), in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)

                        if webState.isLoading {
                            ProgressView(value: webState.progress)
                                .tint(.white)
                                .padding(.horizontal, 16)
                        }
                    }
                }

                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
    }
}

private struct HiddenInAppWebBrowserView: UIViewRepresentable {
    let url: URL
    @ObservedObject var state: HiddenInAppWebViewState

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = HiddenJavDBAPI.userAgent
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        context.coordinator.attachObservers(to: webView)
        context.coordinator.load(url: url, in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.loadedURLString != url.absoluteString {
            context.coordinator.load(url: url, in: webView)
        }

        if context.coordinator.reloadToken != state.reloadToken {
            context.coordinator.reloadToken = state.reloadToken
            webView.reload()
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let state: HiddenInAppWebViewState
        var loadedURLString: String?
        var reloadToken = UUID()
        private var progressObservation: NSKeyValueObservation?
        private var titleObservation: NSKeyValueObservation?
        private var urlObservation: NSKeyValueObservation?

        init(state: HiddenInAppWebViewState) {
            self.state = state
        }

        func attachObservers(to webView: WKWebView) {
            progressObservation = webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.state.progress = webView.estimatedProgress
                }
            }
            titleObservation = webView.observe(\.title, options: [.initial, .new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.state.pageTitle = webView.title ?? ""
                }
            }
            urlObservation = webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.state.currentURL = webView.url
                }
            }
        }

        func load(url: URL, in webView: WKWebView) {
            loadedURLString = url.absoluteString
            state.isLoading = true
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            request.setValue(HiddenJavDBAPI.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("zh-CN,zh;q=0.9,en;q=0.7", forHTTPHeaderField: "Accept-Language")
            webView.load(request)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            state.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            state.isLoading = false
            state.progress = 1
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            state.isLoading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            state.isLoading = false
        }
    }
}

private struct HiddenAVPlayerContainerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect
        controller.allowsPictureInPicturePlayback = false
        controller.updatesNowPlayingInfoCenter = false
        controller.view.backgroundColor = .black
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }
}

private struct HiddenJavDBImagePreviewView: View {
    let imageURLs: [URL]

    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int

    init(imageURLs: [URL], initialIndex: Int) {
        self.imageURLs = imageURLs
        let safeIndex = min(max(initialIndex, 0), max(imageURLs.count - 1, 0))
        _currentIndex = State(initialValue: safeIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if imageURLs.isEmpty {
                Text("没有可显示的图片")
                    .foregroundStyle(.white.opacity(0.85))
            } else {
                TabView(selection: $currentIndex) {
                    ForEach(Array(imageURLs.enumerated()), id: \.offset) { index, imageURL in
                        GeometryReader { proxy in
                            AsyncImage(url: imageURL) { phase in
                                switch phase {
                                case let .success(image):
                                    image
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: proxy.size.width, height: proxy.size.height)
                                case .empty:
                                    ProgressView()
                                        .frame(width: proxy.size.width, height: proxy.size.height)
                                case .failure:
                                    VStack(spacing: 10) {
                                        Image(systemName: "photo")
                                            .font(.system(size: 24, weight: .semibold))
                                        Text("图片加载失败")
                                    }
                                    .foregroundStyle(.white.opacity(0.85))
                                    .frame(width: proxy.size.width, height: proxy.size.height)
                                @unknown default:
                                    EmptyView()
                                }
                            }
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
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
    }
}

private enum HiddenJavDBRandomMode: String, CaseIterable, Identifiable {
    case single
    case nine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .single:
            return "随机 1 部"
        case .nine:
            return "随机 9 部"
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
            return "正在抓取随机影片..."
        case .nine:
            return "正在抓取随机 9 部..."
        }
    }
}

@MainActor
private final class HiddenJavDBViewModel: ObservableObject {
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

    var randomMovie: HiddenJavDBMovie? { randomMovies.first }

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

    func loadRandomMovieIfNeeded(mode: HiddenJavDBRandomMode) async {
        guard randomMovies.isEmpty else { return }
        await loadRandomMovies(mode: mode)
    }

    func loadRandomMovies(mode: HiddenJavDBRandomMode) async {
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
            switch mode {
            case .single:
                randomMovies = try await fetchRandomMovies(count: mode.requestCount)
            case .nine:
                try await fetchRandomMoviesProgressively(count: mode.requestCount, sessionID: sessionID)
            }
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
        await syncCloudNow(reason: "云端同步完成")
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

    private func fetchRandomMovies(count: Int) async throws -> [HiddenJavDBMovie] {
        var movies: [HiddenJavDBMovie] = []
        var seen = Set<String>()
        var attempts = 0
        let maxAttempts = max(18, count * 12)

        while movies.count < count && attempts < maxAttempts {
            attempts += 1
            let result = try await HiddenJavDBAPI.fetchRandomMovie(knownTotalPages: cachedTotalPages)
            cachedTotalPages = result.totalPages

            let movie = result.movie
            if seen.insert(movie.id).inserted {
                movies.append(movie)
            }
        }

        guard !movies.isEmpty else {
            throw NSError(
                domain: "HiddenJavDBViewModel",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "没有拿到可用影片，请重试"]
            )
        }

        return movies
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

            let mergedFavorites = mergeMovies(primary: remoteFavorites, secondary: favoriteMovies)
            let mergedPlaybacks = mergePlaybacks(primary: remotePlaybacks, secondary: favoritePlaybacks)

            favoriteMovies = mergedFavorites
            favoritePlaybacks = mergedPlaybacks
            saveFavoriteMovies()
            saveFavoritePlaybacks()

            try await cloudService.upsertFavorites(mergedFavorites)
            try await cloudService.upsertPlaybacks(mergedPlaybacks)

            cloudStatusMessage = "\(reason) · 影片 \(favoriteMovies.count) 部 · 播放点 \(favoritePlaybacks.count) 条"
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

    private func mergeMovies(primary: [HiddenJavDBMovie], secondary: [HiddenJavDBMovie]) -> [HiddenJavDBMovie] {
        var seen = Set<String>()
        var merged: [HiddenJavDBMovie] = []

        for movie in primary + secondary {
            if seen.insert(movie.id).inserted {
                merged.append(movie)
            }
        }

        return merged
    }

    private func mergePlaybacks(
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

private struct HiddenSupabaseConfiguration {
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
            .nonEmpty) ?? "easysearch"

        return HiddenSupabaseConfiguration(
            baseURL: baseURL,
            publishableKey: rawKey,
            schema: schema
        )
    }
}

private enum HiddenSupabaseAuthOutcome {
    case authenticated(HiddenSupabaseSession)
    case confirmationRequired(String)
}

private struct HiddenSupabaseSession: Codable {
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
            url: HiddenJavDBAPI.normalizeMovieURL(movieURL),
            code: code,
            title: title,
            coverURL: HiddenJavDBAPI.normalizeImageURL(coverURL),
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
                url: HiddenJavDBAPI.normalizeMovieURL(movieURL),
                code: code,
                title: title,
                coverURL: HiddenJavDBAPI.normalizeImageURL(coverURL),
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
            url: HiddenSpaceAPI.normalizeAlbumURL(albumURL),
            title: title,
            coverURL: HiddenSpaceAPI.normalizeImageURL(coverURL)
        )
    }
}

private struct HiddenSupabase4KHDImageRow: Decodable {
    let image_id: String
    let image_url: String

    func asImageURL() -> URL? {
        URL(string: image_url).map(HiddenSpaceAPI.normalizeImageURL)
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
        let normalized = HiddenSpaceAPI.normalizeImageURL(imageURL)
        image_id = normalized.absoluteString
        image_url = normalized.absoluteString
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

private actor HiddenSupabaseService {
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
            let message = payload?.resolvedMessage?.nonEmpty ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)

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

        let nestedSession = object["session"] as? [String: Any]
        let accessToken = (object["access_token"] as? String) ?? (nestedSession?["access_token"] as? String)
        guard let accessToken = accessToken?.nonEmpty else {
            return nil
        }

        let refreshToken = ((object["refresh_token"] as? String) ?? (nestedSession?["refresh_token"] as? String)) ?? ""
        let user = (object["user"] as? [String: Any]) ?? (nestedSession?["user"] as? [String: Any])
        let email = user?["email"] as? String
        let userID = (user?["id"] as? String).flatMap(UUID.init(uuidString:))

        let expiresAt = parseExpirationDate(root: object, nestedSession: nestedSession)
        return HiddenSupabaseSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            userID: userID,
            email: email
        )
    }

    private func parseExpirationDate(root: [String: Any], nestedSession: [String: Any]?) -> Date {
        if let timestamp = (root["expires_at"] as? TimeInterval) ?? (nestedSession?["expires_at"] as? TimeInterval) {
            return Date(timeIntervalSince1970: timestamp)
        }

        if let seconds = (root["expires_in"] as? TimeInterval) ?? (nestedSession?["expires_in"] as? TimeInterval) {
            return Date().addingTimeInterval(seconds)
        }

        return Date().addingTimeInterval(3600)
    }
}

private extension Error {
    var isHiddenSupabaseAuthFailure: Bool {
        let nsError = self as NSError
        guard nsError.domain == "HiddenSupabaseService" else {
            return false
        }

        return nsError.code == -2 || nsError.code == 401 || nsError.code == 403
    }
}

private enum Hidden4KHDLocalStore {
    static let favoriteAlbumsKey = "hidden_space.favorite_albums.v1"
    static let favoriteImagesKey = "hidden_space.favorite_images.v1"

    static func loadFavoriteAlbums() -> [HiddenAlbum] {
        guard let data = UserDefaults.standard.data(forKey: favoriteAlbumsKey),
              let albums = try? JSONDecoder().decode([HiddenAlbum].self, from: data) else {
            return []
        }

        return albums.map { album in
            HiddenAlbum(
                url: HiddenSpaceAPI.normalizeAlbumURL(album.url),
                title: album.title,
                coverURL: HiddenSpaceAPI.normalizeImageURL(album.coverURL)
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
                .map(HiddenSpaceAPI.normalizeImageURL)
        }

        if let urls = try? JSONDecoder().decode([URL].self, from: data) {
            let normalized = urls.map(HiddenSpaceAPI.normalizeImageURL)
            saveFavoriteImages(normalized)
            return normalized
        }

        return []
    }

    static func saveFavoriteImages(_ imageURLs: [URL]) {
        let payload = imageURLs.map { HiddenSpaceAPI.normalizeImageURL($0).absoluteString }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: favoriteImagesKey)
    }
}

private enum HiddenJavDBLocalStore {
    static let favoriteMoviesKey = "hidden_space.javdb.favorite_movies.v1"
    static let favoritePlaybacksKey = "hidden_space.javdb.favorite_playbacks.v1"

    static func loadFavoriteMovies() -> [HiddenJavDBMovie] {
        guard let data = UserDefaults.standard.data(forKey: favoriteMoviesKey),
              let movies = try? JSONDecoder().decode([HiddenJavDBMovie].self, from: data) else {
            return []
        }

        return movies.map { movie in
            HiddenJavDBMovie(
                url: HiddenJavDBAPI.normalizeMovieURL(movie.url),
                code: movie.code,
                title: movie.title,
                coverURL: HiddenJavDBAPI.normalizeImageURL(movie.coverURL),
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
                    url: HiddenJavDBAPI.normalizeMovieURL(playback.movie.url),
                    code: playback.movie.code,
                    title: playback.movie.title,
                    coverURL: HiddenJavDBAPI.normalizeImageURL(playback.movie.coverURL),
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

    private func syncNow(reason: String) async {
        guard isCloudAuthenticated else { return }

        isCloudBusy = true
        defer { isCloudBusy = false }

        do {
            let localJavPlaybacks = HiddenJavDBLocalStore.loadFavoritePlaybacks()
            let ensuredLocalJavFavorites = mergeMovies(
                primary: HiddenJavDBLocalStore.loadFavoriteMovies(),
                secondary: localJavPlaybacks.map(\.movie)
            )
            let local4KHDAlbums = Hidden4KHDLocalStore.loadFavoriteAlbums()
            let local4KHDImages = Hidden4KHDLocalStore.loadFavoriteImages()

            let remoteJavFavorites = try await cloudService.fetchFavorites()
            let remoteJavPlaybacks = try await cloudService.fetchPlaybacks()
            let remote4KHDAlbums = try await cloudService.fetch4KHDAlbums()
            let remote4KHDImages = try await cloudService.fetch4KHDImages()

            let mergedJavFavorites = mergeMovies(primary: remoteJavFavorites, secondary: ensuredLocalJavFavorites)
            let mergedJavPlaybacks = mergePlaybacks(primary: remoteJavPlaybacks, secondary: localJavPlaybacks)
            let merged4KHDAlbums = mergeAlbums(primary: remote4KHDAlbums, secondary: local4KHDAlbums)
            let merged4KHDImages = mergeImageURLs(primary: remote4KHDImages, secondary: local4KHDImages)

            HiddenJavDBLocalStore.saveFavoriteMovies(mergedJavFavorites)
            HiddenJavDBLocalStore.saveFavoritePlaybacks(mergedJavPlaybacks)
            Hidden4KHDLocalStore.saveFavoriteAlbums(merged4KHDAlbums)
            Hidden4KHDLocalStore.saveFavoriteImages(merged4KHDImages)

            try await cloudService.upsertFavorites(mergedJavFavorites)
            try await cloudService.upsertPlaybacks(mergedJavPlaybacks)
            try await cloudService.upsert4KHDAlbums(merged4KHDAlbums)
            try await cloudService.upsert4KHDImages(merged4KHDImages)

            cloudStatusMessage = "\(reason) · jav 影片 \(mergedJavFavorites.count) 部 · jav 播放点 \(mergedJavPlaybacks.count) 条 · 4khd album \(merged4KHDAlbums.count) 个 · 图片 \(merged4KHDImages.count) 张"
        } catch {
            if error.isHiddenSupabaseAuthFailure {
                isCloudAuthenticated = false
                didPrepareCloud = false
            }
            cloudStatusMessage = "云端同步失败：\(error.localizedDescription)"
        }
    }

    private func applySession(_ session: HiddenSupabaseSession) {
        isCloudAuthenticated = true
        cloudUserEmail = session.email
        cloudStatusMessage = session.email?.nonEmpty.map { "已登录 \($0)" } ?? "已登录云端同步"
    }

    private func mergeAlbums(primary: [HiddenAlbum], secondary: [HiddenAlbum]) -> [HiddenAlbum] {
        var seen = Set<String>()
        var merged: [HiddenAlbum] = []

        for album in primary + secondary {
            if seen.insert(album.id).inserted {
                merged.append(album)
            }
        }

        return merged
    }

    private func mergeImageURLs(primary: [URL], secondary: [URL]) -> [URL] {
        var seen = Set<String>()
        var merged: [URL] = []

        for url in (primary + secondary).map(HiddenSpaceAPI.normalizeImageURL) {
            if seen.insert(url.absoluteString).inserted {
                merged.append(url)
            }
        }

        return merged
    }

    private func mergeMovies(primary: [HiddenJavDBMovie], secondary: [HiddenJavDBMovie]) -> [HiddenJavDBMovie] {
        var seen = Set<String>()
        var merged: [HiddenJavDBMovie] = []

        for movie in primary + secondary {
            if seen.insert(movie.id).inserted {
                merged.append(movie)
            }
        }

        return merged
    }

    private func mergePlaybacks(
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
}

private struct HiddenJavDBMovie: Identifiable, Codable, Hashable {
    let url: URL
    let code: String
    let title: String
    let coverURL: URL
    let actresses: [String]

    var id: String { url.absoluteString }
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? code : trimmed
    }
    var actressesText: String {
        actresses.isEmpty ? "未知" : actresses.joined(separator: " / ")
    }
}

private struct HiddenJavDBMovieDetail: Hashable {
    let code: String
    let title: String
    let actresses: [String]
    let releaseDate: String?
    let durationMinutes: Int?
    let studio: String?
    let otherActressMovies: [HiddenJavDBMovie]
    let recommendedMovies: [HiddenJavDBMovie]

    var actressesText: String {
        actresses.isEmpty ? "未知" : actresses.joined(separator: " / ")
    }

    var durationText: String {
        guard let durationMinutes else { return "未知" }
        return "\(durationMinutes) 分钟"
    }
}

private struct HiddenJavDBFavoritePlayback: Identifiable, Codable, Hashable {
    let id: UUID
    let movie: HiddenJavDBMovie
    let sourceName: String
    let streamURL: URL
    let refererURL: URL
    let positionSeconds: Double
    let createdAt: Date

    init(
        id: UUID = UUID(),
        movie: HiddenJavDBMovie,
        sourceName: String,
        streamURL: URL,
        refererURL: URL,
        positionSeconds: Double,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.movie = movie
        self.sourceName = sourceName
        self.streamURL = streamURL
        self.refererURL = refererURL
        self.positionSeconds = positionSeconds
        self.createdAt = createdAt
    }
}

private struct HiddenJavDBFavoritePlaybackSaveContext {
    let savedPlayback: HiddenJavDBFavoritePlayback
    let replacedPlayback: HiddenJavDBFavoritePlayback?
    let markerPositions: [Double]
}

private extension HiddenJavDBFavoritePlayback {
    func matchesSamePlayback(as other: HiddenJavDBFavoritePlayback) -> Bool {
        movie.id == other.movie.id &&
        sourceName == other.sourceName &&
        streamURL.absoluteString == other.streamURL.absoluteString &&
        abs(positionSeconds - other.positionSeconds) < 2
    }
}

private enum HiddenPlaybackTimeFormatter {
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

private struct HiddenJavDBPreviewImage: Identifiable {
    let index: Int
    let urls: [URL]

    var id: String {
        guard !urls.isEmpty else { return "empty-\(index)" }
        let safeIndex = min(max(index, 0), urls.count - 1)
        return "\(safeIndex)-\(urls[safeIndex].absoluteString)"
    }
}

private enum HiddenJavDBWatchPlaybackTarget {
    case stream(URL, URL)
    case webPage(URL)
}

private enum HiddenJavDBAPI {
    private static let listingURL = URL(string: "https://javdb.com/?vft=1&vst=1")!
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile"
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = true
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        return URLSession(configuration: configuration)
    }()

    static func fetchRandomMovie(knownTotalPages: Int?) async throws -> (movie: HiddenJavDBMovie, totalPages: Int) {
        let totalPages = try await resolveTotalPages(knownTotalPages: knownTotalPages)

        var attempts = 0
        while attempts < 8 {
            attempts += 1
            let randomPage = Int.random(in: 1...max(totalPages, 1))
            let html = try await fetchHTML(from: listURL(page: randomPage))
            let movies = parseMovies(from: html)
            if let movie = movies.randomElement() {
                return (movie, totalPages)
            }
        }

        throw NSError(
            domain: "HiddenJavDBAPI",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "没有解析到可用影片，请重试"]
        )
    }

    static func fetchMovieImages(movieURL: URL) async throws -> [URL] {
        let html = try await fetchHTML(from: movieURL)
        let imageURLs = parseMovieImages(from: html)
        guard !imageURLs.isEmpty else {
            throw NSError(
                domain: "HiddenJavDBAPI",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "没有拿到截图列表"]
            )
        }
        return imageURLs
    }

    static func fetchMovieDetail(for movie: HiddenJavDBMovie) async throws -> HiddenJavDBMovieDetail {
        let html = try await fetchHTML(from: movie.url)

        let parsedTitle = firstNonEmpty([
            regexFirstCapture(pattern: #"<strong[^>]*class="[^"]*current-title[^"]*"[^>]*>(.*?)</strong>"#, in: html, dotMatchesLine: true),
            regexFirstCapture(pattern: #"<h2[^>]*class="[^"]*title[^"]*"[^>]*>(.*?)</h2>"#, in: html, dotMatchesLine: true),
            regexFirstCapture(pattern: #"<title>(.*?)</title>"#, in: html, dotMatchesLine: true)
        ]).map(cleanTitle)

        let parsedCode = firstNonEmpty([
            extractMetadataValue(labelKeywords: ["番號", "番号", "Code", "ID"], in: html),
            regexFirstCapture(pattern: #"<span[^>]*class="[^"]*video-id[^"]*"[^>]*>(.*?)</span>"#, in: html, dotMatchesLine: true)
        ]).map(cleanTitle)

        let actresses = parseActorNames(from: html)
        let releaseDate = firstNonEmpty([
            extractMetadataValue(labelKeywords: ["日期", "発行日", "Release Date"], in: html),
            regexFirstCapture(pattern: #"(20\d{2}[-/\.]\d{1,2}[-/\.]\d{1,2})"#, in: html, dotMatchesLine: false)
        ]).map(cleanTitle)

        let durationRaw = firstNonEmpty([
            extractMetadataValue(labelKeywords: ["片長", "长度", "Duration", "Length"], in: html),
            regexFirstCapture(pattern: #"(\d{2,3})\s*(?:分鐘|分钟|min)"#, in: html, dotMatchesLine: true)
        ]).map(cleanTitle)

        let durationMinutes: Int?
        if let durationRaw {
            durationMinutes = Int(regexFirstCapture(pattern: #"(\d{2,3})"#, in: durationRaw, dotMatchesLine: false) ?? "")
        } else {
            durationMinutes = nil
        }

        let studio = firstNonEmpty([
            extractMetadataValue(labelKeywords: ["片商", "メーカー", "Studio", "Maker"], in: html),
            extractMetadataValue(labelKeywords: ["发行", "Publisher", "Label"], in: html)
        ]).map(cleanTitle)
        let otherActressMovies = parseRelatedMovies(
            from: html,
            titleKeywords: ["她們還演出過", "她们还演出过", "她還演出過", "她还演出过"],
            excluding: movie
        )
        let recommendedMovies = parseRelatedMovies(
            from: html,
            titleKeywords: ["可能你也喜歡", "可能你也喜欢", "you may also like"],
            excluding: movie
        )

        return HiddenJavDBMovieDetail(
            code: parsedCode?.nonEmpty ?? movie.code,
            title: parsedTitle?.nonEmpty ?? movie.displayTitle,
            actresses: actresses.isEmpty ? movie.actresses : actresses,
            releaseDate: releaseDate?.nonEmpty,
            durationMinutes: durationMinutes,
            studio: studio?.nonEmpty,
            otherActressMovies: otherActressMovies,
            recommendedMovies: recommendedMovies
        )
    }

    static func searchMovies(query: String) async throws -> [HiddenJavDBMovie] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return [] }

        let html = try await fetchHTML(from: searchURL(query: normalizedQuery))
        return parseMovies(from: html)
    }

    static func resolvePlayableStream(for playback: HiddenJavDBFavoritePlayback) async throws -> (streamURL: URL, refererURL: URL) {
        for site in preferredPlayableSites(for: playback) {
            guard let pageURL = site.url(for: playback.movie.code) else { continue }

            do {
                let target = try await resolveWatchPlaybackTarget(for: site, pageURL: pageURL)
                if case let .stream(streamURL, refererURL) = target {
                    return (streamURL, refererURL)
                }
            } catch {
                continue
            }
        }

        return (playback.streamURL, playback.refererURL)
    }

    static func fetchMissAVPrimaryStreamURL(pageURL: URL) async throws -> URL {
        let html = try await fetchHTML(from: pageURL)
        guard let streamURL = extractMissAVStreamURL(from: html) else {
            throw NSError(
                domain: "HiddenJavDBAPI",
                code: -30,
                userInfo: [NSLocalizedDescriptionKey: "未解析到 MISSAV 视频流"]
            )
        }
        return streamURL
    }

    static func resolveWatchPlaybackTarget(for site: HiddenJavDBWatchSite, pageURL: URL) async throws -> HiddenJavDBWatchPlaybackTarget {
        switch site.launchMode {
        case .nativeStream:
            switch site.name {
            case "MISSAV":
                return .stream(try await fetchMissAVPrimaryStreamURL(pageURL: pageURL), pageURL)
            case "Jable":
                do {
                    let videoPageURL = try await resolveJableVideoPageURL(from: pageURL)
                    do {
                        let streamURL = try await fetchJablePrimaryStreamURL(pageURL: videoPageURL)
                        return .stream(streamURL, videoPageURL)
                    } catch {
                        return .webPage(videoPageURL)
                    }
                } catch {
                    return .webPage(pageURL)
                }
            default:
                throw NSError(
                    domain: "HiddenJavDBAPI",
                    code: -31,
                    userInfo: [NSLocalizedDescriptionKey: "暂不支持该站点的原生播放"]
                )
            }
        case .embeddedWeb:
            switch site.name {
            case "Jav.Guru":
                return .webPage(try await fetchJavGuruPreferredWebURL(searchPageURL: pageURL))
            default:
                return .webPage(pageURL)
            }
        case .external:
            throw NSError(
                domain: "HiddenJavDBAPI",
                code: -32,
                userInfo: [NSLocalizedDescriptionKey: "该站点仅支持外部打开"]
            )
        }
    }

    private static func resolveTotalPages(knownTotalPages: Int?) async throws -> Int {
        if let knownTotalPages, knownTotalPages > 0 {
            return knownTotalPages
        }

        let html = try await fetchHTML(from: listingURL)
        let queryPages = regexCaptureAll(pattern: #"(?:\?|&)page=(\d+)"#, in: html, dotMatchesLine: false)
            .compactMap { Int($0) }
        if let maxQueryPage = queryPages.max(), maxQueryPage > 0 {
            return maxQueryPage
        }

        let normalPages = regexCaptureAll(pattern: #"/page/(\d+)"#, in: html, dotMatchesLine: false)
            .compactMap { Int($0) }
        if let maxNormalPage = normalPages.max(), maxNormalPage > 0 {
            return maxNormalPage
        }

        return 400
    }

    private static func fetchJablePrimaryStreamURL(pageURL: URL) async throws -> URL {
        let html = try await fetchHTML(from: pageURL)

        let directMatches = regexCaptureAll(
            pattern: #"var\s+hlsUrl\s*=\s*'([^']+)'"#,
            in: html,
            dotMatchesLine: true
        ) + regexCaptureAll(
            pattern: #"video\.src\s*=\s*'([^']+)'"#,
            in: html,
            dotMatchesLine: true
        ) + regexCaptureAll(
            pattern: #"(https?://[^"'\s]+\.m3u8(?:\?[^"'\s]*)?)"#,
            in: html,
            dotMatchesLine: true
        )

        if let streamURL = directMatches.compactMap(normalizedURL(from:)).first {
            return streamURL
        }

        throw NSError(
            domain: "HiddenJavDBAPI",
            code: -33,
            userInfo: [NSLocalizedDescriptionKey: "未解析到 Jable 视频流"]
        )
    }

    private static func resolveJableVideoPageURL(from pageURL: URL) async throws -> URL {
        if pageURL.path.contains("/videos/") {
            return pageURL
        }

        let searchHTML = try await fetchHTML(from: pageURL)
        if let videoURL = extractJableVideoPageURL(from: searchHTML, preferredCode: pageURL.lastPathComponent) {
            return videoURL
        }

        throw NSError(
            domain: "HiddenJavDBAPI",
            code: -34,
            userInfo: [NSLocalizedDescriptionKey: "未找到 Jable 影片页"]
        )
    }

    private static func extractJableVideoPageURL(from html: String, preferredCode: String) -> URL? {
        let rawMatches = regexCaptureAll(
            pattern: #"href=["'](https?://jable\.tv/videos/[^"']+|/videos/[^"']+)["']"#,
            in: html,
            dotMatchesLine: true
        )

        var seen = Set<String>()
        let candidates = rawMatches.compactMap { raw in
            normalizedExternalURL(from: raw, relativeTo: URL(string: "https://jable.tv")!)
        }.filter { url in
            seen.insert(url.absoluteString).inserted
        }

        let exactCode = preferredCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if !exactCode.isEmpty,
           let exactMatch = candidates.first(where: { $0.path.lowercased().contains("/videos/\(exactCode)/") }) {
            return exactMatch
        }

        return candidates.first
    }

    private static func fetchJavGuruPreferredWebURL(searchPageURL: URL) async throws -> URL {
        let searchHTML = try await fetchHTML(from: searchPageURL)
        let articleURL = extractJavGuruArticleURL(from: searchHTML) ?? searchPageURL

        let articleHTML = try await fetchHTML(from: articleURL)
        if let playerURL = extractJavGuruEmbeddedURL(from: articleHTML) {
            return playerURL
        }

        return articleURL
    }

    private static func listURL(page: Int) -> URL {
        guard page > 1 else { return listingURL }
        var components = URLComponents(url: listingURL, resolvingAgainstBaseURL: false)
        var items = components?.queryItems ?? []
        items.removeAll { $0.name == "page" }
        items.append(URLQueryItem(name: "page", value: "\(page)"))
        components?.queryItems = items
        return components?.url ?? listingURL
    }

    private static func searchURL(query: String) -> URL {
        var components = URLComponents(string: "https://javdb.com/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "f", value: "all")
        ]
        return components?.url ?? listingURL
    }

    private static func preferredPlayableSites(for playback: HiddenJavDBFavoritePlayback) -> [HiddenJavDBWatchSite] {
        let nativeSites = HiddenJavDBWatchSite.defaultSites.filter { $0.launchMode == .nativeStream }
        guard let preferredSite = nativeSites.first(where: { $0.name == playback.sourceName }) else {
            return nativeSites
        }

        return [preferredSite] + nativeSites.filter { $0.id != preferredSite.id }
    }

    private static func fetchHTML(from url: URL) async throws -> String {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpShouldHandleCookies = true
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.7", forHTTPHeaderField: "Accept-Language")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")

        if let cookies = HTTPCookieStorage.shared.cookies(for: url), !cookies.isEmpty {
            let header = HTTPCookie.requestHeaderFields(with: cookies)
            if let cookieField = header["Cookie"] {
                request.setValue(cookieField, forHTTPHeaderField: "Cookie")
            }
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "HiddenJavDBAPI",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "请求返回异常"]
            )
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 403 || httpResponse.statusCode == 503 {
                if let webHTML = try? await HiddenJavDBWebHTMLFetcher.shared.fetchHTML(from: url),
                   !isCloudflareChallengeHTML(webHTML) {
                    return webHTML
                }

                throw NSError(
                    domain: "HiddenJavDBAPI",
                    code: -4,
                    userInfo: [NSLocalizedDescriptionKey: "请求遇到验证页，请稍后重试"]
                )
            }

            throw NSError(
                domain: "HiddenJavDBAPI",
                code: -5,
                userInfo: [NSLocalizedDescriptionKey: "页面请求失败（\(httpResponse.statusCode)）"]
            )
        }

        let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .unicode)
            ?? ""

        if html.isEmpty {
            throw NSError(
                domain: "HiddenJavDBAPI",
                code: -6,
                userInfo: [NSLocalizedDescriptionKey: "页面解析失败"]
            )
        }

        if isCloudflareChallengeHTML(html) {
            if let webHTML = try? await HiddenJavDBWebHTMLFetcher.shared.fetchHTML(from: url),
               !isCloudflareChallengeHTML(webHTML) {
                return webHTML
            }

            throw NSError(
                domain: "HiddenJavDBAPI",
                code: -7,
                userInfo: [NSLocalizedDescriptionKey: "检测到验证页，请稍后重试"]
            )
        }

        return html
    }

    private static func parseMovies(from html: String) -> [HiddenJavDBMovie] {
        let blocks = regexCapturePairs(
            pattern: #"<a[^>]+href=["'](/v/[^"'?#]+)["'][^>]*>(.*?)</a>"#,
            in: html,
            dotMatchesLine: true
        )

        var movies: [HiddenJavDBMovie] = []
        var seen = Set<String>()

        for (rawLink, block) in blocks {
            guard block.range(of: "<img", options: .caseInsensitive) != nil,
                  let movieURL = normalizedURL(from: rawLink),
                  seen.insert(movieURL.absoluteString).inserted else {
                continue
            }

            let coverRaw = firstNonEmpty([
                regexFirstCapture(pattern: #"<img[^>]+data-src=["']([^"']+)["']"#, in: block, dotMatchesLine: true),
                regexFirstCapture(pattern: #"<img[^>]+src=["']([^"']+)["']"#, in: block, dotMatchesLine: true)
            ])

            guard let coverRaw,
                  let coverURL = normalizedURL(from: coverRaw) else {
                continue
            }

            let code = firstNonEmpty([
                regexFirstCapture(pattern: #"<strong[^>]*>(.*?)</strong>"#, in: block, dotMatchesLine: true),
                regexFirstCapture(pattern: #"<div[^>]*class=["'][^"']*uid[^"']*["'][^>]*>(.*?)</div>"#, in: block, dotMatchesLine: true)
            ]).map(cleanTitle)?.nonEmpty ?? movieURL.lastPathComponent.uppercased()

            let title = firstNonEmpty([
                regexFirstCapture(pattern: #"<div[^>]*class=["'][^"']*video-title[^"']*["'][^>]*>(.*?)</div>"#, in: block, dotMatchesLine: true),
                regexFirstCapture(pattern: #"<div[^>]*class=["'][^"']*title[^"']*["'][^>]*>(.*?)</div>"#, in: block, dotMatchesLine: true),
                regexFirstCapture(pattern: #"title=["']([^"']+)["']"#, in: block, dotMatchesLine: true)
            ]).map(cleanTitle)?.nonEmpty ?? code

            let actresses = parseActorNames(from: block)

            movies.append(
                HiddenJavDBMovie(
                    url: normalizeMovieURL(movieURL),
                    code: code,
                    title: title,
                    coverURL: normalizeImageURL(coverURL),
                    actresses: actresses
                )
            )
        }

        return movies
    }

    private static func parseRelatedMovies(
        from html: String,
        titleKeywords: [String],
        excluding currentMovie: HiddenJavDBMovie
    ) -> [HiddenJavDBMovie] {
        let normalizedKeywords = titleKeywords.map(normalizedSectionTitle)

        for block in regexFullMatches(pattern: #"<section\b[^>]*>.*?</section>"#, in: html, dotMatchesLine: true) {
            let normalizedBlock = normalizedSectionTitle(cleanTitle(block))
            guard normalizedKeywords.contains(where: { normalizedBlock.contains($0) }) else { continue }

            let movies = dedupedRelatedMovies(
                parseMovies(from: block).filter { $0.id != currentMovie.id }
            )
            if !movies.isEmpty {
                return movies
            }
        }

        for section in extractHeadingAnchoredSections(from: html) {
            let normalizedTitle = normalizedSectionTitle(section.title)
            guard normalizedKeywords.contains(where: { normalizedTitle.contains($0) }) else { continue }

            let movies = dedupedRelatedMovies(
                parseMovies(from: section.body).filter { $0.id != currentMovie.id }
            )
            if !movies.isEmpty {
                return movies
            }
        }

        return []
    }

    private static func parseMovieImages(from html: String) -> [URL] {
        let anchoredImages = dedupePreferredMovieSampleImages(
            extractAnchoredPreviewImageCandidates(from: html)
                .compactMap(normalizedURL(from:))
                .filter(isLikelyMovieSampleImageURL)
        )
        if !anchoredImages.isEmpty {
            return anchoredImages
        }

        let previewScopes = extractPreviewScopes(from: html)
        let scopedCandidates = previewScopes.flatMap(extractImageCandidates)
        let scopedImages = dedupePreferredMovieSampleImages(
            scopedCandidates.compactMap(normalizedURL(from:)).filter(isLikelyMovieSampleImageURL)
        )
        if !scopedImages.isEmpty {
            return scopedImages
        }

        let allCandidates = extractImageCandidates(from: html)
        let strictAll = dedupePreferredMovieSampleImages(
            allCandidates.compactMap(normalizedURL(from:)).filter(isLikelyMovieSampleImageURL)
        )
        if !strictAll.isEmpty {
            return strictAll
        }

        return dedupePreferredMovieSampleImages(
            allCandidates
                .compactMap(normalizedURL(from:))
                .filter(isLikelyImageURL)
                .filter { !isClearlyNonSampleImageURL($0) }
        )
    }

    private static func extractAnchoredPreviewImageCandidates(from html: String) -> [String] {
        let scopes = extractPreviewScopes(from: html)
        let scopedCandidates = scopes.flatMap { scope in
            regexCaptureAll(
                pattern: #"<a[^>]+href=["']([^"']+)["'][^>]*>(?:(?!</a>).)*?<img"#,
                in: scope,
                dotMatchesLine: true
            )
        }

        let pageLevelCandidates = regexCaptureAll(
            pattern: #"<a[^>]+href=["']([^"']+)["'][^>]*>(?:(?!</a>).)*?<img"#,
            in: html,
            dotMatchesLine: true
        )

        return scopedCandidates + pageLevelCandidates
    }

    private static func extractPreviewScopes(from html: String) -> [String] {
        var scopes: [String] = []

        let panelBlocks = regexCaptureAll(
            pattern: #"<(?:section|div)[^>]+class=["'][^"']*(?:preview-images|tile-images|samples|sample-waterfall)[^"']*["'][^>]*>(.*?)</(?:section|div)>"#,
            in: html,
            dotMatchesLine: true
        )
        scopes.append(contentsOf: panelBlocks)

        let idBlocks = regexCaptureAll(
            pattern: #"<(?:section|div)[^>]+id=["'][^"']*(?:preview|sample|screenshot)[^"']*["'][^>]*>(.*?)</(?:section|div)>"#,
            in: html,
            dotMatchesLine: true
        )
        scopes.append(contentsOf: idBlocks)

        return scopes
    }

    private static func extractImageCandidates(from html: String) -> [String] {
        let directURLs = regexCaptureAll(
            pattern: #"(?:href|src|data-src|data-lazy-src)=["']([^"']+)["']"#,
            in: html,
            dotMatchesLine: true
        )
        let srcsetValues = regexCaptureAll(
            pattern: #"(?:srcset|data-srcset)=["']([^"']+)["']"#,
            in: html,
            dotMatchesLine: true
        )
        return directURLs + srcsetValues.flatMap(extractURLsFromSrcset)
    }

    private static func dedupeImageURLs(_ urls: [URL]) -> [URL] {
        var deduped: [URL] = []
        var seen = Set<String>()
        for url in urls {
            let normalized = normalizeImageURL(url)
            if seen.insert(normalized.absoluteString).inserted {
                deduped.append(normalized)
            }
        }
        return deduped
    }

    private static func dedupePreferredMovieSampleImages(_ urls: [URL]) -> [URL] {
        struct Candidate {
            let url: URL
            let score: Int
        }

        var order: [String] = []
        var bestByKey: [String: Candidate] = [:]

        for rawURL in urls {
            let normalized = normalizeImageURL(rawURL)
            let key = canonicalMovieSampleImageKey(for: normalized)
            let score = movieSampleImageQualityScore(for: normalized)

            if let existing = bestByKey[key] {
                if score > existing.score {
                    bestByKey[key] = Candidate(url: normalized, score: score)
                }
            } else {
                order.append(key)
                bestByKey[key] = Candidate(url: normalized, score: score)
            }
        }

        return order.compactMap { bestByKey[$0]?.url }
    }

    private static func canonicalMovieSampleImageKey(for url: URL) -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString.lowercased()
        }

        let host = components.host?.lowercased() ?? ""
        let path = components.path.lowercased()
        let fileName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent

        var base = fileName
        base = base.replacingOccurrences(
            of: #"(?:[_-](?:blur|blurry|thumb|thumbnail|small|sm|mini|preview|low|lq|mq|sd|hd|orig|original|large|xl|xlarge))+$"#,
            with: "",
            options: .regularExpression
        )
        base = base.replacingOccurrences(
            of: #"(?:[_-]\d{2,4}x\d{2,4})+$"#,
            with: "",
            options: .regularExpression
        )

        if base.isEmpty {
            base = fileName
        }
        return "\(host)|\(base)"
    }

    private static func movieSampleImageQualityScore(for url: URL) -> Int {
        let value = url.absoluteString.lowercased()
        var score = 0

        if value.contains("/sample/") || value.contains("/samples/") || value.contains("/screenshots/") {
            score += 8
        }
        if value.contains("/thumb/") || value.contains("/thumbs/") {
            score -= 8
        }

        let positiveKeywords = [
            "original",
            "orig",
            "full",
            "large",
            "hq"
        ]
        for keyword in positiveKeywords where value.contains(keyword) {
            score += 2
        }

        let negativeKeywords = [
            "blur",
            "blurry",
            "thumb",
            "thumbnail",
            "small",
            "preview",
            "low",
            "lq",
            "placeholder",
            "sprite"
        ]
        for keyword in negativeKeywords where value.contains(keyword) {
            score -= 4
        }

        score += min(value.count / 40, 8)
        return score
    }

    private static func parseActorNames(from text: String) -> [String] {
        let names = regexCaptureAll(
            pattern: #"<a[^>]+href=["']/actors/[^"']+["'][^>]*>(.*?)</a>"#,
            in: text,
            dotMatchesLine: true
        ).map(cleanTitle).filter { !$0.isEmpty }

        var deduped: [String] = []
        var seen = Set<String>()
        for name in names where seen.insert(name).inserted {
            deduped.append(name)
        }
        return deduped
    }

    private static func extractMissAVStreamURL(from html: String) -> URL? {
        var candidates: [String] = []

        // Try direct URLs first.
        let direct = regexCaptureAll(
            pattern: #"(https?://[^"'\s]+\.m3u8(?:\?[^"'\s]*)?)"#,
            in: html,
            dotMatchesLine: true
        )
        candidates.append(contentsOf: direct)

        // MissAV often stores source URLs in P.A.C.K.E.R eval blocks.
        let decodedBlocks = decodeMissAVEvalBlocks(from: html)
        for block in decodedBlocks {
            let urls = regexCaptureAll(
                pattern: #"(https?://[^"'\s]+\.m3u8(?:\?[^"'\s]*)?)"#,
                in: block,
                dotMatchesLine: true
            )
            candidates.append(contentsOf: urls)
        }

        let normalized = candidates.compactMap(normalizedURL(from:))
        let prioritized = prioritizedMissAVStreamCandidates(normalized)
        return prioritized.first
    }

    private static func extractJavGuruArticleURL(from html: String) -> URL? {
        let candidates = regexCaptureAll(
            pattern: #"href=["'](https://jav\.guru/\d+/[^"'?#]+/?)["']"#,
            in: html,
            dotMatchesLine: true
        )

        return candidates.compactMap(normalizedURL(from:)).first
    }

    private static func extractJavGuruEmbeddedURL(from html: String) -> URL? {
        guard let encoded = regexFirstCapture(
            pattern: #""iframe_url":"([^"]+)""#,
            in: html,
            dotMatchesLine: true
        )?.nonEmpty else {
            return nil
        }

        let decoded = decodeBase64String(encoded)
        return decoded.flatMap(normalizedURL(from:))
    }

    private static func decodeMissAVEvalBlocks(from html: String) -> [String] {
        let pattern = #"eval\(function\(p,a,c,k,e,d\)\{.*?\}\('(.+?)',(\d+),(\d+),'(.+?)'\.split\('\|'\),0,\{\}\)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, options: [], range: range)

        var decoded: [String] = []
        for match in matches {
            guard match.numberOfRanges >= 5,
                  let payloadRange = Range(match.range(at: 1), in: html),
                  let baseRange = Range(match.range(at: 2), in: html),
                  let countRange = Range(match.range(at: 3), in: html),
                  let dictRange = Range(match.range(at: 4), in: html),
                  let base = Int(html[baseRange]),
                  let count = Int(html[countRange]) else {
                continue
            }
            guard base >= 2, base <= 36 else {
                continue
            }

            let payloadRaw = String(html[payloadRange])
            let payload = payloadRaw
                .replacingOccurrences(of: #"\'"#, with: "'")
                .replacingOccurrences(of: #"\\\\"#, with: #"\"#)
            let dictionary = String(html[dictRange]).split(separator: "|").map(String.init)
            decoded.append(unpackPAckerPayload(payload, base: base, count: count, dictionary: dictionary))
        }

        return decoded
    }

    private static func unpackPAckerPayload(_ payload: String, base: Int, count: Int, dictionary: [String]) -> String {
        guard base >= 2 else { return payload }

        var result = payload
        if count > 0 {
            for index in stride(from: count - 1, through: 0, by: -1) {
                guard index < dictionary.count else { continue }
                let replacement = dictionary[index]
                if replacement.isEmpty {
                    continue
                }
                let token = toBaseString(index, base: base)
                let escapedToken = NSRegularExpression.escapedPattern(for: token)
                result = result.replacingOccurrences(
                    of: "\\b\(escapedToken)\\b",
                    with: replacement,
                    options: [.regularExpression, .caseInsensitive]
                )
            }
        }

        return result.replacingOccurrences(of: #"\'"#, with: "'")
    }

    private static func toBaseString(_ value: Int, base: Int) -> String {
        guard base >= 2, base <= 36 else {
            return "\(value)"
        }
        if value == 0 {
            return "0"
        }

        let digits = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        var number = value
        var output = ""
        while number > 0 {
            let remainder = number % base
            output = String(digits[remainder]) + output
            number /= base
        }
        return output
    }

    private static func prioritizedMissAVStreamCandidates(_ urls: [URL]) -> [URL] {
        var unique: [URL] = []
        var seen = Set<String>()
        for url in urls {
            if seen.insert(url.absoluteString).inserted {
                unique.append(url)
            }
        }

        let filtered = unique.filter { url in
            let host = url.host?.lowercased() ?? ""
            let path = url.path.lowercased()
            guard path.hasSuffix(".m3u8") else { return false }
            return host.contains("surrit.com") || path.contains("/playlist")
        }

        let playlistFirst = filtered.sorted { lhs, rhs in
            let lPath = lhs.path.lowercased()
            let rPath = rhs.path.lowercased()
            let lScore = (lPath.contains("/playlist") ? 3 : 0) + (lPath.contains("/video/") ? 1 : 0)
            let rScore = (rPath.contains("/playlist") ? 3 : 0) + (rPath.contains("/video/") ? 1 : 0)
            return lScore > rScore
        }

        return playlistFirst.isEmpty ? unique : playlistFirst
    }

    private static func extractMetadataValue(labelKeywords: [String], in html: String) -> String? {
        for keyword in labelKeywords {
            let escaped = NSRegularExpression.escapedPattern(for: keyword)
            let patterns = [
                #"<strong[^>]*>[^<]*\#(escaped)[^<]*</strong>\s*<span[^>]*class="[^"]*value[^"]*"[^>]*>(.*?)</span>"#,
                #"<span[^>]*class="[^"]*meta[^"]*"[^>]*>[^<]*\#(escaped)[^<]*</span>\s*<span[^>]*class="[^"]*value[^"]*"[^>]*>(.*?)</span>"#,
                #"\#(escaped)[^<:：]{0,12}[:：]\s*</?[^>]*>\s*([^<]+)"#
            ]

            for pattern in patterns {
                if let value = regexFirstCapture(pattern: pattern, in: html, dotMatchesLine: true) {
                    let cleaned = cleanTitle(value)
                    if !cleaned.isEmpty {
                        return cleaned
                    }
                }
            }
        }
        return nil
    }

    private static func normalizedURL(from raw: String) -> URL? {
        let decoded = decodeHTMLEntities(raw)
            .replacingOccurrences(of: "&#038;", with: "&")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let url: URL?
        if decoded.hasPrefix("//") {
            url = URL(string: "https:" + decoded)
        } else if decoded.hasPrefix("/") {
            url = URL(string: "https://javdb.com" + decoded)
        } else {
            url = URL(string: decoded)
        }
        return url
    }

    private static func normalizedExternalURL(from raw: String, relativeTo baseURL: URL) -> URL? {
        let decoded = decodeHTMLEntities(raw)
            .replacingOccurrences(of: "&#038;", with: "&")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if decoded.hasPrefix("//") {
            return URL(string: "https:" + decoded)
        }
        if decoded.hasPrefix("/") {
            return URL(string: decoded, relativeTo: baseURL)?.absoluteURL
        }
        return URL(string: decoded)
    }

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

    private static func isCloudflareChallengeHTML(_ html: String) -> Bool {
        let lowered = html.lowercased()
        if lowered.contains("<title>just a moment") {
            return true
        }
        if lowered.contains("enable javascript and cookies to continue") {
            return true
        }
        if lowered.contains("cf_chl_opt") {
            return true
        }
        return lowered.contains("challenge-platform") && lowered.contains("cf-ray")
    }

    private static func isLikelyImageURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }

        let path = components.path.lowercased()
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "webp", "gif", "avif"].contains(ext) {
            return true
        }

        if path.contains("/samples/") || path.contains("/covers/") || path.contains("/thumbs/") {
            return true
        }

        return false
    }

    private static func isLikelyMovieSampleImageURL(_ url: URL) -> Bool {
        guard isLikelyImageURL(url),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }

        let path = components.path.lowercased()
        if isClearlyNonSampleImageURL(url) {
            return false
        }

        let positiveKeywords = [
            "/sample/",
            "/samples/",
            "/screenshot/",
            "/screenshots/",
            "/preview/",
            "/digital/video/",
            "/litevideo/freepv/",
            "sample-",
            "screenshot",
            "preview",
            "jp-"
        ]
        if positiveKeywords.contains(where: { path.contains($0) }) {
            return true
        }

        if regexFirstCapture(pattern: #"(?:-|_)(\d{1,2})\.(?:jpe?g|png|webp|avif|gif)$"#, in: path, dotMatchesLine: false) != nil {
            return true
        }

        return false
    }

    private static func isClearlyNonSampleImageURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        let path = components.path.lowercased()

        let blockedKeywords = [
            "/actors/",
            "/actor/",
            "/avatars/",
            "/avatar/",
            "/logo",
            "/icon",
            "/favicon",
            "/poster",
            "/cover",
            "/thumb",
            "/banner",
            "/ads/",
            "/emoji/"
        ]
        return blockedKeywords.contains(where: { path.contains($0) })
    }

    private static func extractURLsFromSrcset(_ srcset: String) -> [String] {
        srcset
            .split(separator: ",")
            .compactMap { candidate in
                candidate
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .split(separator: " ")
                    .first
                    .map(String.init)
            }
    }

    private static func cleanTitle(_ text: String) -> String {
        let stripped = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        let decoded = decodeHTMLEntities(stripped)
        let normalized = decoded.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.hasSuffix(" - JavDB") {
            return String(normalized.dropLast(" - JavDB".count))
        }
        return normalized
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        guard let data = text.data(using: .utf8) else { return text }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        if let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            return attributed.string
        }
        return text
    }

    private static func decodeBase64String(_ value: String) -> String? {
        guard let data = Data(base64Encoded: value) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func firstNonEmpty(_ values: [String?]) -> String? {
        for value in values {
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty else {
                continue
            }
            return trimmed
        }
        return nil
    }

    private static func regexFirstCapture(pattern: String, in text: String, dotMatchesLine: Bool) -> String? {
        regexCaptureAll(pattern: pattern, in: text, dotMatchesLine: dotMatchesLine).first
    }

    private static func regexCaptureAll(pattern: String, in text: String, dotMatchesLine: Bool) -> [String] {
        var options: NSRegularExpression.Options = [.caseInsensitive]
        if dotMatchesLine {
            options.insert(.dotMatchesLineSeparators)
        }

        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        return matches.compactMap { match in
            guard match.numberOfRanges > 1,
                  let captureRange = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return String(text[captureRange])
        }
    }

    private static func regexCapturePairs(pattern: String, in text: String, dotMatchesLine: Bool) -> [(String, String)] {
        var options: NSRegularExpression.Options = [.caseInsensitive]
        if dotMatchesLine {
            options.insert(.dotMatchesLineSeparators)
        }

        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        return matches.compactMap { match in
            guard match.numberOfRanges > 2,
                  let firstRange = Range(match.range(at: 1), in: text),
                  let secondRange = Range(match.range(at: 2), in: text) else {
                return nil
            }
            return (String(text[firstRange]), String(text[secondRange]))
        }
    }

    private static func regexFullMatches(pattern: String, in text: String, dotMatchesLine: Bool) -> [String] {
        var options: NSRegularExpression.Options = [.caseInsensitive]
        if dotMatchesLine {
            options.insert(.dotMatchesLineSeparators)
        }

        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard let fullRange = Range(match.range(at: 0), in: text) else {
                return nil
            }
            return String(text[fullRange])
        }
    }

    private static func extractHeadingAnchoredSections(from html: String) -> [(title: String, body: String)] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<h([1-6])[^>]*>(.*?)</h\1>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, options: [], range: range)

        var sections: [(title: String, body: String)] = []
        for index in matches.indices {
            guard let titleRange = Range(matches[index].range(at: 2), in: html),
                  let fullRange = Range(matches[index].range(at: 0), in: html) else {
                continue
            }

            let title = cleanTitle(String(html[titleRange]))
            guard !title.isEmpty else { continue }

            let bodyStart = fullRange.upperBound
            let bodyEnd: String.Index
            if index + 1 < matches.count,
               let nextRange = Range(matches[index + 1].range(at: 0), in: html) {
                bodyEnd = nextRange.lowerBound
            } else {
                bodyEnd = html.endIndex
            }

            sections.append((title: title, body: String(html[bodyStart..<bodyEnd])))
        }

        return sections
    }

    private static func normalizedSectionTitle(_ value: String) -> String {
        cleanTitle(value)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "：", with: "")
            .replacingOccurrences(of: ":", with: "")
    }

    private static func dedupedRelatedMovies(_ movies: [HiddenJavDBMovie]) -> [HiddenJavDBMovie] {
        var deduped: [HiddenJavDBMovie] = []
        var seen = Set<String>()

        for movie in movies where seen.insert(movie.id).inserted {
            deduped.append(movie)
            if deduped.count >= 18 {
                break
            }
        }

        return deduped
    }
}

@MainActor
private final class HiddenJavDBWebHTMLFetcher: NSObject, WKNavigationDelegate {
    static let shared = HiddenJavDBWebHTMLFetcher()

    private let webView: WKWebView
    private var continuation: CheckedContinuation<String, Error>?
    private var timeoutTask: Task<Void, Never>?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = HiddenJavDBAPI.userAgent
        webView.scrollView.isScrollEnabled = false
        super.init()
        webView.navigationDelegate = self
    }

    func fetchHTML(from url: URL) async throws -> String {
        if continuation != nil {
            throw NSError(
                domain: "HiddenJavDBWebHTMLFetcher",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "页面加载中，请稍后重试"]
            )
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            request.setValue(HiddenJavDBAPI.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            request.setValue("no-cache", forHTTPHeaderField: "Pragma")

            webView.load(request)

            timeoutTask?.cancel()
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                self?.failIfPending(message: "WebView 请求超时，请重试")
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let html = try await webView.evaluateJavaScript("document.documentElement.outerHTML")
                let htmlString = html as? String ?? ""
                if htmlString.isEmpty {
                    failIfPending(message: "WebView 页面为空")
                    return
                }
                finishIfPending(html: htmlString)
            } catch {
                failIfPending(error: error)
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failIfPending(error: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failIfPending(error: error)
    }

    private func finishIfPending(html: String) {
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation?.resume(returning: html)
        continuation = nil
    }

    private func failIfPending(error: Error) {
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation?.resume(throwing: error)
        continuation = nil
    }

    private func failIfPending(message: String) {
        failIfPending(
            error: NSError(
                domain: "HiddenJavDBWebHTMLFetcher",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        )
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
