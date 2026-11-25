import SwiftUI

public struct DashboardView: View {
    public var isTabActive: Bool = true

    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var registry: FeatureRegistry
    @EnvironmentObject private var statusCenter: FeatureStatusCenter
    @EnvironmentObject private var navigationState: AppNavigationState

    @StateObject private var hidden4KHDViewModel = HiddenSpaceViewModel()
    @StateObject private var hiddenJavDBViewModel = HiddenJavDBViewModel()
    @StateObject private var hiddenPresentationState = HiddenSpacePresentationState()
    @State private var path = NavigationPath()
    @State private var savedHiddenSpacePath = NavigationPath()
    @State private var hasSavedHiddenSpacePath = false
    @State private var navigationStackIdentity = UUID()
    @State private var dashboardTapCount = 0
    @State private var hiddenModulesUnlocked = false
    @State private var selectedFeatureID: String?
    @State private var snapshot: WorkbenchSnapshot?
    @ObservedObject private var storage = WebDAVSettingsStore.shared

    public init(isTabActive: Bool = true) {
        self.isTabActive = isTabActive
    }

    public var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: ESUI.sectionSpacing) {
                    Button(action: unlockHiddenModulesIfNeeded) {
                        Text("工作台")
                            .font(.largeTitle.bold())
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityHint("连续激活五次可解锁私密入口")

                    attentionBanner

                    if moduleFeatures.isEmpty && unlockedHiddenFeatures.isEmpty {
                        ESEmptyState(
                            title: "暂无模块",
                            systemImage: "square.grid.2x2"
                        )
                    } else {
                        let records = moduleFeatures.filter { $0.group == .recordsAndProgress }
                        let tools = moduleFeatures.filter { $0.group != .recordsAndProgress }
                        if !records.isEmpty { moduleGroupSection(title: "记录", features: records) }
                        if !tools.isEmpty { moduleGroupSection(title: "工具", features: tools) }

                        if !unlockedHiddenFeatures.isEmpty {
                            privateSection
                        }
                    }
                }
                .padding(.horizontal, ESUI.Space.lg)
                .padding(.top, ESUI.Space.sm)
                .padding(.bottom, ESUI.Space.lg)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .esScreenBackground()
            .navigationTitle("工作台")
            .toolbarVisibility(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { featureId in
                // Keep resolving hidden features even after the private section collapses,
                // so nested routes (search / detail) don't flash "模块不存在".
                if let feature = resolvedFeature(for: featureId) {
                    feature.entryView
                        .environmentObject(hidden4KHDViewModel)
                        .environmentObject(hiddenJavDBViewModel)
                        .environmentObject(hiddenPresentationState)
                        .toolbarVisibility(.visible, for: .navigationBar)
                } else {
                    ESEmptyState(title: "模块不存在", systemImage: "questionmark.circle")
                }
            }
            .navigationDestination(for: HiddenSpaceRoute.self) { route in
                hiddenSpaceDestination(for: route)
            }
            .id(navigationStackIdentity)
            .onChange(of: path.count) { _, count in
                // Only collapse/lock when the whole stack returns to the dashboard root.
                // Nested pushes used to fire onDisappear on the feature root and wipe unlock state.
                if count == 0 {
                    collapseHiddenSpaceAfterExitIfNeeded()
                }
            }
        }
        .overlay {
            if scenePhase != .active && shouldMaskHiddenFeatures {
                Color.black.opacity(0.92).ignoresSafeArea()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshSnapshot() }
            else { lockHiddenModulesForPrivacyIfNeeded() }
        }
        .onChange(of: isTabActive) { _, active in
            if active {
                saveHiddenSpaceSnapshotIfNeeded()
            } else {
                collapseHiddenSpaceOnTabLeaveIfNeeded()
            }
        }
        .task(id: isTabActive) {
            guard isTabActive else { return }
            consumePendingWorkbenchRoute()
            refreshSnapshot()
            await statusCenter.refresh()
        }
        .onChange(of: path.isEmpty) {
            if path.isEmpty && isTabActive { refreshSnapshot() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .utTrackerEntriesDidChange)) { _ in refreshSnapshot() }
        .onReceive(NotificationCenter.default.publisher(for: .trainingLogDidChange)) { _ in refreshSnapshot() }
        .onReceive(NotificationCenter.default.publisher(for: .expenseAssistantDataDidChange)) { _ in refreshSnapshot() }
        .onChange(of: navigationState.pendingWorkbenchFeatureID) {
            guard isTabActive else { return }
            consumePendingWorkbenchRoute()
        }
    }

    private func consumePendingWorkbenchRoute() {
        guard let featureID = navigationState.pendingWorkbenchFeatureID else { return }
        navigationState.pendingWorkbenchFeatureID = nil
        guard let feature = registry.moduleListFeatures.first(where: { $0.id == featureID }) else { return }
        path = NavigationPath()
        openFeature(feature)
    }

    // MARK: - Data

    private var moduleFeatures: [any AppFeature] {
        registry.moduleListFeatures
    }

    private var unlockedHiddenFeatures: [any AppFeature] {
        hiddenModulesUnlocked ? registry.hiddenFeatures : []
    }

    private var hiddenFeatureIDs: Set<String> {
        Set(registry.hiddenFeatures.map(\.id))
    }

    private func resolvedFeature(for featureId: String) -> (any AppFeature)? {
        if let feature = (moduleFeatures + unlockedHiddenFeatures).first(where: { $0.id == featureId }) {
            return feature
        }
        // While a hidden feature is still selected (or its path is being restored), keep
        // resolving it even if the private section was collapsed by privacy rules.
        if hiddenFeatureIDs.contains(featureId) {
            return registry.hiddenFeatures.first(where: { $0.id == featureId })
        }
        return nil
    }

    private var shouldMaskHiddenFeatures: Bool {
        hiddenModulesUnlocked || isInsideHiddenFeature
    }

    private var isInsideHiddenFeature: Bool {
        if let selectedFeatureID, hiddenFeatureIDs.contains(selectedFeatureID) {
            return true
        }
        return false
    }

    // MARK: - Sections

    private func moduleGroupSection(title: String, features: [any AppFeature]) -> some View {
        VStack(alignment: .leading, spacing: ESUI.Space.xs) {
            Text(title)
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                ForEach(Array(features.enumerated()), id: \.element.id) { index, feature in
                    if index != 0 { Divider().padding(.leading, ESUI.Space.huge + ESUI.Space.sm) }
                    let status = workbenchStatus(for: feature)
                    Button {
                        openFeature(feature)
                    } label: {
                        ESNavigationRow(
                            title: feature.title, icon: feature.iconName, color: feature.color,
                            status: status.text, needsAttention: status.needsAttention, showsChevron: true
                        )
                        .padding(.horizontal, ESUI.Space.md)
                        .padding(.vertical, ESUI.Space.xs)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(ESCardButtonStyle())
                    .contextMenu {
                        if index > 0 {
                            Button("上移") { moveFeature(at: index, in: features, by: -1) }
                        }
                        if index + 1 < features.count {
                            Button("下移") { moveFeature(at: index, in: features, by: 1) }
                        }
                    }
                }
            }
            .esSurface()
        }
    }

    private var privateSection: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.xs) {
            Text("私密").font(.title3.bold()).accessibilityAddTraits(.isHeader)
            ForEach(unlockedHiddenFeatures, id: \.id) { feature in
                Button {
                    openFeature(feature)
                } label: {
                    ESNavigationRow(title: feature.title, icon: feature.iconName, color: feature.color, showsChevron: true)
                        .padding(.horizontal, ESUI.Space.md)
                        .padding(.vertical, ESUI.Space.xs)
                        .esSurface()
                }
                .buttonStyle(ESCardButtonStyle())
            }
        }
    }

    private func workbenchStatus(for feature: any AppFeature) -> (text: String?, needsAttention: Bool) {
        switch feature.id {
        case "uttracker":
            guard let snapshot else { return (nil, false) }
            return ("本月进度 \(snapshot.utProgress.formatted(.percent.precision(.fractionLength(0))))", false)
        case "training-log":
            guard let snapshot else { return (nil, false) }
            return (snapshot.trainedToday ? "今天已记录" : "今天未记录", false)
        case "expense-assistant":
            guard let snapshot else { return (nil, false) }
            return snapshot.overdueExpenses > 0 ? ("\(snapshot.overdueExpenses) 笔逾期", true) : (nil, false)
        case "webdav":
            return (storage.locations.isEmpty ? "未配置" : "\(storage.locations.count) 个位置", false)
        default:
            let status = statusCenter.summary(for: feature.id)
            switch status.kind {
            case .ready, .empty: return (nil, false)
            default: return (status.text, status.kind == .recoverableFailure || status.kind == .attentionNeeded)
            }
        }
    }

    private func refreshSnapshot() {
        guard isTabActive else { return }
        snapshot = WorkbenchSnapshot.load()
    }

    // MARK: - Actions

    private func unlockHiddenModulesIfNeeded() {
        dashboardTapCount += 1
        guard dashboardTapCount >= 5 else { return }
        dashboardTapCount = 0
        hiddenModulesUnlocked = true
    }

    private func lockHiddenModulesForPrivacyIfNeeded() {
        guard shouldMaskHiddenFeatures else { return }
        saveHiddenSpaceSnapshotIfNeeded()
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
        saveHiddenSpaceSnapshotIfNeeded()
        dashboardTapCount = 0
        hiddenModulesUnlocked = false
        selectedFeatureID = nil
        resetNavigationStack()
    }

    private func shouldRestoreHiddenSpacePath(for feature: any AppFeature) -> Bool {
        feature.placement == .hiddenModule && hasSavedHiddenSpacePath
    }

    private func openFeature(_ feature: any AppFeature) {
        selectedFeatureID = feature.id
        if shouldRestoreHiddenSpacePath(for: feature), restoreHiddenSpacePathIfPossible() {
            return
        }
        path.append(feature.id)
    }

    private func restoreHiddenSpacePathIfPossible() -> Bool {
        guard hasSavedHiddenSpacePath else { return false }
        path = savedHiddenSpacePath
        hasSavedHiddenSpacePath = false
        savedHiddenSpacePath = NavigationPath()
        return true
    }

    private func saveHiddenSpaceSnapshotIfNeeded() {
        guard isInsideHiddenFeature, !path.isEmpty else { return }
        savedHiddenSpacePath = path
        hasSavedHiddenSpacePath = true
    }

    private func resetNavigationStack() {
        path = NavigationPath()
        navigationStackIdentity = UUID()
    }

    private func moveFeature(at index: Int, in features: [any AppFeature], by offset: Int) {
        let target = index + offset
        guard features.indices.contains(target) else { return }
        registry.moveModuleFeatures(ids: features.map(\.id), fromOffsets: IndexSet(integer: index), toOffset: offset > 0 ? target + 1 : target)
    }

    @ViewBuilder
    private func hiddenSpaceDestination(for route: HiddenSpaceRoute) -> some View {
        switch route {
        case .javDBSettings:
            HiddenJavDBSettingsDetailView()
        case .fourKHD:
            Hidden4KHDFeatureView(viewModel: hidden4KHDViewModel)
        case .fourKHDFavorites:
            Hidden4KHDFavoritesView(viewModel: hidden4KHDViewModel, presentationState: hiddenPresentationState)
        case .fourKHDFavoriteImages:
            HiddenFavoriteImagesView(viewModel: hidden4KHDViewModel, presentationState: hiddenPresentationState)
        case .fourKHDFavoriteAlbums:
            HiddenFavoriteAlbumsView(viewModel: hidden4KHDViewModel)
        case let .fourKHDAlbum(album):
            HiddenAlbumDetailView(album: album, viewModel: hidden4KHDViewModel, presentationState: hiddenPresentationState)
        case .javDB:
            HiddenJavDBFeatureView(viewModel: hiddenJavDBViewModel)
        case .javDBFavorites:
            HiddenJavDBFavoriteMoviesView(viewModel: hiddenJavDBViewModel, presentationState: hiddenPresentationState)
        case let .javDBMovie(movie):
            HiddenJavDBMovieDetailView(movie: movie, viewModel: hiddenJavDBViewModel, presentationState: hiddenPresentationState)
        }
    }
}

