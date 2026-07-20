import SwiftUI

/// Central registry for all available features in the app.
public class FeatureRegistry: ObservableObject {
    @Published public var features: [any AppFeature] = []
    @Published private(set) public var moduleFeatureOrderIDs: [String] = []

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
    
    public init() {
        registerDefaultFeatures()
    }
    
    private func registerDefaultFeatures() {
        features.append(EasySearchFeature())
        features.append(UTTrackerFeature())
        features.append(ExpenseAssistantFeature())
        features.append(GitHubUpdatesFeature())
        features.append(QingLongFeature())
        features.append(ImageTranslateFeature())
        features.append(EmailAssistantFeature())
        features.append(UtilitiesFeature())
        features.append(HiddenSpaceFeature())
        reloadModuleFeatureOrder()
    }

    public func moveModuleFeatures(fromOffsets: IndexSet, toOffset: Int) {
        var order = moduleFeatureOrderIDs
        order.move(fromOffsets: fromOffsets, toOffset: toOffset)
        moduleFeatureOrderIDs = order
        userDefaults.set(order, forKey: moduleOrderDefaultsKey)
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

public struct HiddenSpaceFeature: AppFeature {
    public var id: String = "hidden-space"
    public var title: String = "隐藏空间"
    public var summary: String = "保留给后续隐藏模块和特殊入口。"
    public var iconName: String = "eye.slash"
    public var color: Color = .purple
    public var placement: AppFeaturePlacement = .hiddenModule

    public init() {}

    public var entryView: AnyView {
        AnyView(HiddenSpaceView())
    }
}
