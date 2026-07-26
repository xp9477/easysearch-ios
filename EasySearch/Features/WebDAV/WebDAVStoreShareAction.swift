import SwiftUI

/// WebDAV share-inbox action registered into `ShareActionRegistry`.
struct WebDAVStoreShareAction: ShareActionHandling {
    let id = "storeToWebDAV"
    let title = "存储到 WebDAV"
    let systemImage = "externaldrive.badge.plus"
    let isAvailable = true

    func destination(items: [SharedInboxItem], onCompleted: @escaping () -> Void) -> AnyView {
        AnyView(
            WebDAVShareUploadView(items: items) {
                onCompleted()
            }
        )
    }
}
