import SwiftUI

public struct UtilitiesFeature: AppFeature {
    public var id: String = "utilities"
    public var title: String = "实用工具"
    public var summary: String = "汇率等小工具集合。"
    public var iconName: String = "hammer.fill"
    public var color: Color = Color(red: 0.35, green: 0.40, blue: 0.48)
    public var placement: AppFeaturePlacement = .moduleList
    public var group: AppFeatureGroup? = .utilities

    public init() {}

    public var entryView: AnyView {
        AnyView(UtilitiesView())
    }

    @MainActor
    public func statusSummary() async -> FeatureStatusSummary {
        FeatureStatusSummary(kind: .ready, text: "可用")
    }

}
