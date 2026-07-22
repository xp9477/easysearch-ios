import SwiftUI
import WebKit
import AVKit
@preconcurrency import AVFoundation
import UIKit

struct HiddenJavDBFeatureView: View {
    @ObservedObject var viewModel: HiddenJavDBViewModel
    @State private var randomMode: HiddenJavDBRandomMode
    @State private var showRandomDetails: Bool
    @State private var searchQuery = ""
    @State private var webPageItem: HiddenSharedWebPageItem?

    private let searchColumns = [
        GridItem(.flexible(), spacing: ESUI.Space.sm),
        GridItem(.flexible(), spacing: ESUI.Space.sm)
    ]

    init(viewModel: HiddenJavDBViewModel) {
        self.viewModel = viewModel
        let settings = HiddenSpaceSettingsStore.shared.load()
        _randomMode = State(initialValue: settings.javDBRandomMode)
        _showRandomDetails = State(initialValue: settings.showJavDBDetailsByDefault)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ESUI.sectionSpacing) {
                searchMovieCard
                randomMovieCard

                NavigationLink(value: HiddenSpaceRoute.javDBFavorites) {
                    HStack(spacing: ESUI.Space.sm) {
                        ESFeatureIcon(systemName: "heart.text.square", color: .pink, size: 40)
                        VStack(alignment: .leading, spacing: ESUI.Space.xxs) {
                            Text("喜欢影片")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("收藏与快速随机播放")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: ESUI.Space.xs)
                        ESStatusBadge(text: "\(viewModel.favoriteMovies.count)", tone: .accent)
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
        .navigationTitle("javdb")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.prepareCloudIfNeeded()
            await viewModel.loadRandomMovieIfNeeded(mode: randomMode)
        }
        .onChange(of: randomMode) { mode in
            showRandomDetails = HiddenSpaceSettingsStore.shared.load().showJavDBDetailsByDefault
            Task {
                await viewModel.loadRandomMovies(mode: mode)
            }
        }
        .onChange(of: searchQuery) { newValue in
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                viewModel.resetSearchMovies()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .hiddenSpaceSettingsDidChange)) { _ in
            let settings = HiddenSpaceSettingsStore.shared.load()
            randomMode = settings.javDBRandomMode
            showRandomDetails = settings.showJavDBDetailsByDefault
        }
        .fullScreenCover(item: $webPageItem) { item in
            HiddenSharedWebPageView(item: item)
        }
    }

    @ViewBuilder
    private var searchMovieCard: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            ESSectionHeader(title: "搜索影片")

