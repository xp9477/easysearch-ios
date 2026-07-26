import SwiftUI

public struct QingLongFeature: AppFeature {
    public var id: String = "qinglong-management"
    public var title: String = "青龙管理"
    public var summary: String = "连接青龙面板，管理任务与订阅。"
    public var iconName: String = "server.rack"
    public var color: Color = .green
    public var placement: AppFeaturePlacement = .moduleList
    public var group: AppFeatureGroup? = .connectAndOps

    public init() {}

    public var entryView: AnyView {
        AnyView(QingLongView())
    }

    @MainActor
    public func statusSummary() async -> FeatureStatusSummary {
        let profile = QingLongPanelLocalStore().loadProfile()
        if profile == nil {
            return FeatureStatusSummary(kind: .needsConfiguration, text: "未连接")
        }
        return FeatureStatusSummary(kind: .ready, text: "已连接")
    }

}
