import SwiftUI

public struct DashboardView: View {
    public var isTabActive: Bool = true

    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var registry: FeatureRegistry
    @EnvironmentObject private var statusCenter: FeatureStatusCenter

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
                    if moduleFeatures.isEmpty && unlockedHiddenFeatures.isEmpty {
                        ESEmptyState(
                            title: "暂无模块",
                            message: "功能模块会显示在这里。",
                            systemImage: "square.grid.2x2"
                        )
                        .esCard()
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
                .padding(.top, ESUI.Space.md)
                .padding(.bottom, ESUI.Space.lg)
            }
            .esBottomTabPadding()
            .esScreenBackground()
            .navigationTitle("工作台")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("工作台")
                        .font(.headline)
                        .opacity(0.01)
                        .onTapGesture {
                            unlockHiddenModulesIfNeeded()
                        }
                        .accessibilityHidden(true)
                }
            }
            .navigationDestination(for: String.self) { featureId in
                if let feature = (moduleFeatures + unlockedHiddenFeatures).first(where: { $0.id == featureId }) {
                    feature.entryView
                        .environmentObject(hidden4KHDViewModel)
                        .environmentObject(hiddenJavDBViewModel)
                        .environmentObject(hiddenPresentationState)
                        .onDisappear {
                            saveHiddenSpaceSnapshotIfNeeded()
                            collapseHiddenSpaceAfterExitIfNeeded()
                        }
                } else {
                    ESEmptyState(title: "模块不存在", systemImage: "questionmark.circle")
                }
            }
            .navigationDestination(for: HiddenSpaceRoute.self) { route in
                hiddenSpaceDestination(for: route)
            }
            .id(navigationStackIdentity)
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
            await statusCenter.refresh()
        }
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
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            ESSectionHeader(title: group.title, trailing: "\(features.count)")

            VStack(spacing: ESUI.Space.xs) {
                ForEach(Array(features.enumerated()), id: \.element.id) { index, feature in
                    Button {
                        openFeature(feature)
                    } label: {
                        workbenchRow(for: feature, isPrivate: false)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if features.count > 1 {
                            if index > 0 {
                                Button("上移") {
                                    moveFeature(feature, in: group, by: -1)
                                }
                            }
                            if index < features.count - 1 {
                                Button("下移") {
                                    moveFeature(feature, in: group, by: 1)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var privateSection: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            ESSectionHeader(title: "私密", subtitle: "离开后将自动锁定", trailing: "已解锁")

            VStack(spacing: ESUI.Space.xs) {
                ForEach(unlockedHiddenFeatures, id: \.id) { feature in
                    Button {
                        openFeature(feature)
                    } label: {
                        workbenchRow(for: feature, isPrivate: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func workbenchRow(for feature: any AppFeature, isPrivate: Bool) -> some View {
        HStack(spacing: ESUI.Space.sm) {
            if feature.id == "uttracker" {
                UTModuleProgressIcon(color: feature.color)
            } else {
                ESFeatureIcon(systemName: feature.iconName, color: feature.color, size: 40)
            }

            VStack(alignment: .leading, spacing: ESUI.Space.xxs) {
                HStack(spacing: ESUI.Space.xs) {
                    Text(feature.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if isPrivate {
                        ESStatusBadge(text: "私密", tone: .accent)
                    }
                }

                Text(feature.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: ESUI.Space.xs)

            if !isPrivate {
                let status = statusCenter.summary(for: feature.id)
                ESStatusBadge(text: status.text, tone: .from(kind: status.kind))
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(ESUI.Space.md)
        .background(
            RoundedRectangle(cornerRadius: ESUI.cardCornerRadius, style: .continuous)
                .fill(ESUI.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ESUI.cardCornerRadius, style: .continuous)
                .stroke(isPrivate ? Color.accentColor.opacity(0.18) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
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
        case .settings:
            HiddenSpaceSettingsDetailView()
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

// MARK: - UT Progress Icon

private struct UTModuleProgressIcon: View {
    let color: Color

    @Environment(\.scenePhase) private var scenePhase
    @State private var summary = UTTrackerSnapshot.currentMonthSummary()

    private var progress: Double {
        min(max(summary.fullMonthProgress, 0), 1)
    }

    private var percentValue: Int {
        Int((summary.fullMonthProgress * 100).rounded())
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
