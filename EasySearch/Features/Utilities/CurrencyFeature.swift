import SwiftUI

/// 汇率换算直达入口(取代原"实用工具"壳)。
public struct CurrencyFeature: AppFeature {
    public var id: String = "currency"
    public var title: String = "汇率"
    public var summary: String = "多币种实时汇率换算。"
    public var iconName: String = "yensign.circle"
    public var color: Color = .gray
    public var placement: AppFeaturePlacement = .moduleList
    public var group: AppFeatureGroup? = .utilities

    public init() {}

    public var entryView: AnyView {
        AnyView(CurrencyConverterView())
    }

    @MainActor
    public func statusSummary() async -> FeatureStatusSummary {
        FeatureStatusSummary(kind: .ready, text: "可用")
    }
}
