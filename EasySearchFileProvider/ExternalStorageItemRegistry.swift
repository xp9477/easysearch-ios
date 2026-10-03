import FileProvider
import Foundation
import Darwin

final class ProcessFileLock {
    private let lockFileURL: URL

    init(lockFileURL: URL) {
        self.lockFileURL = lockFileURL
    }

    func withLock<T>(_ block: () throws -> T) throws -> T {
        let path = lockFileURL.path
        let fd = open(path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else {
            throw ExternalStorageError.cannotAcquireLock(path: path)
        }
        defer {
            flock(fd, LOCK_UN)
            close(fd)
        }
        guard flock(fd, LOCK_EX) == 0 else {
            throw ExternalStorageError.cannotAcquireLock(path: path)
        }
        return try block()
    }
}

final class ExternalStorageItemRegistry: @unchecked Sendable {
    private struct RegistrySnapshot: Codable {
        var domainID: String
        var items: [String: RegisteredItemRecord] // key: UUID string
        var pathToID: [String: String] // key: normalized remotePath -> UUID string
        var syncAnchorSequence: UInt64
        var prunedSequence: UInt64
        var journal: [SyncJournalEntry]
    }

    private let domainID: String
    private let registryFileURL: URL
    private let fileLock: ProcessFileLock
    private let threadLock = NSLock()
    private let fileManager: FileManager

    private var snapshot: RegistrySnapshot

    init(domainID: String, baseStorageURL: URL, fileManager: FileManager = .default) throws {
        self.domainID = domainID
        self.fileManager = fileManager

        let domainDir = baseStorageURL
            .appendingPathComponent("domains", isDirectory: true)
            .appendingPathComponent(domainID, isDirectory: true)

        if !fileManager.fileExists(atPath: domainDir.path) {
            try fileManager.createDirectory(at: domainDir, withIntermediateDirectories: true)
        }

        self.registryFileURL = domainDir.appendingPathComponent("registry.json", isDirectory: false)
        let lockURL = domainDir.appendingPathComponent("registry.lock", isDirectory: false)
        self.fileLock = ProcessFileLock(lockFileURL: lockURL)

        self.snapshot = RegistrySnapshot(
            domainID: domainID,
            items: [:],
            pathToID: [:],
            syncAnchorSequence: 1,
            prunedSequence: 0,
            journal: []
        )

        try synchronized {
            try reloadFromDiskLocked()
        }
    }

    // MARK: - Lock & Persistence

    private func synchronized<T>(_ block: () throws -> T) throws -> T {
        threadLock.lock()
        defer { threadLock.unlock() }
        return try fileLock.withLock {
            try block()
        }
    }

    private func reloadFromDiskLocked() throws {
        guard fileManager.fileExists(atPath: registryFileURL.path) else {
            try saveToDiskLocked()
            return
        }
        let data = try Data(contentsOf: registryFileURL)
        self.snapshot = try JSONDecoder().decode(RegistrySnapshot.self, from: data)
    }

    private func saveToDiskLocked() throws {
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: registryFileURL, options: .atomic)
    }

    // MARK: - Queries

    func resolve(identifier: NSFileProviderItemIdentifier) -> RegisteredItemRecord? {
        if identifier == .rootContainer {
            return RegisteredItemRecord(
                id: NSFileProviderItemIdentifier.rootContainer.rawValue,
                parentIdentifier: NSFileProviderItemIdentifier.rootContainer.rawValue,
                remotePath: "",
                filename: "",
                isDirectory: true,
                contentLength: nil,
                modifiedAt: nil,
                contentType: nil,
                etag: nil,
                version: ItemVersionRecord(contentVersionString: "root_1", metadataVersionString: "root_1"),
                isMaterializedOrAccessed: true,
                lastSyncAnchorSequence: 1
            )
        }
        return try? synchronized {
            try reloadFromDiskLocked()
            return snapshot.items[identifier.rawValue]
        }
    }

    func resolve(remotePath: String) -> RegisteredItemRecord? {
        let normPath = ExternalStoragePathUtility.normalize(path: remotePath)
        if normPath.isEmpty {
            return resolve(identifier: .rootContainer)
        }
        return try? synchronized {
            try reloadFromDiskLocked()
            guard let id = snapshot.pathToID[normPath] else { return nil }
            return snapshot.items[id]
        }
    }

