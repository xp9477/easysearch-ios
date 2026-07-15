import SwiftUI

struct WebDAVFeature: AppFeature {
    let id = "webdav"
    let title = "WebDAV 文件"
    let summary = "连接 WebDAV，浏览、上传和下载文件"
    let iconName = "externaldrive.fill"
    let color: Color = .blue
    let placement: AppFeaturePlacement = .moduleList

    var entryView: AnyView {
        AnyView(WebDAVView())
    }
}
