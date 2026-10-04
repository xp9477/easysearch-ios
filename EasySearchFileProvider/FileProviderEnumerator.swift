import FileProvider
import Foundation

final class FileProviderEnumerator: NSObject, NSFileProviderEnumerator {
    private struct EnumerationSnapshot {
        let id: String
        let items: [RegisteredItemRecord]
        let createdAt: Date
    }

    private struct PageToken: Codable {
        let snapshotID: String
        let offset: Int
    }

    private static let snapshotLock = NSLock()
    private static var snapshotStore: [String: EnumerationSnapshot] = [:]

    private let containerItemIdentifier: NSFileProviderItemIdentifier
    private let registry: ExternalStorageItemRegistry
    private let client: ExternalStorageClientProtocol
    private let domainDisplayName: String
    private let pageSize = 50

    private var activeTask: Task<Void, Never>?

    init(
        containerItemIdentifier: NSFileProviderItemIdentifier,
        registry: ExternalStorageItemRegistry,
        client: ExternalStorageClientProtocol,
        domainDisplayName: String = ""
    ) {
        self.containerItemIdentifier = containerItemIdentifier
        self.registry = registry
        self.client = client
        self.domainDisplayName = domainDisplayName
        super.init()
        if containerItemIdentifier != .workingSet {
            registry.markAccessed(identifier: containerItemIdentifier)
        }
    }

    func invalidate() {
        activeTask?.cancel()
        activeTask = nil
    }

    // MARK: - Enumerate Items with Snapshot Pagination

    func enumerateItems(
        for observer: any NSFileProviderEnumerationObserver,
        startingAt page: NSFileProviderPage
    ) {
        let task = Task {
            do {
                if containerItemIdentifier == .workingSet {
                    try await enumerateWorkingSetWithSnapshot(observer: observer, startingAt: page)
                } else {
                    try await enumerateDirectoryWithSnapshot(observer: observer, startingAt: page)
                }
            } catch {
                let mapped = ExternalStorageErrorMapper.mapToNSFileProviderError(error)
                observer.finishEnumeratingWithError(mapped)
            }
        }
        self.activeTask = task
    }

    private func enumerateDirectoryWithSnapshot(
        observer: any NSFileProviderEnumerationObserver,
        startingAt page: NSFileProviderPage
    ) async throws {
        let isInitial = (page.rawValue == NSFileProviderPage.initialPageSortedByName as Data
            || page.rawValue == NSFileProviderPage.initialPageSortedByDate as Data)

        let snapshot: EnumerationSnapshot
        let offset: Int

        if isInitial {
            // 首次请求：拉取远端单层直接子项，登记至 registry，生成固定快照
            let containerRecord = registry.resolve(identifier: containerItemIdentifier)
            guard let containerRecord else {
                throw ExternalStorageError.itemNotFound(pathOrID: containerItemIdentifier.rawValue)
            }

            let remoteItems = try await client.list(path: containerRecord.remotePath)

            var registeredRecords: [RegisteredItemRecord] = []
            for rItem in remoteItems {
                try Task.checkCancellation()
                let record = try registry.registerOrUpdate(
                    remotePath: rItem.path,
                    name: rItem.name,
                    isDirectory: rItem.isDirectory,
                    parentIdentifier: containerItemIdentifier,
                    contentLength: rItem.contentLength,
                    modifiedAt: rItem.modifiedAt,
                    contentType: rItem.contentType,
                    etag: rItem.etag
                )
                registeredRecords.append(record)
            }

            let snapshotID = UUID().uuidString
            let newSnapshot = EnumerationSnapshot(
                id: snapshotID,
                items: registeredRecords,
                createdAt: Date()
            )
            Self.saveSnapshot(newSnapshot)
            snapshot = newSnapshot
            offset = 0
        } else {
            // 后续分页请求：使用已有快照，禁止重复请求网络导致重复或漏项
            guard let token = Self.decodePageToken(page),
                  let cached = Self.getSnapshot(id: token.snapshotID) else {
                throw NSError(
                    domain: NSFileProviderErrorDomain,
                    code: NSFileProviderError.Code.pageExpired.rawValue,
                    userInfo: [NSLocalizedDescriptionKey: "Enumeration page snapshot expired"]
                )
            }
            snapshot = cached
            offset = token.offset
        }

        let total = snapshot.items.count
        guard offset < total else {
            observer.didEnumerate([])
            observer.finishEnumerating(upTo: nil)
            Self.removeSnapshot(id: snapshot.id)
            return
        }

        let endIndex = min(offset + pageSize, total)
        let pageSlice = snapshot.items[offset..<endIndex]
        let fileProviderItems = pageSlice.map {
            FileProviderItem(record: $0, domainDisplayName: domainDisplayName)
        }

        observer.didEnumerate(fileProviderItems)

        if endIndex < total {
            let nextToken = PageToken(snapshotID: snapshot.id, offset: endIndex)
            let pageData = try JSONEncoder().encode(nextToken)
            observer.finishEnumerating(upTo: NSFileProviderPage(pageData))
        } else {
            observer.finishEnumerating(upTo: nil)
            Self.removeSnapshot(id: snapshot.id)
        }
    }