            HStack(spacing: ESUI.Space.sm) {
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
                ESInfoBanner(title: "正在搜索", systemImage: "magnifyingglass", tone: .accent)
            } else if let searchErrorMessage = viewModel.searchMovieErrorMessage {
                playbackIssueView(message: searchErrorMessage) {
                    performMovieSearch()
                }
            } else if let lastQuery = viewModel.lastSearchedMovieQuery, !viewModel.searchedMovies.isEmpty {
                VStack(alignment: .leading, spacing: ESUI.Space.sm) {
                    Text("“\(lastQuery)” · \(viewModel.searchedMovies.count) 个结果")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: searchColumns, spacing: ESUI.Space.sm) {
                        ForEach(viewModel.searchedMovies) { movie in
                            NavigationLink(value: HiddenSpaceRoute.javDBMovie(movie)) {
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
                ESEmptyState(
                    title: "没有搜索到影片",
                    message: "“\(lastQuery)” 暂无匹配结果，可换关键词重试。",
                    systemImage: "film"
                )
            }
        }
        .esCard()
    }

    @ViewBuilder
    private var randomMovieCard: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            ESSectionHeader(
                title: "随机影片",
                trailing: viewModel.isLoadingRandomMovie ? "加载中" : randomMode.title
            )

            Picker("随机模式", selection: $randomMode) {
                ForEach(HiddenJavDBRandomMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if randomMode == .single {
                if viewModel.isLoadingRandomMovie {
                    HiddenMediaPlaceholder(mode: .loading(randomMode.loadingText), systemImage: "film.stack")
                        .frame(height: 230)
                } else if let movie = viewModel.randomMovie {
                    NavigationLink(value: HiddenSpaceRoute.javDBMovie(movie)) {
                        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
                            AsyncCoverImage(url: movie.coverURL, fitToContainer: true)
                                .frame(height: 230)
                                .clipShape(RoundedRectangle(cornerRadius: ESUI.cardCornerRadius, style: .continuous))

                            VStack(alignment: .leading, spacing: ESUI.Space.xxs) {
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

                    HStack(spacing: ESUI.Space.sm) {
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
                    playbackIssueView(message: viewModel.randomErrorMessage ?? "暂时没有拿到影片") {
                        Task {
                            await viewModel.loadRandomMovies(mode: randomMode)
                        }
                    }
                }
            } else {
                if !viewModel.randomMovies.isEmpty {
                    LazyVStack(spacing: ESUI.Space.sm) {
                        ForEach(Array(viewModel.randomMovies.prefix(9))) { movie in
                            NavigationLink(value: HiddenSpaceRoute.javDBMovie(movie)) {
                                HiddenJavDBRandomListMovieTile(movie: movie, isFavorite: viewModel.isFavorite(movie))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if viewModel.isLoadingRandomMovie {
                        HStack(spacing: ESUI.Space.xs) {
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
                    HiddenMediaPlaceholder(mode: .loading(randomMode.loadingText), systemImage: "film.stack")
                        .frame(height: 230)
                } else {
                    playbackIssueView(message: viewModel.randomErrorMessage ?? "暂时没有拿到影片") {
                        Task {
                            await viewModel.loadRandomMovies(mode: randomMode)
                        }
                    }
                }
            }
        }
        .esCard()
    }

    private func playbackIssueView(message: String, retry: @escaping () -> Void) -> some View {
        let issue = HiddenPlaybackIssuePresentation(message: message)

        return VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            ESInfoBanner(
                title: issue.title,
                message: issue.message,
                systemImage: issue.systemImage,
                tone: issue.tone
            )

            HStack(spacing: ESUI.Space.sm) {
                Button(issue.primaryActionTitle) {
                    retry()
                }
                .buttonStyle(.borderedProminent)

                if issue.kind == .javDBAgeConfirmation {
                    Button(issue.secondaryActionTitle ?? "打开确认页") {
                        webPageItem = HiddenSharedWebPageItem(
                            title: "javdb",
                            url: URL(string: "https://javdb.com/")!
                        )
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
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

struct HiddenJavDBFavoriteMoviesView: View {
    @ObservedObject var viewModel: HiddenJavDBViewModel
    @ObservedObject var presentationState: HiddenSpacePresentationState
    @State private var showDetails: Bool
    @State private var isResolvingRandomPlayback = false
    @State private var randomPlaybackErrorMessage: String?

    private let columns = [
        GridItem(.flexible(), spacing: ESUI.Space.sm),
        GridItem(.flexible(), spacing: ESUI.Space.sm)
    ]

    init(viewModel: HiddenJavDBViewModel, presentationState: HiddenSpacePresentationState) {
        self.viewModel = viewModel
        self.presentationState = presentationState
        _showDetails = State(initialValue: HiddenSpaceSettingsStore.shared.load().showJavDBDetailsByDefault)
    }

    var body: some View {
        ScrollView {
            if viewModel.favoriteMovies.isEmpty {
                ESEmptyState(
                    title: "还没有喜欢的影片",
                    message: "在随机列表或详情页点喜欢后会出现在这里。",
                    systemImage: "heart"
                )
                .frame(maxWidth: .infinity, minHeight: 280)
            } else {
                VStack(alignment: .leading, spacing: ESUI.Space.md) {
                    HStack(spacing: ESUI.Space.sm) {
                        Button {
                            Task {
                                await playRandomFavoriteMovie()
                            }
                        } label: {
                            HStack(spacing: ESUI.Space.xs) {
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

                    LazyVGrid(columns: columns, spacing: ESUI.Space.sm) {
                        ForEach(viewModel.favoriteMovies) { movie in
                            NavigationLink(value: HiddenSpaceRoute.javDBMovie(movie)) {
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
                .padding(.horizontal, ESUI.screenHorizontalPadding)
                .padding(.top, ESUI.Space.md)
                .padding(.bottom, ESUI.Space.lg)
            }
        }
        .esScreenBackground()
        .navigationTitle("喜欢影片")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: inAppPlayerItemBinding) { item in
            HiddenSharedVideoPlayerView(
                item: item,
                onSavePlaybackPosition: { item, position in
                    guard let movie = favoriteMovie(for: item) else {
                        return HiddenPlaybackSaveResult(
                            savedPositionSeconds: position,
                            markerPositions: item.markerPositions,
                            undo: { item.markerPositions }
                        )
                    }
                    let playback = HiddenJavDBFavoritePlayback(
                        movie: movie,
                        sourceName: item.sourceName,
                        streamURL: item.streamURL,
                        refererURL: item.refererURL,
                        positionSeconds: position
                    )
                    let context = viewModel.saveFavoritePlayback(playback)
                    return HiddenPlaybackSaveResult(
                        savedPositionSeconds: context.savedPlayback.positionSeconds,
                        markerPositions: context.markerPositions,
                        undo: { viewModel.undoFavoritePlaybackSave(context) }
                    )
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .hiddenSpaceSettingsDidChange)) { _ in
            showDetails = HiddenSpaceSettingsStore.shared.load().showJavDBDetailsByDefault
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
                    inAppPlayerItem = HiddenSharedPlayerItem(
                        resourceID: movie.id,
                        title: movie.displayTitle,
                        code: movie.code,
                        coverURL: movie.coverURL,
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
                inAppPlayerItem = HiddenSharedPlayerItem(
                    resourceID: movie.id,
                    title: movie.displayTitle,
                    code: movie.code,
                    coverURL: movie.coverURL,
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

    private func favoriteMovie(for item: HiddenSharedPlayerItem) -> HiddenJavDBMovie? {
        viewModel.favoriteMovies.first {
            $0.id == item.resourceID || $0.code.caseInsensitiveCompare(item.code) == .orderedSame
        }
    }

    private var inAppPlayerItem: HiddenSharedPlayerItem? {
        get {
            guard case let .javDBFavoritesPlayer(item) = presentationState.modal else { return nil }
            return item
        }
        nonmutating set {
            presentationState.modal = newValue.map(HiddenSpacePresentedModal.javDBFavoritesPlayer)
        }
    }

    private var inAppPlayerItemBinding: Binding<HiddenSharedPlayerItem?> {
        Binding(
            get: { inAppPlayerItem },
            set: { inAppPlayerItem = $0 }
        )
    }
}

struct HiddenJavDBMovieDetailView: View {
    let movie: HiddenJavDBMovie
    @ObservedObject var viewModel: HiddenJavDBViewModel
    @ObservedObject var presentationState: HiddenSpacePresentationState

    @State private var imageURLs: [URL] = []
    @State private var isLoadingImages = false
    @State private var imageErrorMessage: String?
    @State private var showDetails: Bool
    @State private var isResolvingWatchPlayback = false
    @State private var resolvingWatchSiteName: String?
    @State private var watchPlaybackErrorMessage: String?
    @State private var hasCompletedInitialImagePhase = false
    @State private var missAVDomainDisplay = HiddenMissAVDomainConfiguration.currentHost()

    private let columns = [
        GridItem(.flexible(), spacing: ESUI.Space.xs),
        GridItem(.flexible(), spacing: ESUI.Space.xs),
        GridItem(.flexible(), spacing: ESUI.Space.xs)
    ]
    private let favoritePlaybackColumns = [
        GridItem(.adaptive(minimum: 150), spacing: ESUI.Space.xs)
    ]
    private let relatedMovieColumns = [
        GridItem(.adaptive(minimum: 146), spacing: ESUI.Space.sm)
    ]
    private var favoritePlaybackEntries: [HiddenJavDBFavoritePlayback] {
        viewModel.favoritePlaybacks(for: movie)
    }
    private var movieDetail: HiddenJavDBMovieDetail? {
        viewModel.detailsByMovieID[movie.id]
    }
    private var relatedMovieDetailErrorMessage: String? {
        guard hasCompletedInitialImagePhase, movieDetail == nil else { return nil }
        return viewModel.detailErrorsByMovieID[movie.id]
    }
    private var isLoadingRelatedMovieSections: Bool {
        hasCompletedInitialImagePhase && movieDetail == nil && relatedMovieDetailErrorMessage == nil
    }

    init(movie: HiddenJavDBMovie, viewModel: HiddenJavDBViewModel, presentationState: HiddenSpacePresentationState) {
        self.movie = movie
        self.viewModel = viewModel
        self.presentationState = presentationState
        _showDetails = State(initialValue: HiddenSpaceSettingsStore.shared.load().showJavDBDetailsByDefault)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ESUI.sectionSpacing) {
                AsyncCoverImage(url: movie.coverURL, fitToContainer: true)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: ESUI.cardCornerRadius, style: .continuous))

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
                }

                watchSection
                favoritePlaybackSection
                screenshotsSection
                relatedMovieSections
            }
            .padding(.horizontal, ESUI.screenHorizontalPadding)
            .padding(.vertical, ESUI.Space.md)
        }
        .esScreenBackground()
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
        .task(id: hasCompletedInitialImagePhase) {
            guard hasCompletedInitialImagePhase else { return }
            await viewModel.loadDetailIfNeeded(for: movie)
        }
        .fullScreenCover(item: previewImageBinding) { preview in
            HiddenJavDBImagePreviewView(imageURLs: preview.urls, initialIndex: preview.index)
        }
        .fullScreenCover(item: inAppPlayerItemBinding) { item in
            HiddenSharedVideoPlayerView(
                item: item,
                onSavePlaybackPosition: { item, position in
                    let playback = HiddenJavDBFavoritePlayback(
                        movie: movie,
                        sourceName: item.sourceName,
                        streamURL: item.streamURL,
                        refererURL: item.refererURL,
                        positionSeconds: position
                    )
                    let context = viewModel.saveFavoritePlayback(playback)
                    return HiddenPlaybackSaveResult(
                        savedPositionSeconds: context.savedPlayback.positionSeconds,
                        markerPositions: context.markerPositions,
                        undo: { viewModel.undoFavoritePlaybackSave(context) }
                    )
                }
            )
        }
        .fullScreenCover(item: inAppWebPageItemBinding) { item in
            HiddenSharedWebPageView(item: item)
        }
        .onReceive(NotificationCenter.default.publisher(for: .hiddenSpaceSettingsDidChange)) { _ in
            let settings = HiddenSpaceSettingsStore.shared.load()
            showDetails = settings.showJavDBDetailsByDefault
            missAVDomainDisplay = HiddenMissAVDomainConfiguration.resolvedHost(from: settings.missAVDomain)
        }
    }

    private var watchSection: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            ESSectionHeader(title: "播放", trailing: missAVDomainDisplay)

            if let url = HiddenJavDBWatchSite.missAV.url(for: movie.code) {
                Button {
                    Task {
                        await openWatchSite(site: .missAV, pageURL: url)
                    }
                } label: {
                    HStack(spacing: ESUI.Space.sm) {
                        Group {
                            if isResolvingWatchPlayback && resolvingWatchSiteName == HiddenJavDBWatchSite.missAV.name {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                        }
                        .frame(width: 18, height: 18)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(isResolvingWatchPlayback && resolvingWatchSiteName == HiddenJavDBWatchSite.missAV.name ? "载入中..." : "播放")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(missAVDomainDisplay)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, ESUI.Space.md)
                    .padding(.vertical, ESUI.Space.sm)
                    .background(
                        RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                            .fill(ESUI.fill)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isResolvingWatchPlayback)

                if let watchPlaybackErrorMessage {
                    watchPlaybackIssueView(message: watchPlaybackErrorMessage, pageURL: url)
                }
            }
        }
        .esCard(cornerRadius: ESUI.compactCornerRadius)
    }

    private func watchPlaybackIssueView(message: String, pageURL: URL) -> some View {
        let issue = HiddenPlaybackIssuePresentation(message: message)

        return VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            ESInfoBanner(
                title: issue.title,
                message: issue.message,
                systemImage: issue.systemImage,
                tone: issue.tone
            )

            HStack(spacing: ESUI.Space.sm) {
                Button(issue.primaryActionTitle) {
                    Task {
                        await openWatchSite(site: .missAV, pageURL: pageURL)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isResolvingWatchPlayback)

                switch issue.kind {
                case .javDBAgeConfirmation:
                    Button(issue.secondaryActionTitle ?? "打开确认页") {
                        inAppWebPageItem = HiddenSharedWebPageItem(
                            title: "javdb · \(movie.code)",
                            url: pageURL
                        )
                    }
                    .buttonStyle(.bordered)
                case .missAVUnavailable:
                    NavigationLink(value: HiddenSpaceRoute.settings) {
                        Text(issue.secondaryActionTitle ?? "修改域名")
                    }
                    .buttonStyle(.bordered)
                default:
                    EmptyView()
                }
            }
        }
    }

    @ViewBuilder
    private var favoritePlaybackSection: some View {
        if !favoritePlaybackEntries.isEmpty {
            VStack(alignment: .leading, spacing: ESUI.Space.sm) {
                ESSectionHeader(title: "喜欢点", trailing: "\(favoritePlaybackEntries.count) 个")

                LazyVGrid(columns: favoritePlaybackColumns, spacing: ESUI.Space.xs) {
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
            .esCard(cornerRadius: ESUI.compactCornerRadius)
        }
    }

    private var screenshotsSection: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            ESSectionHeader(
                title: "截图",
                trailing: isLoadingImages ? "加载中" : nil
            )

            if isLoadingImages {
                ESLoadingState(message: "正在加载截图…")
                    .frame(minHeight: 180)
            } else if let imageErrorMessage {
                ESErrorState(
                    title: "截图加载失败",
                    message: imageErrorMessage,
                    retryTitle: "重试",
                    retry: {
                        Task {
                            await loadImages(force: true)
                        }
                    }
                )
                .frame(minHeight: 180)
            } else if imageURLs.isEmpty {
                ESEmptyState(title: "没有拿到可用截图", systemImage: "photo.on.rectangle")
                    .frame(minHeight: 120)
            } else {
                LazyVGrid(columns: columns, spacing: ESUI.Space.xs) {
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
        .esCard(cornerRadius: ESUI.compactCornerRadius)
    }

    @ViewBuilder
    private var relatedMovieSections: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.md) {
            relatedMovieSection(
                title: "她还演过",
                movies: movieDetail?.otherActressMovies ?? [],
                emptyMessage: "暂时没有她还演过的影片",
                isLoading: isLoadingRelatedMovieSections,
                errorMessage: relatedMovieDetailErrorMessage
            )

            relatedMovieSection(
                title: "猜你喜欢",
                movies: movieDetail?.recommendedMovies ?? [],
                emptyMessage: "暂时没有猜你喜欢",
                isLoading: isLoadingRelatedMovieSections,
                errorMessage: relatedMovieDetailErrorMessage
            )
        }
    }

    @ViewBuilder
    private func relatedMovieSection(
        title: String,
        movies: [HiddenJavDBMovie],
        emptyMessage: String,
        isLoading: Bool,
        errorMessage: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            ESSectionHeader(
                title: title,
                trailing: isLoading ? nil : "\(movies.count) 部"
            )

            if !hasCompletedInitialImagePhase {
                ESLoadingState(message: "截图加载完成后开始加载 \(title)…")
            } else if isLoading {
                ESLoadingState(message: "正在加载 \(title)…")
            } else if let errorMessage, movies.isEmpty {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if movies.isEmpty {
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: relatedMovieColumns, alignment: .leading, spacing: ESUI.Space.sm) {
                    ForEach(movies) { relatedMovie in
                        NavigationLink(value: HiddenSpaceRoute.javDBMovie(relatedMovie)) {
                            HiddenJavDBRelatedMovieTile(movie: relatedMovie)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .esCard(cornerRadius: ESUI.compactCornerRadius)
    }

    private func loadImages(force: Bool) async {
        if !force && (!imageURLs.isEmpty || isLoadingImages) {
            if !imageURLs.isEmpty {
                hasCompletedInitialImagePhase = true
            }
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

        hasCompletedInitialImagePhase = true
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
                inAppWebPageItem = HiddenSharedWebPageItem(
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
    ) -> HiddenSharedPlayerItem {
        HiddenSharedPlayerItem(
            resourceID: movie.id,
            title: movie.displayTitle,
            code: movie.code,
            coverURL: movie.coverURL,
            sourceName: sourceName,
            streamURL: streamURL,
            refererURL: refererURL,
            startPositionSeconds: startPositionSeconds,
            markerPositions: viewModel.playbackMarkerPositions(for: movie)
        )
    }

    private var previewImage: HiddenJavDBPreviewImage? {
        get {
            guard case let .javDBMoviePreview(movieID, preview) = presentationState.modal,
                  movieID == movie.id else { return nil }
            return preview
        }
        nonmutating set {
            presentationState.modal = newValue.map { HiddenSpacePresentedModal.javDBMoviePreview(movieID: movie.id, preview: $0) }
        }
    }

    private var inAppPlayerItem: HiddenSharedPlayerItem? {
        get {
            guard case let .javDBMoviePlayer(movieID, item) = presentationState.modal,
                  movieID == movie.id else { return nil }
            return item
        }
        nonmutating set {
            presentationState.modal = newValue.map { HiddenSpacePresentedModal.javDBMoviePlayer(movieID: movie.id, item: $0) }
        }
    }

    private var inAppWebPageItem: HiddenSharedWebPageItem? {
        get {
            guard case let .javDBMovieWebPage(movieID, item) = presentationState.modal,
                  movieID == movie.id else { return nil }
            return item
        }
        nonmutating set {
            presentationState.modal = newValue.map { HiddenSpacePresentedModal.javDBMovieWebPage(movieID: movie.id, item: $0) }
        }
    }

    private var previewImageBinding: Binding<HiddenJavDBPreviewImage?> {
        Binding(
            get: { previewImage },
            set: { previewImage = $0 }
        )
    }

    private var inAppPlayerItemBinding: Binding<HiddenSharedPlayerItem?> {
        Binding(
            get: { inAppPlayerItem },
            set: { inAppPlayerItem = $0 }
        )
    }

    private var inAppWebPageItemBinding: Binding<HiddenSharedWebPageItem?> {
        Binding(
            get: { inAppWebPageItem },
            set: { inAppWebPageItem = $0 }
        )
    }
}

private struct HiddenJavDBMovieDetailSummaryView: View {
    let movie: HiddenJavDBMovie
    let detail: HiddenJavDBMovieDetail?
    let errorMessage: String?
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.xs) {
            if isLoading {
                HStack(spacing: ESUI.Space.xs) {
                    ProgressView()
                    Text("正在加载详细信息…")
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
        .esCard(cornerRadius: ESUI.compactCornerRadius)
    }
}

private struct HiddenJavDBDetailRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: ESUI.Space.xs) {
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
    private let thumbnailAspectRatio: CGFloat = 25.0 / 14.0

    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var didFail = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                .fill(ESUI.fill)

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
                    .minimumScaleFactor(0.82)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(thumbnailAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous))
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

                    Text(didFail ? "未取到预览帧" : "正在取预览帧")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.82))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous))
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

private struct HiddenJavDBFavoriteMovieTile: View {
    let movie: HiddenJavDBMovie
    let detail: HiddenJavDBMovieDetail?
    let errorMessage: String?
    let isLoadingDetail: Bool
    let showDetails: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.xs) {
            AsyncCoverImage(url: movie.coverURL)
                .frame(height: 126)
                .clipShape(RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous))

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
        .esCard(cornerRadius: ESUI.compactCornerRadius)
    }
}

private struct HiddenJavDBRelatedMovieTile: View {
    let movie: HiddenJavDBMovie

    var body: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.xs) {
            ZStack(alignment: .topLeading) {
                AsyncCoverImage(url: movie.coverURL, fitToContainer: true)
                    .frame(maxWidth: .infinity)
                    .frame(height: 172)
                    .clipShape(RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous))

                Text(movie.code)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.56), in: Capsule())
                    .padding(8)
            }

            Text(movie.displayTitle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)

            if !movie.actresses.isEmpty {
                Text(movie.actressesText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(ESUI.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: ESUI.cardCornerRadius, style: .continuous)
                .fill(ESUI.fill)
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
                .clipShape(RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous))

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
        .contentShape(RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous))
    }
}
