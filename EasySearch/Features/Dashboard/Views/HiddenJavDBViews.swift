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

    private let searchColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    init(viewModel: HiddenJavDBViewModel) {
        self.viewModel = viewModel
        let settings = HiddenSpaceSettingsStore.shared.load()
        _randomMode = State(initialValue: settings.javDBRandomMode)
        _showRandomDetails = State(initialValue: settings.showJavDBDetailsByDefault)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                searchMovieCard
                randomMovieCard

                NavigationLink(value: HiddenSpaceRoute.javDBFavorites) {
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
                    NavigationLink(value: HiddenSpaceRoute.javDBMovie(movie)) {
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
                            NavigationLink(value: HiddenSpaceRoute.javDBMovie(movie)) {
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

struct HiddenJavDBFavoriteMoviesView: View {
    @ObservedObject var viewModel: HiddenJavDBViewModel
    @ObservedObject var presentationState: HiddenSpacePresentationState
    @State private var showDetails: Bool
    @State private var isResolvingRandomPlayback = false
    @State private var randomPlaybackErrorMessage: String?

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    init(viewModel: HiddenJavDBViewModel, presentationState: HiddenSpacePresentationState) {
        self.viewModel = viewModel
        self.presentationState = presentationState
        _showDetails = State(initialValue: HiddenSpaceSettingsStore.shared.load().showJavDBDetailsByDefault)
    }

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
                .padding(.horizontal, 12)
                .padding(.top, 12)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
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
                },
                onPlaybackClosed: { item, position in
                    guard let movie = favoriteMovie(for: item) else { return }
                    let playback = HiddenJavDBFavoritePlayback(
                        movie: movie,
                        sourceName: item.sourceName,
                        streamURL: item.streamURL,
                        refererURL: item.refererURL,
                        positionSeconds: position
                    )
                    _ = viewModel.saveFavoritePlayback(playback)
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
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]
    private let favoritePlaybackColumns = [
        GridItem(.adaptive(minimum: 150), spacing: 8)
    ]
    private let relatedMovieColumns = [
        GridItem(.adaptive(minimum: 146), spacing: 10)
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
                },
                onPlaybackClosed: { item, position in
                    let playback = HiddenJavDBFavoritePlayback(
                        movie: movie,
                        sourceName: item.sourceName,
                        streamURL: item.streamURL,
                        refererURL: item.refererURL,
                        positionSeconds: position
                    )
                    _ = viewModel.saveFavoritePlayback(playback)
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
        VStack(alignment: .leading, spacing: 12) {
            Text("播放")
                .font(.headline)

            Text("仅保留 miss 入口，直接拉起当前影片播放。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let url = HiddenJavDBWatchSite.missAV.url(for: movie.code) {
                Button {
                    Task {
                        await openWatchSite(site: .missAV, pageURL: url)
                    }
                } label: {
                    HStack(spacing: 12) {
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
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.tertiarySystemFill))
                    )
                }
                .buttonStyle(.plain)
                .disabled(isResolvingWatchPlayback)
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

                LazyVGrid(columns: favoritePlaybackColumns, spacing: 8) {
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
        VStack(alignment: .leading, spacing: 12) {
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()

                if !isLoading {
                    Text("\(movies.count) 部")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !hasCompletedInitialImagePhase {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("截图加载完成后开始加载 \(title)...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("正在加载 \(title)...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
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
                LazyVGrid(columns: relatedMovieColumns, alignment: .leading, spacing: 10) {
                    ForEach(movies) { relatedMovie in
                        NavigationLink(value: HiddenSpaceRoute.javDBMovie(relatedMovie)) {
                            HiddenJavDBRelatedMovieTile(movie: relatedMovie)
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
    private let thumbnailAspectRatio: CGFloat = 25.0 / 14.0

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
                    .minimumScaleFactor(0.82)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(thumbnailAspectRatio, contentMode: .fit)
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

                    Text(didFail ? "未取到预览帧" : "正在取预览帧")
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

private struct HiddenJavDBRelatedMovieTile: View {
    let movie: HiddenJavDBMovie

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                AsyncCoverImage(url: movie.coverURL, fitToContainer: true)
                    .frame(maxWidth: .infinity)
                    .frame(height: 172)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

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
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.tertiarySystemFill))
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

struct HiddenJavDBWatchSite: Identifiable, Hashable {
    enum LaunchMode: Equatable {
        case nativeStream
        case embeddedWeb
        case external
    }

    let name: String
    let urlTemplate: String
    var id: String { name }

    static var missAV: HiddenJavDBWatchSite {
        HiddenJavDBWatchSite(name: "MISSAV", urlTemplate: HiddenMissAVDomainConfiguration.currentMovieTemplate())
    }

    static var defaultSites: [HiddenJavDBWatchSite] {
        [.missAV]
    }

    var launchMode: LaunchMode {
        switch name {
        case "MISSAV":
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

private struct HiddenInAppPlayerItem: Identifiable, Hashable {
    let movie: HiddenJavDBMovie
    let sourceName: String
    let streamURL: URL
    let refererURL: URL
    let startPositionSeconds: Double
    let markerPositions: [Double]
    let id = UUID()
}

private struct HiddenInAppWebPageItem: Identifiable, Hashable {
    let title: String
    let url: URL
    let id = UUID()
}

private struct HiddenInAppVideoPlayerView: View {
    private enum SurfaceInteractionMode {
        case undecided
        case brightnessAdjusting
    }

    let item: HiddenInAppPlayerItem
    let onSaveFavoritePlayback: (HiddenJavDBFavoritePlayback) -> HiddenJavDBFavoritePlaybackSaveContext
    let onUndoFavoritePlaybackSave: (HiddenJavDBFavoritePlaybackSaveContext) -> [Double]

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer
    @State private var appliedPlaybackRate: Float = 1.0
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
    @State private var isTemporaryBoostActive = false
    @State private var playbackRateRampTask: Task<Void, Never>?
    @State private var pendingBoostActivationTask: Task<Void, Never>?
    @State private var activeTouchStartedAt: Date?
    @State private var activeTouchStartLocation: CGPoint?
    @State private var didActivateTouchBoost = false
    @State private var surfaceInteractionMode: SurfaceInteractionMode = .undecided
    @State private var touchStartBrightness: CGFloat?
    @State private var displayedBrightness: CGFloat?
    @State private var didApplyInitialStartPosition = false
    @State private var markerPositions: [Double]

    private let normalPlaybackRate: Float = 1.0
    private let temporaryBoostRate: Float = 2.0
    private let boostActivationDelay: TimeInterval = 0.18
    private let boostActivationMaximumDistance: CGFloat = 36
    private let tapMaximumDistance: CGFloat = 12
    private let playbackRateRampDuration: TimeInterval = 0.28
    private let brightnessGestureLeadingRegionRatio: CGFloat = 0.42
    private let brightnessActivationMinimumDistance: CGFloat = 14

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
            "Origin": "\(item.refererURL.scheme ?? "https")://\(item.refererURL.host ?? HiddenMissAVDomainConfiguration.currentHost())",
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

            GeometryReader { proxy in
                Color.clear
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .gesture(videoSurfaceGesture(in: proxy.size))
            }
            .ignoresSafeArea()

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

            if shouldShowPlaybackRateHUD {
                playbackRateHUD
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            if shouldShowBrightnessHUD {
                brightnessHUD
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: shouldShowPlaybackRateHUD)
        .animation(.easeInOut(duration: 0.18), value: shouldShowBrightnessHUD)
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .onAppear {
            configureAudioSession()
            player.isMuted = true
            applyPlayerRateImmediately(normalPlaybackRate)
            player.playImmediately(atRate: appliedPlaybackRate)
            syncPlaybackState()
            scheduleControlsAutoHide()
        }
        .onDisappear {
            seekTask?.cancel()
            controlsAutoHideTask?.cancel()
            favoriteSaveResetTask?.cancel()
            pendingBoostActivationTask?.cancel()
            playbackRateRampTask?.cancel()
            isTemporaryBoostActive = false
            displayedBrightness = nil
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
                            playerBadge(text: formattedRate(appliedPlaybackRate))
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
                    }

                    Text("左侧上下滑动调亮度，长按画面可临时 2x 播放。")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(maxWidth: .infinity, alignment: .leading)

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

    private var shouldShowPlaybackRateHUD: Bool {
        abs(appliedPlaybackRate - normalPlaybackRate) > 0.05
    }

    private var playbackRateHUD: some View {
        VStack {
            Text(formattedRate(appliedPlaybackRate))
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isTemporaryBoostActive ? Color.orange.opacity(0.86) : Color.black.opacity(0.56))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
            Spacer()
        }
        .padding(.top, controlsVisible ? 94 : 54)
        .allowsHitTesting(false)
    }

    private var shouldShowBrightnessHUD: Bool {
        displayedBrightness != nil
    }

    private var brightnessHUD: some View {
        VStack {
            Spacer()

            HStack {
                VStack(spacing: 10) {
                    Image(systemName: "sun.max.fill")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)

                    Text(formattedBrightness(displayedBrightness ?? UIScreen.main.brightness))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)

                    GeometryReader { proxy in
                        ZStack(alignment: .bottom) {
                            Capsule()
                                .fill(Color.white.opacity(0.14))

                            Capsule()
                                .fill(Color.white)
                                .frame(height: max(12, proxy.size.height * (displayedBrightness ?? UIScreen.main.brightness)))
                        }
                    }
                    .frame(width: 8, height: 88)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
                .background(Color.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )

                Spacer()
            }
            .padding(.leading, 18)
            .padding(.bottom, controlsVisible ? 168 : 84)
        }
        .allowsHitTesting(false)
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
            player.playImmediately(atRate: appliedPlaybackRate)
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

    private func formattedRate(_ value: Float) -> String {
        let roundedValue = round(value)
        if abs(value - roundedValue) < 0.05 {
            return "\(Int(roundedValue))x"
        }
        return String(format: "%.1fx", value)
    }

    private func formattedBrightness(_ value: CGFloat) -> String {
        "\(Int(round(value * 100)))%"
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

    private var targetPlaybackRate: Float {
        isTemporaryBoostActive ? temporaryBoostRate : normalPlaybackRate
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
        let rateAfterSeek = appliedPlaybackRate

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

    private func videoSurfaceGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                handleVideoSurfaceTouchChanged(value, in: size)
            }
            .onEnded { value in
                handleVideoSurfaceTouchEnded(value)
            }
    }

    private func applyPlayerRateImmediately(_ rate: Float) {
        let normalizedRate = max(0.25, rate)
        appliedPlaybackRate = normalizedRate
        player.defaultRate = normalizedRate
        if player.timeControlStatus == .playing {
            player.rate = normalizedRate
        }
    }

    private func rampPlaybackRate(to targetRate: Float) {
        playbackRateRampTask?.cancel()

        let clampedTargetRate = max(0.25, targetRate)
        let startRate = appliedPlaybackRate
        guard abs(startRate - clampedTargetRate) >= 0.02 else {
            applyPlayerRateImmediately(clampedTargetRate)
            return
        }

        playbackRateRampTask = Task { @MainActor in
            let startedAt = Date()

            while !Task.isCancelled {
                let progress = min(Date().timeIntervalSince(startedAt) / playbackRateRampDuration, 1)
                let easedProgress = 1 - pow(1 - progress, 3)
                let nextRate = startRate + (clampedTargetRate - startRate) * Float(easedProgress)
                applyPlayerRateImmediately(nextRate)

                if progress >= 1 {
                    break
                }

                try? await Task.sleep(nanoseconds: 16_000_000)
            }

            guard !Task.isCancelled else { return }
            applyPlayerRateImmediately(clampedTargetRate)
        }
    }

    private func beginTemporarySpeedBoost() {
        guard !isTemporaryBoostActive else { return }
        isTemporaryBoostActive = true
        rampPlaybackRate(to: targetPlaybackRate)
    }

    private func endTemporarySpeedBoostIfNeeded() {
        guard isTemporaryBoostActive else { return }
        isTemporaryBoostActive = false
        rampPlaybackRate(to: targetPlaybackRate)
    }

    private func handleVideoSurfaceTouchChanged(_ value: DragGesture.Value, in size: CGSize) {
        if activeTouchStartedAt == nil {
            activeTouchStartedAt = Date()
            activeTouchStartLocation = value.startLocation
            surfaceInteractionMode = .undecided
            touchStartBrightness = UIScreen.main.brightness
            displayedBrightness = nil
            didActivateTouchBoost = false
            schedulePendingBoostActivation()
            return
        }

        guard let touchStartLocation = activeTouchStartLocation else { return }
        let horizontalDistance = abs(value.location.x - touchStartLocation.x)
        let verticalDistance = abs(value.location.y - touchStartLocation.y)

        if shouldBeginBrightnessAdjustment(
            from: touchStartLocation,
            in: size,
            horizontalDistance: horizontalDistance,
            verticalDistance: verticalDistance
        ) {
            beginBrightnessAdjustment()
        }

        if surfaceInteractionMode == .brightnessAdjusting {
            updateBrightness(with: value, in: size)
            return
        }

        let travelDistance = distanceBetween(value.location, and: touchStartLocation)

        if travelDistance > boostActivationMaximumDistance {
            pendingBoostActivationTask?.cancel()
            if isTemporaryBoostActive {
                endTemporarySpeedBoostIfNeeded()
            }
        }
    }

    private func handleVideoSurfaceTouchEnded(_ value: DragGesture.Value) {
        let touchStartedAt = activeTouchStartedAt
        let touchStartLocation = activeTouchStartLocation ?? value.startLocation
        let pressDuration = touchStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        let travelDistance = distanceBetween(value.location, and: touchStartLocation)
        let shouldToggleControls = surfaceInteractionMode == .undecided && !didActivateTouchBoost && pressDuration < boostActivationDelay && travelDistance <= tapMaximumDistance

        pendingBoostActivationTask?.cancel()
        activeTouchStartedAt = nil
        activeTouchStartLocation = nil
        touchStartBrightness = nil
        displayedBrightness = nil
        surfaceInteractionMode = .undecided
        didActivateTouchBoost = false

        endTemporarySpeedBoostIfNeeded()

        if shouldToggleControls {
            toggleControlsVisibility()
        }
    }

    private func schedulePendingBoostActivation() {
        pendingBoostActivationTask?.cancel()
        pendingBoostActivationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(boostActivationDelay * 1_000_000_000))
            guard !Task.isCancelled, activeTouchStartedAt != nil, !didActivateTouchBoost else { return }
            didActivateTouchBoost = true
            beginTemporarySpeedBoost()
        }
    }

    private func distanceBetween(_ lhs: CGPoint, and rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private func shouldBeginBrightnessAdjustment(
        from startLocation: CGPoint,
        in size: CGSize,
        horizontalDistance: CGFloat,
        verticalDistance: CGFloat
    ) -> Bool {
        guard surfaceInteractionMode == .undecided else { return false }
        guard startLocation.x <= size.width * brightnessGestureLeadingRegionRatio else { return false }
        guard verticalDistance >= brightnessActivationMinimumDistance else { return false }
        return verticalDistance > horizontalDistance * 1.2
    }

    private func beginBrightnessAdjustment() {
        pendingBoostActivationTask?.cancel()
        endTemporarySpeedBoostIfNeeded()
        surfaceInteractionMode = .brightnessAdjusting
    }

    private func updateBrightness(with value: DragGesture.Value, in size: CGSize) {
        guard let startLocation = activeTouchStartLocation, let startBrightness = touchStartBrightness else { return }
        let height = max(size.height, 1)
        let delta = (startLocation.y - value.location.y) / height
        let nextBrightness = min(max(startBrightness + delta, 0), 1)
        UIScreen.main.brightness = nextBrightness
        displayedBrightness = nextBrightness
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

enum HiddenJavDBRandomMode: String, CaseIterable, Identifiable {
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

struct HiddenSpaceSettings: Equatable {
    var fourKHDRandomMode: HiddenRandomMode
    var javDBRandomMode: HiddenJavDBRandomMode
    var showJavDBDetailsByDefault: Bool
    var missAVDomain: String
}

extension Notification.Name {
    static let hiddenSpaceSettingsDidChange = Notification.Name("hiddenSpaceSettingsDidChange")
}

final class HiddenSpaceSettingsStore {
    static let shared = HiddenSpaceSettingsStore()

    private let userDefaults: UserDefaults
    private let notificationCenter: NotificationCenter
    private let fourKHDRandomModeKey = "hiddenSpace.4khd.randomMode"
    private let javDBRandomModeKey = "hiddenSpace.javdb.randomMode"
    private let showJavDBDetailsByDefaultKey = "hiddenSpace.javdb.showDetailsByDefault"
    private let missAVDomainKey = "hiddenSpace.missav.domain"
    private let legacyMissAVDomainKey = "hiddenSpace.javdb.missDomain"

    init(
        userDefaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        self.userDefaults = userDefaults
        self.notificationCenter = notificationCenter
    }

    func load() -> HiddenSpaceSettings {
        let fourKHDRawValue = userDefaults.string(forKey: fourKHDRandomModeKey)
        let javDBRawValue = userDefaults.string(forKey: javDBRandomModeKey)
        let missAVDomain = migratedMissAVDomain()

        return HiddenSpaceSettings(
            fourKHDRandomMode: fourKHDRawValue.flatMap(HiddenRandomMode.init(rawValue:)) ?? .single,
            javDBRandomMode: javDBRawValue.flatMap(HiddenJavDBRandomMode.init(rawValue:)) ?? .single,
            showJavDBDetailsByDefault: userDefaults.object(forKey: showJavDBDetailsByDefaultKey) as? Bool ?? false,
            missAVDomain: missAVDomain
        )
    }

    func save(_ settings: HiddenSpaceSettings) {
        userDefaults.set(settings.fourKHDRandomMode.rawValue, forKey: fourKHDRandomModeKey)
        userDefaults.set(settings.javDBRandomMode.rawValue, forKey: javDBRandomModeKey)
        userDefaults.set(settings.showJavDBDetailsByDefault, forKey: showJavDBDetailsByDefaultKey)
        userDefaults.set(settings.missAVDomain, forKey: missAVDomainKey)
        userDefaults.removeObject(forKey: legacyMissAVDomainKey)
        notificationCenter.post(name: .hiddenSpaceSettingsDidChange, object: nil)
    }

    private func migratedMissAVDomain() -> String {
        if let currentValue = userDefaults.string(forKey: missAVDomainKey) {
            return currentValue
        }

        guard let legacyValue = userDefaults.string(forKey: legacyMissAVDomainKey) else {
            return ""
        }

        userDefaults.set(legacyValue, forKey: missAVDomainKey)
        userDefaults.removeObject(forKey: legacyMissAVDomainKey)
        return legacyValue
    }
}

enum HiddenMissAVDomainConfiguration {
    static let defaultHost = "missav.ai"

    static func currentHost() -> String {
        resolvedHost(from: HiddenSpaceSettingsStore.shared.load().missAVDomain)
    }

    static func currentBaseURL() -> URL {
        URL(string: "https://\(currentHost())")!
    }

    static func currentMovieTemplate() -> String {
        "\(currentBaseURL().absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/cn/{{code}}"
    }

    static func resolvedHost(from rawValue: String?) -> String {
        normalizedHost(from: rawValue) ?? defaultHost
    }

    static func normalizedHost(from rawValue: String?) -> String? {
        guard let rawValue else { return nil }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: candidate),
              let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty else {
            return nil
        }

        if let port = components.port {
            return "\(host.lowercased()):\(port)"
        }

        return host.lowercased()
    }
}

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
