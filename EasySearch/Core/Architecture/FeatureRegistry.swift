import Foundation
import SwiftUI

// MARK: - Feature Registry

public class FeatureRegistry: ObservableObject {
    @Published public var features: [any AppFeature] = []
    @Published public private(set) var moduleFeatureOrderIDs: [String] = []

    private let userDefaults = UserDefaults.standard
    private let moduleOrderDefaultsKey = "featureRegistry.moduleFeatureOrder"

    public var primaryTabFeatures: [any AppFeature] {
        features.filter { $0.placement == .primaryTab }
    }

    public var moduleListFeatures: [any AppFeature] {
        orderedFeatures(from: features.filter { $0.placement == .moduleList })
    }

    public var hiddenFeatures: [any AppFeature] {
        features.filter { $0.placement == .hiddenModule }
    }

    /// Module features belonging to a capability group, ordered by stored order.
    public func moduleFeatures(in group: AppFeatureGroup) -> [any AppFeature] {
        moduleListFeatures.filter { $0.group == group }
    }

    public init() {
        features.append(EasySearchFeature())
        features.append(UTTrackerFeature())
        features.append(TrainingLogFeature())
        features.append(ExpenseAssistantFeature())
        features.append(QingLongFeature())
        features.append(CurrencyFeature())
        features.append(WebDAVFeature())
        features.append(HiddenSpaceFeature())
        reloadModuleFeatureOrder()
    }

    public func moveModuleFeatures(fromOffsets: IndexSet, toOffset: Int) {
        var order = moduleFeatureOrderIDs
        order.move(fromOffsets: fromOffsets, toOffset: toOffset)
        moduleFeatureOrderIDs = order
        userDefaults.set(order, forKey: moduleOrderDefaultsKey)
    }

    /// Reorder features within a single group while preserving relative order of other groups.
    public func moveModuleFeatures(in group: AppFeatureGroup, fromOffsets: IndexSet, toOffset: Int) {
        let groupIDs = moduleFeatures(in: group).map(\.id)
        guard !groupIDs.isEmpty else { return }

        var mutableGroupIDs = groupIDs
        mutableGroupIDs.move(fromOffsets: fromOffsets, toOffset: toOffset)

        var nextOrder: [String] = []
        var groupCursor = 0
        let groupIDSet = Set(groupIDs)

        for id in moduleFeatureOrderIDs {
            if groupIDSet.contains(id) {
                if groupCursor < mutableGroupIDs.count {
                    nextOrder.append(mutableGroupIDs[groupCursor])
                    groupCursor += 1
                }
            } else {
                nextOrder.append(id)
            }
        }

        while groupCursor < mutableGroupIDs.count {
            nextOrder.append(mutableGroupIDs[groupCursor])
            groupCursor += 1
        }

        moduleFeatureOrderIDs = nextOrder
        userDefaults.set(nextOrder, forKey: moduleOrderDefaultsKey)
    }

    private func reloadModuleFeatureOrder() {
        let defaultIDs = features
            .filter { $0.placement == .moduleList }
            .map(\.id)
        let storedIDs = userDefaults.stringArray(forKey: moduleOrderDefaultsKey) ?? []
        let normalizedStoredIDs = storedIDs.filter { defaultIDs.contains($0) }
        let missingIDs = defaultIDs.filter { !normalizedStoredIDs.contains($0) }
        let normalizedOrder = normalizedStoredIDs + missingIDs

        moduleFeatureOrderIDs = normalizedOrder
        userDefaults.set(normalizedOrder, forKey: moduleOrderDefaultsKey)
    }

    private func orderedFeatures(from unorderedFeatures: [any AppFeature]) -> [any AppFeature] {
        let fallbackIndexByID = Dictionary(
            uniqueKeysWithValues: unorderedFeatures.enumerated().map { ($1.id, $0) }
        )
        let orderIndexByID = Dictionary(
            uniqueKeysWithValues: moduleFeatureOrderIDs.enumerated().map { ($1, $0) }
        )

        return unorderedFeatures.sorted { lhs, rhs in
            let lhsIndex = orderIndexByID[lhs.id] ?? (moduleFeatureOrderIDs.count + (fallbackIndexByID[lhs.id] ?? 0))
            let rhsIndex = orderIndexByID[rhs.id] ?? (moduleFeatureOrderIDs.count + (fallbackIndexByID[rhs.id] ?? 0))
            return lhsIndex < rhsIndex
        }
    }
}

// MARK: - Feature Status Center

@MainActor
public final class FeatureStatusCenter: ObservableObject {
    public static let shared = FeatureStatusCenter()

    @Published public private(set) var summaries: [String: FeatureStatusSummary] = [:]
    @Published public private(set) var cloudSummary = FeatureStatusSummary(kind: .needsConfiguration, text: "仅本地")
    @Published public private(set) var qingLongSummary = FeatureStatusSummary(kind: .needsConfiguration, text: "未连接")

    /// Optional registry used so status refresh queries each feature instead of hardcoding stores here.
    weak var registry: FeatureRegistry?

    private init() {}

    public func attach(registry: FeatureRegistry) {
        self.registry = registry
    }

    public func summary(for featureID: String) -> FeatureStatusSummary {
        summaries[featureID] ?? .ready
    }

    public func refresh() async {
        let cloud = CloudSyncViewModel.shared
        await cloud.prepareIfNeeded()

        if !cloud.isCloudConfigured {
            cloudSummary = FeatureStatusSummary(kind: .empty, text: "仅本地")
        } else if cloud.isCloudAuthenticated {
            let email = cloud.cloudUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            cloudSummary = FeatureStatusSummary(
                kind: .ready,
                text: email.isEmpty ? "已登录" : email
            )
        } else {
            cloudSummary = FeatureStatusSummary(kind: .needsConfiguration, text: "未登录")
        }

        let qingLong = QingLongPanelLocalStore().loadProfile()
        qingLongSummary = qingLong == nil
            ? FeatureStatusSummary(kind: .needsConfiguration, text: "未连接")
            : FeatureStatusSummary(kind: .ready, text: "已连接")

        var next: [String: FeatureStatusSummary] = [:]
        let features = registry?.features ?? []
        for feature in features where feature.placement == .moduleList || feature.placement == .hiddenModule {
            next[feature.id] = await feature.statusSummary()
        }

        // Keep cross-cutting aliases used by Settings UI.
        if next["qinglong-management"] == nil {
            next["qinglong-management"] = qingLongSummary
        }

        summaries = next
    }
}
