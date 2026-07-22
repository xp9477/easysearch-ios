import SwiftUI

public struct QingLongFeature: AppFeature {
    public var id: String = "qinglong-management"
    public var title: String = "青龙管理"
    public var summary: String = "连接青龙面板，管理任务与订阅。"
    public var iconName: String = "server.rack"
    public var color: Color = Color(red: 0.10, green: 0.72, blue: 0.48)
    public var placement: AppFeaturePlacement = .moduleList
    public var group: AppFeatureGroup? = .connectAndOps

    public init() {}

    public var entryView: AnyView {
        AnyView(QingLongView())
    }
}