    private func enumerateWorkingSetWithSnapshot(
        observer: any NSFileProviderEnumerationObserver,
        startingAt page: NSFileProviderPage
    ) async throws {
        let isInitial = (page.rawValue == NSFileProviderPage.initialPageSortedByName as Data
            || page.rawValue == NSFileProviderPage.initialPageSortedByDate as Data)

        let snapshot: EnumerationSnapshot
        let offset: Int

        if isInitial {
            let items = registry.workingSetItems()
            let snapshotID = UUID().uuidString
            let newSnapshot = EnumerationSnapshot(id: snapshotID, items: items, createdAt: Date())
            Self.saveSnapshot(newSnapshot)
            snapshot = newSnapshot
            offset = 0
        } else {
            guard let token = Self.decodePageToken(page),
                  let cached = Self.getSnapshot(id: token.snapshotID) else {
                throw NSError(
                    domain: NSFileProviderErrorDomain,
                    code: NSFileProviderError.Code.pageExpired.rawValue,
                    userInfo: [NSLocalizedDescriptionKey: "Working set page snapshot expired"]
                )
            }
            snapshot = cached
            offset = token.offset
        }

        let total = snapshot.items.count
        guard offset < total else {
            observer.didEnumerate([])
            observer.finishEnumerating(upTo: nil)
            Self.removeSnapshot(id: snapshot.id)
            return
        }

        let endIndex = min(offset + pageSize, total)
        let pageSlice = snapshot.items[offset..<endIndex]
        let fileProviderItems = pageSlice.map {
            FileProviderItem(record: $0, domainDisplayName: domainDisplayName)
        }

        observer.didEnumerate(fileProviderItems)

        if endIndex < total {
            let nextToken = PageToken(snapshotID: snapshot.id, offset: endIndex)
            let pageData = try JSONEncoder().encode(nextToken)
            observer.finishEnumerating(upTo: NSFileProviderPage(pageData))
        } else {
            observer.finishEnumerating(upTo: nil)
            Self.removeSnapshot(id: snapshot.id)
        }
    }

    // MARK: - Enumerate Changes (Incremental Sync)

    func enumerateChanges(
        for observer: any NSFileProviderChangeObserver,
        from syncAnchor: NSFileProviderSyncAnchor
    ) {
        let task = Task {
            do {
                if containerItemIdentifier == .workingSet {
                    try await enumerateWorkingSetChanges(observer: observer, from: syncAnchor)
                } else {
                    try await enumerateDirectoryChanges(observer: observer, from: syncAnchor)
                }
            } catch {
                let mapped = ExternalStorageErrorMapper.mapToNSFileProviderError(error)
                observer.finishEnumeratingWithError(mapped)
            }
        }
        self.activeTask = task
    }