    func directChildren(of parentIdentifier: NSFileProviderItemIdentifier) -> [RegisteredItemRecord] {
        return (try? synchronized {
            try reloadFromDiskLocked()
            let pid = parentIdentifier.rawValue
            return snapshot.items.values.filter { $0.parentIdentifier == pid }
        }) ?? []
    }

    func workingSetItems() -> [RegisteredItemRecord] {
        return (try? synchronized {
            try reloadFromDiskLocked()
            return snapshot.items.values.filter { $0.isMaterializedOrAccessed }
        }) ?? []
    }

    func markAccessed(identifier: NSFileProviderItemIdentifier) {
        try? synchronized {
            try reloadFromDiskLocked()
            if var item = snapshot.items[identifier.rawValue] {
                item.isMaterializedOrAccessed = true
                snapshot.items[identifier.rawValue] = item
                try saveToDiskLocked()
            }
        }
    }

    // MARK: - Mutations

    // Content versions describe bytes; metadata versions must also change for
    // rename/reparent/type changes even when the server leaves mtime unchanged.
    private func version(etag: String?, modifiedAt: Date?, contentLength: Int64?,
                         name: String, parentIdentifier: String, isDirectory: Bool,
                         contentType: String?) -> ItemVersionRecord {
        let base = ItemVersionRecord.make(etag: etag, modifiedAt: modifiedAt, contentLength: contentLength)
        let metadata = [base.metadataVersionString, name, parentIdentifier,
                        isDirectory ? "directory" : "file", contentType ?? ""]
            .map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
        return ItemVersionRecord(contentVersionString: base.contentVersionString,
                                 metadataVersionString: metadata)
    }

    @discardableResult
    func registerOrUpdate(
        remotePath: String,
        name: String,
        isDirectory: Bool,
        parentIdentifier: NSFileProviderItemIdentifier,
        contentLength: Int64? = nil,
        modifiedAt: Date? = nil,
        contentType: String? = nil,
        etag: String? = nil
    ) throws -> RegisteredItemRecord {
        try ExternalStoragePathUtility.validatePathComponent(name)
        try ExternalStoragePathUtility.validatePath(remotePath)
        let normPath = ExternalStoragePathUtility.normalize(path: remotePath)

        return try synchronized {
            try reloadFromDiskLocked()

            let newVersion = version(etag: etag, modifiedAt: modifiedAt,
                contentLength: contentLength, name: name,
                parentIdentifier: parentIdentifier.rawValue, isDirectory: isDirectory,
                contentType: contentType)

            if let existingID = snapshot.pathToID[normPath], var item = snapshot.items[existingID] {
                let hasChanged = item.version != newVersion || item.filename != name || item.parentIdentifier != parentIdentifier.rawValue
                item.filename = name
                item.parentIdentifier = parentIdentifier.rawValue
                item.isDirectory = isDirectory
                item.contentLength = contentLength
                item.modifiedAt = modifiedAt
                item.contentType = contentType
                item.etag = etag
                item.version = newVersion

                if hasChanged {
                    snapshot.syncAnchorSequence += 1
                    item.lastSyncAnchorSequence = snapshot.syncAnchorSequence
                    appendJournalLocked(action: .updated, itemID: item.id, parentPath: ExternalStoragePathUtility.parentPath(of: normPath))
                }

                snapshot.items[existingID] = item
                try saveToDiskLocked()
                return item
            }

            // 新增项目：分配全新稳定 UUID
            let newID = UUID().uuidString
            snapshot.syncAnchorSequence += 1
            let newItem = RegisteredItemRecord(
                id: newID,
                parentIdentifier: parentIdentifier.rawValue,
                remotePath: normPath,
                filename: name,
                isDirectory: isDirectory,
                contentLength: contentLength,
                modifiedAt: modifiedAt,
                contentType: contentType,
                etag: etag,
                version: newVersion,
                isMaterializedOrAccessed: false,
                lastSyncAnchorSequence: snapshot.syncAnchorSequence
            )

            snapshot.items[newID] = newItem
            snapshot.pathToID[normPath] = newID
            appendJournalLocked(action: .updated, itemID: newID, parentPath: ExternalStoragePathUtility.parentPath(of: normPath))

            try saveToDiskLocked()
            return newItem
        }
    }

