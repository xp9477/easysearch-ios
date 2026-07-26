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

    public init(isTabActive: Bool = true) {
        self.isTabActive = isTabActive
    }

    public var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: ESUI.sectionSpacing) {
                    attentionBanner

                    if moduleFeatures.isEmpty && unlockedHiddenFeatures.isEmpty {
                        ESEmptyState(
                            title: "暂无模块",
                            systemImage: "square.grid.2x2"
                        )
                    } else {
                        ForEach(AppFeatureGroup.allCases) { group in
                            let features = registry.moduleFeatures(in: group)
                            if !features.isEmpty {
                                moduleGroupSection(group: group, features: features)
                            }
                        }

                        if !unlockedHiddenFeatures.isEmpty {
                            privateSection
                        }
                    }
                }
                .padding(.horizontal, ESUI.screenHorizontalPadding)
                .padding(.top, ESUI.Space.sm)
                .padding(.bottom, ESUI.Space.lg)
            }
            .esBottomTabPadding()
            .esScreenBackground()
            .navigationTitle("工作台")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    // Near-invisible hit target around the nav center title.
                    Text("工作台")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .frame(minWidth: 160, minHeight: 44)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            unlockHiddenModulesIfNeeded()
                        }
                        .accessibilityLabel("工作台")
                        .accessibilityHint("连点可解锁私密入口")
                }
            }
            .navigationDestination(for: String.self) { featureId in
                // Keep resolving hidden features even after the private section collapses,
                // so nested routes (search / detail) don't flash "模块不存在".
                if let feature = resolvedFeature(for: featureId) {
                    feature.entryView
                        .environmentObject(hidden4KHDViewModel)
                        .environmentObject(hiddenJavDBViewModel)
                        .environmentObject(hiddenPresentationState)
                } else {
                    ESEmptyState(title: "模块不存在", systemImage: "questionmark.circle")
                }
            }
            .navigationDestination(for: HiddenSpaceRoute.self) { route in
                hiddenSpaceDestination(for: route)
            }
            .id(navigationStackIdentity)
            .onChange(of: path.count) { count in
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
        .onChange(of: scenePhase) { phase in
            guard phase != .active else { return }
            lockHiddenModulesForPrivacyIfNeeded()
        }
        .onChange(of: isTabActive) { active in
            if active {
                saveHiddenSpaceSnapshotIfNeeded()
            } else {
                collapseHiddenSpaceOnTabLeaveIfNeeded()
            }
        }
        .task(id: isTabActive) {
            guard isTabActive else { return }
            consumePendingWorkbenchRoute()
            await statusCenter.refresh()
        }
        .onChange(of: navigationState.pendingWorkbenchFeatureID) { _ in
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

    private func moduleGroupSection(group: AppFeatureGroup, features: [any AppFeature]) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: ESUI.Space.sm),
            GridItem(.flexible(), spacing: ESUI.Space.sm)
        ]

        return VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            Text(group.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)

            LazyVGrid(columns: columns, spacing: ESUI.Space.sm) {
                ForEach(Array(features.enumerated()), id: \.element.id) { index, feature in
                    Button {
                        openFeature(feature)
                    } label: {
                        moduleTile(for: feature, isPrivate: false)
                    }
                    .buttonStyle(ESCardButtonStyle())
                    .contextMenu {
                        if features.count > 1 {
                            if index > 0 {
                                Button("上移") { moveFeature(feature, in: group, by: -1) }
                            }
                            if index < features.count - 1 {
                                Button("下移") { moveFeature(feature, in: group, by: 1) }
                            }
                        }
                    }
                }
            }
        }
    }

    private var privateSection: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.xs) {
            Text("私密")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)

            ForEach(unlockedHiddenFeatures, id: \.id) { feature in
                Button {
                    openFeature(feature)
                } label: {
                    moduleTile(for: feature, isPrivate: true, isWide: true)
                }
                .buttonStyle(ESCardButtonStyle())
            }
        }
    }

    private func moduleTile(for feature: any AppFeature, isPrivate: Bool, isWide: Bool = false) -> some View {
        let customIcon: AnyView? = {
            switch feature.id {
            case "uttracker":
                return AnyView(UTModuleProgressIcon(color: feature.color))
            case "training-log":
                return AnyView(TrainingModuleStatusIcon(color: feature.color))
            default:
                return nil
            }
        }()
        let badge: Int? = feature.id == "expense-assistant" ? expensePendingCount : nil

        return ESModuleTile(
            title: feature.title,
            systemImage: feature.iconName,
            featureID: feature.id,
            badgeCount: isPrivate ? nil : badge,
            isWide: isWide,
            customIcon: customIcon
        )
        .overlay(
            RoundedRectangle(cornerRadius: ESUI.tileCornerRadius, style: .continuous)
                .stroke(
                    isPrivate ? Color.secondary.opacity(0.35) : Color.clear,
                    style: StrokeStyle(lineWidth: isPrivate ? 1 : 0, dash: isPrivate ? [5, 4] : [])
                )
        )
    }

    private var expensePendingCount: Int {
        let snapshot = ExpenseAssistantLocalStore().loadSnapshot()
        let monthly = ExpenseAssistantReminderEngine.overdueMonthlyClaims(in: snapshot, asOf: Date()).count
        let travel = ExpenseAssistantReminderEngine.overdueTravelClaims(in: snapshot, asOf: Date()).count
        return monthly + travel
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

    private func moveFeature(_ feature: any AppFeature, in group: AppFeatureGroup, by offset: Int) {
        let features = registry.moduleFeatures(in: group)
        guard let index = features.firstIndex(where: { $0.id == feature.id }) else { return }
        let target = index + offset
        guard features.indices.contains(target) else { return }
        registry.moveModuleFeatures(in: group, fromOffsets: IndexSet(integer: index), toOffset: offset > 0 ? target + 1 : target)
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
                    title: "云同步异常:\(statusCenter.cloudSummary.text)",
                    systemImage: "icloud.slash",
                    tone: .danger
                )
            }
            .buttonStyle(.plain)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