// MARK: - Attention Banner

private extension DashboardView {
    @ViewBuilder
    var attentionBanner: some View {
        if statusCenter.cloudSummary.kind == .recoverableFailure
            || statusCenter.cloudSummary.kind == .offlineOrUnavailable {
            Button {
                navigationState.openSettings(.cloudSync)
            } label: {
                ESStatusBanner(
                    title: "云同步异常：\(statusCenter.cloudSummary.text)",
                    message: "轻点前往设置查看云端配置与同步状态",
                    systemImage: "icloud.slash",
                    tone: .danger
                )
            }
            .buttonStyle(.plain)
            .transition(ESMotion.reduceMotionSafeTopBanner)
        }
    }
}

// MARK: - Workbench Summary

private struct WorkbenchSnapshot {
    let utProgress: Double
    let trainedToday: Bool
    let overdueExpenses: Int

    static func load(asOf now: Date = .now) -> Self {
        let ut = UTTrackerSnapshot.currentMonthSummary()
        let training = TrainingLogLocalStore().loadSnapshot()
        let expenses = ExpenseAssistantLocalStore().loadSnapshot()
        let monthly = ExpenseAssistantReminderEngine.overdueMonthlyClaims(in: expenses, asOf: now).count
        let travel = ExpenseAssistantReminderEngine.overdueTravelClaims(in: expenses, asOf: now).count
        return Self(
            utProgress: max(ut.elapsedMonthProgress, 0),
            trainedToday: training.days[TrainingLogCalendar.dayKey(for: now)]?.hasTraining == true,
            overdueExpenses: monthly + travel
        )
    }
}

// MARK: - Shared Preview Model (used by Hidden modules)

struct PreviewImage: Identifiable, Hashable {
    let index: Int
    let urls: [URL]
    var autoPlaySlideshow = false

    var id: String {
        guard !urls.isEmpty else { return "empty-\(index)" }
        let safeIndex = min(max(index, 0), urls.count - 1)
        return "\(safeIndex)-\(urls[safeIndex].absoluteString)-\(autoPlaySlideshow ? "slideshow" : "manual")"
    }
}