    func renameOrMove(
        identifier: NSFileProviderItemIdentifier,
        newParentIdentifier: NSFileProviderItemIdentifier,
        newName: String,
        newRemotePath: String
    ) throws -> RegisteredItemRecord {
        guard identifier != .rootContainer && identifier != .workingSet else {
            throw ExternalStorageError.rootOperationForbidden
        }
        try ExternalStoragePathUtility.validatePathComponent(newName)
        try ExternalStoragePathUtility.validatePath(newRemotePath)
        let normNewPath = ExternalStoragePathUtility.normalize(path: newRemotePath)

        return try synchronized {
            try reloadFromDiskLocked()

            guard var item = snapshot.items[identifier.rawValue] else {
                throw ExternalStorageError.itemNotFound(pathOrID: identifier.rawValue)
            }

            let oldRemotePath = item.remotePath
            if let occupied = snapshot.pathToID[normNewPath], occupied != item.id {
                throw ExternalStorageError.nameCollision(name: newName)
            }
            if item.isDirectory && normNewPath.hasPrefix(oldRemotePath + "/") {
                throw ExternalStorageError.invalidRemotePath(path: normNewPath)
            }
            item.filename = newName
            item.parentIdentifier = newParentIdentifier.rawValue
            item.remotePath = normNewPath
            item.version = version(etag: item.etag, modifiedAt: item.modifiedAt,
                contentLength: item.contentLength, name: item.filename,
                parentIdentifier: item.parentIdentifier, isDirectory: item.isDirectory,
                contentType: item.contentType)

            snapshot.pathToID.removeValue(forKey: oldRemotePath)
            snapshot.pathToID[normNewPath] = item.id

            // 如果是目录，必须原子递归更新所有子孙的 remotePath，同时保持所有子孙的稳定 UUID 不变！
            if item.isDirectory {
                let oldPrefix = oldRemotePath + "/"
                let newPrefix = normNewPath + "/"
                let descendants = snapshot.items.values.filter { $0.remotePath.hasPrefix(oldPrefix) }

                for var desc in descendants {
                    let relativeSuffix = desc.remotePath.dropFirst(oldPrefix.count)
                    let updatedDescPath = newPrefix + relativeSuffix

                    snapshot.pathToID.removeValue(forKey: desc.remotePath)
                    desc.remotePath = updatedDescPath
                    snapshot.pathToID[updatedDescPath] = desc.id
                    snapshot.items[desc.id] = desc
                }
            }

            snapshot.syncAnchorSequence += 1
            item.lastSyncAnchorSequence = snapshot.syncAnchorSequence
            snapshot.items[item.id] = item

            appendJournalLocked(action: .updated, itemID: item.id, parentPath: ExternalStoragePathUtility.parentPath(of: normNewPath))
            try saveToDiskLocked()
            return item
        }
    }

    @discardableResult
    func delete(identifier: NSFileProviderItemIdentifier) throws -> [RegisteredItemRecord] {
        guard identifier != .rootContainer && identifier != .workingSet && identifier != .trashContainer else {
            throw ExternalStorageError.rootOperationForbidden
        }

        return try synchronized {
            try reloadFromDiskLocked()

            guard let item = snapshot.items[identifier.rawValue] else {
                return []
            }

            var deletedItems = [item]
            if item.isDirectory {
                let prefix = item.remotePath + "/"
                let descendants = snapshot.items.values.filter { $0.remotePath.hasPrefix(prefix) }
                deletedItems.append(contentsOf: descendants)
            }

            snapshot.syncAnchorSequence += 1

            for target in deletedItems {
                snapshot.items.removeValue(forKey: target.id)
                snapshot.pathToID.removeValue(forKey: target.remotePath)
                appendJournalLocked(
                    action: .deleted,
                    itemID: target.id,
                    parentPath: ExternalStoragePathUtility.parentPath(of: target.remotePath)
                )
            }

            try saveToDiskLocked()
            return deletedItems
        }
    }