// MARK: - Training Status Icon

private struct TrainingModuleStatusIcon: View {
    let color: Color

    @Environment(\.scenePhase) private var scenePhase
    @State private var trainedToday = false
    @State private var monthDayCount = 0

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle()
                    .fill(color.opacity(trainedToday ? 0.16 : 0.1))
                    .frame(width: 40, height: 40)

                Image(systemName: trainedToday ? "flame.fill" : "flame")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(trainedToday ? color : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }

            if trainedToday {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(ESUI.success)
                    .background(Circle().fill(ESUI.surface).frame(width: 12, height: 12))
                    .offset(x: 3, y: 2)
            } else if monthDayCount > 0 {
                Text("\(monthDayCount)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(ESUI.fill))
                    .offset(x: 4, y: 2)
            }
        }
        .frame(width: 40, height: 40)
        .animation(ESMotion.quick, value: trainedToday)
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .trainingLogDidChange)) { _ in
            refresh()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { refresh() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("训练记录")
        .accessibilityValue(trainedToday ? "今天已训练" : "本月 \(monthDayCount) 天")
    }

    private func refresh() {
        let snapshot = TrainingLogLocalStore().loadSnapshot()
        let todayKey = TrainingLogCalendar.dayKey(for: Date())
        trainedToday = (snapshot.days[todayKey]?.lines.isEmpty == false)

        let monthPrefix = String(todayKey.prefix(7))
        monthDayCount = snapshot.days
            .filter { $0.key.hasPrefix(monthPrefix) && !$0.value.lines.isEmpty }
            .count
    }
}

// MARK: - UT Progress Icon

private struct UTModuleProgressIcon: View {
    let color: Color

    @Environment(\.scenePhase) private var scenePhase
    @State private var summary = UTTrackerSnapshot.currentMonthSummary()

    private var progress: Double {
        min(max(summary.elapsedMonthProgress, 0), 1)
    }

    private var percentValue: Int {
        Int((summary.elapsedMonthProgress * 100).rounded())
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
                .fill(color.opacity(0.1))
                .frame(width: 40, height: 40)

            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 3)
                .frame(width: 32, height: 32)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 32, height: 32)
                .rotationEffect(.degrees(-90))

            Text(displayText)
                .font(.system(size: displayText.count >= 3 ? 9 : 10, weight: .bold, design: .rounded))
                .foregroundStyle(summary.totalHours <= 0.01 ? .secondary : .primary)
        }
        .frame(width: 40, height: 40)
        .onAppear { refreshSummary() }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            refreshSummary()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { refreshSummary() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("UT 本月进度")
        .accessibilityValue("\(displayText) 百分比")
    }

    private func refreshSummary() {
        summary = UTTrackerSnapshot.currentMonthSummary()
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
