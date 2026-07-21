import SwiftUI

public struct QingLongFeature: AppFeature {
    public var id: String = "qinglong-management"
    public var title: String = "青龙管理"
    public var summary: String = "连接自建青龙面板，查看环境变量、定时任务和订阅。"
    public var iconName: String = "server.rack"
    public var color: Color = .green
    public var placement: AppFeaturePlacement = .moduleList
    public var group: AppFeatureGroup? = .connectAndOps

    public init() {}

    public var entryView: AnyView {
        AnyView(QingLongView())
    }
}