    func removeItemsNoLongerInRemote(parentIdentifier: NSFileProviderItemIdentifier, remainingPaths: Set<String>) throws -> [NSFileProviderItemIdentifier] {
        return try synchronized {
            try reloadFromDiskLocked()

            let pid = parentIdentifier.rawValue
            let directChildren = snapshot.items.values.filter { $0.parentIdentifier == pid }
            var removedIdentifiers: [NSFileProviderItemIdentifier] = []

            for child in directChildren {
                if !remainingPaths.contains(child.remotePath) {
                    let deleted = try deleteInternalLocked(itemID: child.id)
                    removedIdentifiers.append(contentsOf: deleted.map { NSFileProviderItemIdentifier($0.id) })
                }
            }

            if !removedIdentifiers.isEmpty {
                try saveToDiskLocked()
            }
            return removedIdentifiers
        }
    }

    private func deleteInternalLocked(itemID: String) throws -> [RegisteredItemRecord] {
        guard let item = snapshot.items[itemID] else { return [] }
        var deletedItems = [item]
        if item.isDirectory {
            let prefix = item.remotePath + "/"
            let descendants = snapshot.items.values.filter { $0.remotePath.hasPrefix(prefix) }
            deletedItems.append(contentsOf: descendants)
        }

        snapshot.syncAnchorSequence += 1
        for target in deletedItems {
            snapshot.items.removeValue(forKey: target.id)
            snapshot.pathToID.removeValue(forKey: target.remotePath)
            appendJournalLocked(
                action: .deleted,
                itemID: target.id,
                parentPath: ExternalStoragePathUtility.parentPath(of: target.remotePath)
            )
        }
        return deletedItems
    }

    // MARK: - Sync Anchors & Journaling

    func currentAnchor() -> NSFileProviderSyncAnchor {
        let seq = (try? synchronized {
            try reloadFromDiskLocked()
            return snapshot.syncAnchorSequence
        }) ?? 1
        return NSFileProviderSyncAnchor(Data("\(seq)".utf8))
    }

    func parseAnchor(_ anchor: NSFileProviderSyncAnchor) -> UInt64? {
        guard let str = String(data: anchor.rawValue, encoding: .utf8) else {
            return nil
        }
        return UInt64(str)
    }

    func incrementalChanges(since anchor: NSFileProviderSyncAnchor, parentPath: String? = nil) -> (updated: [RegisteredItemRecord], deletedIDs: [NSFileProviderItemIdentifier], newAnchor: NSFileProviderSyncAnchor)? {
        guard let fromSeq = parseAnchor(anchor) else {
            return nil
        }

        return try? synchronized {
            try reloadFromDiskLocked()

            // 只有当客户端 anchor 早于已裁剪批次或超出当前序列时才判定过期
            if fromSeq < snapshot.prunedSequence || fromSeq > snapshot.syncAnchorSequence {
                return nil
            }

            let entries = snapshot.journal.filter { entry in
                guard entry.sequence > fromSeq else { return false }
                if let parentPath = parentPath {
                    return entry.parentPath == parentPath
                }
                return true
            }

            var updatedIDs = Set<String>()
            var deletedIDs = Set<String>()

            for entry in entries {
                switch entry.action {
                case .updated:
                    if !deletedIDs.contains(entry.itemIdentifier) {
                        updatedIDs.insert(entry.itemIdentifier)
                    }
                case .deleted:
                    updatedIDs.remove(entry.itemIdentifier)
                    deletedIDs.insert(entry.itemIdentifier)
                }
            }

            let updatedRecords = updatedIDs.compactMap { snapshot.items[$0] }
            let deletedItemIDs = deletedIDs.map { NSFileProviderItemIdentifier($0) }
            let newAnchor = NSFileProviderSyncAnchor(Data("\(snapshot.syncAnchorSequence)".utf8))

            return (updated: updatedRecords, deletedIDs: deletedItemIDs, newAnchor: newAnchor)
        }
    }

    private func appendJournalLocked(action: SyncAction, itemID: String, parentPath: String) {
        let entry = SyncJournalEntry(
            sequence: snapshot.syncAnchorSequence,
            action: action,
            itemIdentifier: itemID,
            parentPath: parentPath
        )
        snapshot.journal.append(entry)

        // 按批次截断：不能截同 sequence 的一半，确保事务完整性
        if snapshot.journal.count > 500 {
            let cutoffIndex = snapshot.journal.count - 400
            let cutSeq = snapshot.journal[cutoffIndex].sequence
            // 将所有 sequence <= cutSeq 的记录完整移除
            snapshot.journal.removeAll { $0.sequence <= cutSeq }
            snapshot.prunedSequence = cutSeq
        }
    }
}
