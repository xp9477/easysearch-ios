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
            List {
                if moduleFeatures.isEmpty && hiddenFeatures.isEmpty {
                    Section {
                        Label("暂无模块", systemImage: "square.grid.2x2")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    if !moduleFeatures.isEmpty {
                        Section {
                            ForEach(moduleFeatures, id: \.id) { feature in
                                featureRow(for: feature)
                            }
                            .onMove(perform: moveModuleFeatures)
                        }
                    }

                    if !hiddenFeatures.isEmpty {
                        Section("隐藏空间") {
                            ForEach(hiddenFeatures, id: \.id) { feature in
                                featureRow(for: feature)
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
    private func featureRow(for feature: any AppFeature) -> some View {
        if shouldRestoreHiddenSpacePath(for: feature) {
            Button {
                openFeature(feature)
            } label: {
                FeatureRow(feature: feature, showsDisclosureIndicator: true)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: feature.id) {
                FeatureRow(feature: feature)
            }
        }
    }

    private func moveModuleFeatures(fromOffsets: IndexSet, toOffset: Int) {
        registry.moveModuleFeatures(fromOffsets: fromOffsets, toOffset: toOffset)
    }
}

private struct FeatureRow: View {
    let feature: any AppFeature
    var showsDisclosureIndicator = false

    var body: some View {
        HStack(spacing: 14) {
            featureIcon

            Text(feature.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            if showsDisclosureIndicator {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
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
