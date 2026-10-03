import FileProvider
import Foundation
import UniformTypeIdentifiers

struct ExternalStorageLocationMetadata: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let baseURL: URL
    let username: String
    let credentialID: UUID?

    init(id: UUID, name: String, baseURL: URL, username: String, credentialID: UUID? = nil) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.username = username
        self.credentialID = credentialID
    }
}

struct ItemVersionRecord: Codable, Equatable, Sendable {
    let contentVersionString: String
    let metadataVersionString: String

    init(contentVersionString: String, metadataVersionString: String) {
        self.contentVersionString = contentVersionString
        self.metadataVersionString = metadataVersionString
    }

    static func make(etag: String?, modifiedAt: Date?, contentLength: Int64?) -> ItemVersionRecord {
        let mtime = modifiedAt?.timeIntervalSince1970 ?? 0
        let size = contentLength ?? 0
        let cVer = etag?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) ?? "\(mtime)_\(size)"
        let mVer = "\(mtime)"
        return ItemVersionRecord(contentVersionString: cVer, metadataVersionString: mVer)
    }

    var fileProviderItemVersion: NSFileProviderItemVersion {
        NSFileProviderItemVersion(
            contentVersion: Data(contentVersionString.utf8),
            metadataVersion: Data(metadataVersionString.utf8)
        )
    }
}

struct RegisteredItemRecord: Codable, Equatable, Identifiable, Sendable {
    let id: String // UUID string or root container string
    var parentIdentifier: String // UUID string or NSFileProviderItemIdentifier.rootContainer.rawValue
    var remotePath: String // normalized path, "" for root
    var filename: String
    var isDirectory: Bool
    var contentLength: Int64?
    var modifiedAt: Date?
    var contentType: String?
    var etag: String?
    var version: ItemVersionRecord
    var isMaterializedOrAccessed: Bool
    var lastSyncAnchorSequence: UInt64

    init(
        id: String,
        parentIdentifier: String,
        remotePath: String,
        filename: String,
        isDirectory: Bool,
        contentLength: Int64? = nil,
        modifiedAt: Date? = nil,
        contentType: String? = nil,
        etag: String? = nil,
        version: ItemVersionRecord,
        isMaterializedOrAccessed: Bool = false,
        lastSyncAnchorSequence: UInt64 = 0
    ) {
        self.id = id
        self.parentIdentifier = parentIdentifier
        self.remotePath = remotePath
        self.filename = filename
        self.isDirectory = isDirectory
        self.contentLength = contentLength
        self.modifiedAt = modifiedAt
        self.contentType = contentType
        self.etag = etag
        self.version = version
        self.isMaterializedOrAccessed = isMaterializedOrAccessed
        self.lastSyncAnchorSequence = lastSyncAnchorSequence
    }

    var itemIdentifier: NSFileProviderItemIdentifier {
        if id == NSFileProviderItemIdentifier.rootContainer.rawValue {
            return .rootContainer
        }
        return NSFileProviderItemIdentifier(id)
    }

    var parentItemIdentifier: NSFileProviderItemIdentifier {
        if parentIdentifier == NSFileProviderItemIdentifier.rootContainer.rawValue {
            return .rootContainer
        }
        return NSFileProviderItemIdentifier(parentIdentifier)
    }

    var resolvedUTType: UTType {
        if isDirectory {
            return .folder
        }
        if let contentType, let ut = UTType(mimeType: contentType) {
            return ut
        }
        let ext = (filename as NSString).pathExtension
        if !ext.isEmpty, let ut = UTType(filenameExtension: ext) {
            return ut
        }
        return .item
    }
}

enum SyncAction: String, Codable, Sendable {
    case updated
    case deleted
}

struct SyncJournalEntry: Codable, Equatable, Sendable {
    let sequence: UInt64
    let action: SyncAction
    let itemIdentifier: String
    let parentPath: String
    let timestamp: Date

    init(sequence: UInt64, action: SyncAction, itemIdentifier: String, parentPath: String, timestamp: Date = Date()) {
        self.sequence = sequence
        self.action = action
        self.itemIdentifier = itemIdentifier
        self.parentPath = parentPath
        self.timestamp = timestamp
    }
}

enum ExternalStoragePathUtility {
    /// 规范化路径：仅去除首尾斜杠及连续多余斜杠，绝不去除组件内的空格与合法字面字符
    static func normalize(path: String) -> String {
        let parts = path
            .components(separatedBy: "/")
            .filter { !$0.isEmpty }
        return parts.joined(separator: "/")
    }

    static func validatePathComponent(_ name: String) throws {
        if name.isEmpty || name == "." || name == ".." {
            throw ExternalStorageError.traversalDetected(path: name)
        }
        if name.contains("/") || name.contains("\\") || name.contains("\0") {
            throw ExternalStorageError.invalidRemotePath(path: name)
        }
    }

    static func validatePath(_ path: String) throws {
        let rawParts = path.components(separatedBy: "/")
        for part in rawParts {
            if part == ".." {
                throw ExternalStorageError.traversalDetected(path: path)
            }
            if part.contains("\\") || part.contains("\0") {
                throw ExternalStorageError.invalidRemotePath(path: path)
            }
        }
    }

    static func parentPath(of path: String) -> String {
        let norm = normalize(path: path)
        guard let idx = norm.lastIndex(of: "/") else {
            return ""
        }
        return String(norm[..<idx])
    }

    static func filename(of path: String) -> String {
        let norm = normalize(path: path)
        guard let idx = norm.lastIndex(of: "/") else {
            return norm
        }
        return String(norm[norm.index(after: idx)...])
    }

    static func join(_ base: String, _ component: String) -> String {
        let normBase = normalize(path: base)
        let normComponent = normalize(path: component)
        if normBase.isEmpty { return normComponent }
        if normComponent.isEmpty { return normBase }
        return "\(normBase)/\(normComponent)"
    }
}
