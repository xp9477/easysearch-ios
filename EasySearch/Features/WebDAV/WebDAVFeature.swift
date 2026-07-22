import SwiftUI

struct WebDAVFeature: AppFeature {
    var id: String = "webdav"
    var title: String = "WebDAV 文件"
    var summary: String = "连接 WebDAV，浏览、上传和下载文件。"
    var iconName: String = "externaldrive.fill"
    var color: Color = Color(red: 0.16, green: 0.45, blue: 0.85)
    var placement: AppFeaturePlacement = .moduleList
    var group: AppFeatureGroup? = .connectAndOps

    init() {}

    var entryView: AnyView {
        AnyView(WebDAVView())
    }
}
