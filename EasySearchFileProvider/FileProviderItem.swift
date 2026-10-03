import FileProvider
import Foundation
import UniformTypeIdentifiers

final class FileProviderItem: NSObject, NSFileProviderItemProtocol {
    private let record: RegisteredItemRecord
    private let domainDisplayName: String

    init(record: RegisteredItemRecord, domainDisplayName: String = "") {
        self.record = record
        self.domainDisplayName = domainDisplayName
        super.init()
    }

    // MARK: - Required Properties

    var itemIdentifier: NSFileProviderItemIdentifier {
        record.itemIdentifier
    }

    var parentItemIdentifier: NSFileProviderItemIdentifier {
        record.parentItemIdentifier
    }

    var filename: String {
        if record.itemIdentifier == .rootContainer {
            return domainDisplayName.isEmpty ? "外部存储" : domainDisplayName
        }
        return record.filename
    }

    var contentType: UTType {
        record.resolvedUTType
    }

    var capabilities: NSFileProviderItemCapabilities {
        if record.itemIdentifier == .rootContainer {
            // 根文件夹 capabilities 仅允许添加子项、读取和枚举，绝对禁止删除、重命名或重定位
            return [.allowsAddingSubItems, .allowsContentEnumerating, .allowsReading]
        }

        if record.isDirectory {
            return [
                .allowsAddingSubItems,
                .allowsContentEnumerating,
                .allowsReading,
                .allowsDeleting,
                .allowsRenaming,
                .allowsReparenting
            ]
        }

        return [
            .allowsReading,
            .allowsWriting,
            .allowsDeleting,
            .allowsRenaming,
            .allowsReparenting
        ]
    }

    // MARK: - Metadata & Size

    var documentSize: NSNumber? {
        guard !record.isDirectory, let size = record.contentLength else {
            return nil
        }
        return NSNumber(value: size)
    }

    var contentModificationDate: Date? {
        record.modifiedAt
    }

    var itemVersion: NSFileProviderItemVersion {
        record.version.fileProviderItemVersion
    }
}
