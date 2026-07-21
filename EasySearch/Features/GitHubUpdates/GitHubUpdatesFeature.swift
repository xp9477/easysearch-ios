import SwiftUI

public struct GitHubUpdatesFeature: AppFeature {
    public var id: String = "github-updates"
    public var title: String = "GitHub 更新"
    public var summary: String = "关注公开仓库的最新 push，在后台检查并发送提醒。"
    public var iconName: String = "bell.badge"
    public var color: Color = .indigo
    public var placement: AppFeaturePlacement = .moduleList
    public var group: AppFeatureGroup? = .connectAndOps

    public init() {}

    public var entryView: AnyView {
        AnyView(GitHubUpdatesView())
    }
}