    private func enumerateDirectoryChanges(
        observer: any NSFileProviderChangeObserver,
        from syncAnchor: NSFileProviderSyncAnchor
    ) async throws {
        guard let containerRecord = registry.resolve(identifier: containerItemIdentifier) else {
            throw ExternalStorageError.itemNotFound(pathOrID: containerItemIdentifier.rawValue)
        }

        let remotePath = containerRecord.remotePath

        // 关键验收要求：增量目录必须完整成功获取后才检测删除，网络失败不当空目录！
        let remoteItems: [WebDAVItem]
        do {
            remoteItems = try await client.list(path: remotePath)
        } catch {
            throw error
        }

        var updatedRecords: [RegisteredItemRecord] = []
        var remainingRemotePaths = Set<String>()

        for rItem in remoteItems {
            try Task.checkCancellation()
            let record = try registry.registerOrUpdate(
                remotePath: rItem.path,
                name: rItem.name,
                isDirectory: rItem.isDirectory,
                parentIdentifier: containerItemIdentifier,
                contentLength: rItem.contentLength,
                modifiedAt: rItem.modifiedAt,
                contentType: rItem.contentType,
                etag: rItem.etag
            )
            updatedRecords.append(record)
            remainingRemotePaths.insert(record.remotePath)
        }

        // 仅在网络成功后，由本地与远端对比检测真正被远端删除的项
        let deletedIdentifiers = try registry.removeItemsNoLongerInRemote(
            parentIdentifier: containerItemIdentifier,
            remainingPaths: remainingRemotePaths
        )

        if !updatedRecords.isEmpty {
            let fpItems = updatedRecords.map { FileProviderItem(record: $0, domainDisplayName: domainDisplayName) }
            observer.didUpdate(fpItems)
        }

        if !deletedIdentifiers.isEmpty {
            observer.didDeleteItems(withIdentifiers: deletedIdentifiers)
        }

        let newAnchor = registry.currentAnchor()
        observer.finishEnumeratingChanges(upTo: newAnchor, moreComing: false)
    }

    private func enumerateWorkingSetChanges(
        observer: any NSFileProviderChangeObserver,
        from syncAnchor: NSFileProviderSyncAnchor
    ) async throws {
        // 关键验收要求：workingSetChanges必须先refresh已跟踪目录否则App signal workingSet永远journal没外部变化
        let trackedItems = registry.workingSetItems()
        var trackedParentPaths = Set<String>()

        // 跟踪根目录及所有物化项的父目录
        trackedParentPaths.insert("")
        for item in trackedItems {
            let parent = ExternalStoragePathUtility.parentPath(of: item.remotePath)
            trackedParentPaths.insert(parent)
        }

        // 主动刷新所有跟踪父目录，将外部变动同步回本地注册表
        for parentPath in trackedParentPaths.sorted(by: { $0.count < $1.count }) {
            try Task.checkCancellation()
            guard let parentRecord = registry.resolve(remotePath: parentPath) else { continue }
            let parentID = parentRecord.itemIdentifier
            let remoteItems = try await client.list(path: parentPath)
            var remaining = Set<String>()
            for item in remoteItems {
                let record = try registry.registerOrUpdate(remotePath: item.path, name: item.name,
                    isDirectory: item.isDirectory, parentIdentifier: parentID,
                    contentLength: item.contentLength, modifiedAt: item.modifiedAt,
                    contentType: item.contentType, etag: item.etag)
                remaining.insert(record.remotePath)
            }
            _ = try registry.removeItemsNoLongerInRemote(parentIdentifier: parentID, remainingPaths: remaining)
        }

        if let changes = registry.incrementalChanges(since: syncAnchor) {
            if !changes.updated.isEmpty {
                let fpItems = changes.updated.map { FileProviderItem(record: $0, domainDisplayName: domainDisplayName) }
                observer.didUpdate(fpItems)
            }
            if !changes.deletedIDs.isEmpty {
                observer.didDeleteItems(withIdentifiers: changes.deletedIDs)
            }
            observer.finishEnumeratingChanges(upTo: changes.newAnchor, moreComing: false)
        } else {
            // syncAnchor 过旧或失效时，抛出 syncAnchorExpired 让系统重走完整枚举
            throw NSError(
                domain: NSFileProviderErrorDomain,
                code: NSFileProviderError.Code.syncAnchorExpired.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "Sync anchor expired"]
            )
        }
    }

    func currentSyncAnchor(completionHandler: @escaping @Sendable (NSFileProviderSyncAnchor?) -> Void) {
        completionHandler(registry.currentAnchor())
    }

    // MARK: - Snapshot Cache Helpers

    private static func saveSnapshot(_ snapshot: EnumerationSnapshot) {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        cleanupExpiredSnapshotsLocked()
        snapshotStore[snapshot.id] = snapshot
    }

    private static func getSnapshot(id: String) -> EnumerationSnapshot? {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        return snapshotStore[id]
    }

    private static func removeSnapshot(id: String) {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        snapshotStore.removeValue(forKey: id)
    }

    private static func cleanupExpiredSnapshotsLocked() {
        let expirationDate = Date().addingTimeInterval(-120)
        snapshotStore = snapshotStore.filter { $0.value.createdAt > expirationDate }
    }

    private static func decodePageToken(_ page: NSFileProviderPage) -> PageToken? {
        guard let token = try? JSONDecoder().decode(PageToken.self, from: page.rawValue) else {
            return nil
        }
        return token
    }
}
