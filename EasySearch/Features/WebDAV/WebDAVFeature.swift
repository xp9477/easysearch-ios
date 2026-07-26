import SwiftUI

struct WebDAVFeature: AppFeature {
    var id: String = "webdav"
    var title: String = "WebDAV 文件"
    var summary: String = "连接 WebDAV，浏览、上传和下载文件。"
    var iconName: String = "externaldrive.fill"
    var color: Color = .blue
    var placement: AppFeaturePlacement = .moduleList
    var group: AppFeatureGroup? = .connectAndOps

    init() {}

    var entryView: AnyView {
        AnyView(WebDAVView())
    }

    @MainActor
    func statusSummary() async -> FeatureStatusSummary {
        let store = WebDAVSettingsStore.shared
        if store.configuration == nil {
            return FeatureStatusSummary(kind: .needsConfiguration, text: "未配置")
        }
        let count = store.locations.count
        return FeatureStatusSummary(kind: .ready, text: count > 0 ? "\(count) 个位置" : "已连接")
    }

}
