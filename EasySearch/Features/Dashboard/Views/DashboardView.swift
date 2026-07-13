import SwiftUI
import WebKit
import AVKit
@preconcurrency import AVFoundation
import UIKit

public struct DashboardView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var registry: FeatureRegistry
    private let isTabActive: Bool
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
                VStack(alignment: .leading, spacing: 22) {
                    if moduleFeatures.isEmpty && hiddenFeatures.isEmpty {
                        ESEmptyState(
                            title: "暂无模块",
                            message: nil,
                            systemImage: "square.grid.2x2"
                        )
                        .esCard()
                    } else {
                        if !moduleFeatures.isEmpty {
                            moduleWorkbenchSection
                        }

                        if !hiddenFeatures.isEmpty {
                            hiddenSpaceSection
                        }
                    }
                }
                .padding(.horizontal, ESUI.screenHorizontalPadding)
                .padding(.top, 14)
            }
            .esBottomTabPadding()
            .esScreenBackground()
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
                            saveHiddenSpaceSnapshotIfNeeded()
                        }
                } else {
                    Text("模块不存在")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationDestination(for: HiddenSpaceRoute.self) { route in
                hiddenSpaceDestination(for: route)
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
            if count > 0 {
                saveHiddenSpaceSnapshotIfNeeded()
            }
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

    private var moduleFeatures: [any AppFeature] {
        registry.moduleListFeatures
    }

    private var hiddenFeatures: [any AppFeature] {
        hiddenModulesUnlocked ? registry.hiddenFeatures : []
    }

    private var hiddenFeatureIDs: Set<String> {
        Set(registry.hiddenFeatures.map { $0.id })
    }

    private var moduleWorkbenchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ESSectionHeader(title: "模块工作台", trailing: "\(moduleFeatures.count)")

            LazyVStack(spacing: 12) {
                ForEach(moduleFeatures, id: \.id) { feature in
                    featureRow(for: feature, locked: false)
                }
            }
        }
    }

    private var hiddenSpaceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ESSectionHeader(title: "私密空间", trailing: "已解锁")

            LazyVStack(spacing: 12) {
                ForEach(hiddenFeatures, id: \.id) { feature in
                    featureRow(for: feature, locked: true)
                }
            }
        }
    }

    private var hiddenSpaceFeatureID: String {
        "hidden-space"
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
        feature.id == hiddenSpaceFeatureID && hasSavedHiddenSpacePath
    }

    private func openFeature(_ feature: any AppFeature) {
        if feature.id == hiddenSpaceFeatureID, restoreHiddenSpacePathIfPossible() {
            return
        }
        path.append(feature.id)
    }

    private func restoreHiddenSpacePathIfPossible() -> Bool {
        guard hasSavedHiddenSpacePath, savedHiddenSpacePath.count > 0 else {
            return false
        }
        path = savedHiddenSpacePath
        return true
    }

    private func saveHiddenSpaceSnapshotIfNeeded() {
        guard isInsideHiddenFeature, path.count > 0 else { return }
        savedHiddenSpacePath = path
        hasSavedHiddenSpacePath = true
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

    private func resetNavigationStack() {
        path = NavigationPath()
        navigationStackIdentity = UUID()
    }

    @ViewBuilder
    private func featureRow(for feature: any AppFeature, locked: Bool) -> some View {
        if shouldRestoreHiddenSpacePath(for: feature) {
            Button {
                openFeature(feature)
            } label: {
                FeatureRow(feature: feature, tone: locked ? .privateSpace : .standard, showsDisclosureIndicator: true)
            }
            .buttonStyle(ESCardButtonStyle())
        } else {
            NavigationLink(value: feature.id) {
                FeatureRow(feature: feature, tone: locked ? .privateSpace : .standard)
            }
            .buttonStyle(ESCardButtonStyle())
        }
    }

    private func moveModuleFeatures(fromOffsets: IndexSet, toOffset: Int) {
        registry.moveModuleFeatures(fromOffsets: fromOffsets, toOffset: toOffset)
    }
}

private struct FeatureRow: View {
    enum Tone {
        case standard
        case privateSpace
    }

    let feature: any AppFeature
    var tone: Tone = .standard
    var showsDisclosureIndicator = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            featureIcon

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(feature.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if tone == .privateSpace {
                        ESStatusPill(text: "私密", tone: .accent)
                    }
                }

                Text(feature.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: showsDisclosureIndicator ? "arrow.uturn.forward.circle.fill" : "chevron.right")
                .font(.system(size: showsDisclosureIndicator ? 20 : 13, weight: .semibold))
                .foregroundStyle(showsDisclosureIndicator ? Color.accentColor.opacity(0.75) : Color(.tertiaryLabel))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: ESUI.cardCornerRadius, style: .continuous)
                .fill(ESUI.elevatedBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ESUI.cardCornerRadius, style: .continuous)
                .stroke(tone == .privateSpace ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var featureIcon: some View {
        if feature.id == "uttracker" {
            UTModuleProgressIcon(color: feature.color)
        } else {
            ESFeatureIcon(systemName: feature.iconName, color: feature.color, size: 48)
        }
    }
}

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
        .accessibilityLabel("UT 本月进度")
        .accessibilityValue("\(displayText) 百分比")
    }

    private func refreshSummary() {
        summary = UTTrackerSnapshot.currentMonthSummary()
    }
}

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
