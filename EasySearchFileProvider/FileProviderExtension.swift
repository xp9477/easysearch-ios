import FileProvider
import Foundation
import UniformTypeIdentifiers

final class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    private let domain: NSFileProviderDomain
    private let locationID: UUID?
    private var registry: ExternalStorageItemRegistry?
    private var cachedClient: ExternalStorageClientProtocol?
    private var lastConfigCacheKey: String = ""
    private let clientLock = NSLock()

    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        let locID = UUID(uuidString: domain.identifier.rawValue)
        self.locationID = locID

        if let locID {
            if let storageRoot = try? ExternalStorageSharedStore.shared.rootDirectoryURL() {
                self.registry = try? ExternalStorageItemRegistry(domainID: domain.identifier.rawValue, baseStorageURL: storageRoot)
            }
        }
        super.init()
    }

    func invalidate() {
        clientLock.lock()
        defer { clientLock.unlock() }
        cachedClient = nil
    }

    // MARK: - Dynamic Client Resolution (Credentials Refresh Support)

    private func getClient() throws -> ExternalStorageClientProtocol {
        clientLock.lock()
        defer { clientLock.unlock() }

        guard let locationID else {
            throw ExternalStorageError.locationNotFound(locationID: UUID())
        }

        let config = try ExternalStorageSharedStore.shared.configuration(locationID: locationID)
        let currentKey = config.cacheKey

        if let client = cachedClient, currentKey == lastConfigCacheKey {
            return client
        }

        let newClient = ExternalStorageWebDAVAdapter(configuration: config)
        self.cachedClient = newClient
        self.lastConfigCacheKey = currentKey
        return newClient
    }

    private func getRegistry() throws -> ExternalStorageItemRegistry {
        clientLock.lock()
        defer { clientLock.unlock() }
        if let registry { return registry }
        guard let locationID else {
            throw ExternalStorageError.locationNotFound(locationID: UUID())
        }
        let storageRoot = try ExternalStorageSharedStore.shared.rootDirectoryURL()
        let reg = try ExternalStorageItemRegistry(domainID: domain.identifier.rawValue, baseStorageURL: storageRoot)
        self.registry = reg
        return reg
    }

    private func refreshed(_ record: RegisteredItemRecord, client: ExternalStorageClientProtocol,
                           registry: ExternalStorageItemRegistry) async throws -> RegisteredItemRecord {
        let items = try await client.list(path: ExternalStoragePathUtility.parentPath(of: record.remotePath))
        guard let item = items.first(where: { $0.path == record.remotePath }) else {
            throw NSFileProviderError(.noSuchItem)
        }
        return try registry.registerOrUpdate(remotePath: item.path, name: item.name,
            isDirectory: item.isDirectory, parentIdentifier: record.parentItemIdentifier,
            contentLength: item.contentLength, modifiedAt: item.modifiedAt,
            contentType: item.contentType, etag: item.etag)
    }

    // MARK: - Remote Item

    func item(
        for identifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, (any Error)?) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: 1)

        guard let registry = try? getRegistry() else {
            completionHandler(nil, NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.Code.notAuthenticated.rawValue, userInfo: nil))
            return progress
        }

        if identifier == .rootContainer {
            let rootRecord = registry.resolve(identifier: .rootContainer)!
            let item = FileProviderItem(record: rootRecord, domainDisplayName: domain.displayName)
            progress.completedUnitCount = 1
            completionHandler(item, nil)
            return progress
        }

        guard let initialRecord = registry.resolve(identifier: identifier) else {
            completionHandler(nil, NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.Code.noSuchItem.rawValue, userInfo: nil))
            return progress
        }

        let task = Task {
            do {
                let client = try self.getClient()
                let parentPath = ExternalStoragePathUtility.parentPath(of: initialRecord.remotePath)
                // 主动刷新远端属性而非永远读取旧缓存
                let remoteItems = try await client.list(path: parentPath)

                if let matched = remoteItems.first(where: { $0.path == initialRecord.remotePath }) {
                    let updatedRecord = try registry.registerOrUpdate(
                        remotePath: matched.path,
                        name: matched.name,
                        isDirectory: matched.isDirectory,
                        parentIdentifier: initialRecord.parentItemIdentifier,
                        contentLength: matched.contentLength,
                        modifiedAt: matched.modifiedAt,
                        contentType: matched.contentType,
                        etag: matched.etag
                    )
                    registry.markAccessed(identifier: identifier)
                    let item = FileProviderItem(record: updatedRecord, domainDisplayName: self.domain.displayName)
                    progress.completedUnitCount = 1
                    completionHandler(item, nil)
                } else {
                    // 远端已不存在，从注册表清理并返回 noSuchItem
                    _ = try? registry.delete(identifier: identifier)
                    completionHandler(nil, NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.Code.noSuchItem.rawValue, userInfo: nil))
                }
            } catch {
                completionHandler(nil, ExternalStorageErrorMapper.mapToNSFileProviderError(error))
            }
        }

        progress.cancellationHandler = { task.cancel() }
        return progress
    }

    // MARK: - Fetch Contents

    func fetchContents(
        for itemIdentifier: NSFileProviderItemIdentifier,
        version requestedVersion: NSFileProviderItemVersion?,
        request: NSFileProviderRequest,
        completionHandler: @escaping (URL?, NSFileProviderItem?, (any Error)?) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: 100)

        guard let registry = try? getRegistry() else {
            completionHandler(nil, nil, NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.Code.notAuthenticated.rawValue, userInfo: nil))
            return progress
        }

        guard itemIdentifier != .rootContainer, let record = registry.resolve(identifier: itemIdentifier), !record.isDirectory else {
            completionHandler(nil, nil, NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.Code.noSuchItem.rawValue, userInfo: nil))
            return progress
        }

        let downloadTask = Task {
            var temporaryURL: URL?
            defer { if let temporaryURL { WebDAVLocalFileStore.removePreview(containing: temporaryURL) } }
            do {
                let client = try self.getClient()
                let parentPath = ExternalStoragePathUtility.parentPath(of: record.remotePath)

                // 1. 下载前校验：远端 list 找到同名项，核验 requestedVersion 及当前远端版本
                let preRemoteItems = try await client.list(path: parentPath)
                guard let preItem = preRemoteItems.first(where: { $0.path == record.remotePath }) else {
                    throw NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.Code.noSuchItem.rawValue, userInfo: nil)
                }

                let preVersion = ItemVersionRecord.make(
                    etag: preItem.etag,
                    modifiedAt: preItem.modifiedAt,
                    contentLength: preItem.contentLength
                )

                if let requested = requestedVersion,
                   preVersion.fileProviderItemVersion.contentVersion != requested.contentVersion {
                    throw NSError(
                        domain: NSFileProviderErrorDomain,
                        code: NSFileProviderError.Code.cannotSynchronize.rawValue,
                        userInfo: [NSLocalizedDescriptionKey: "Requested version is out of date before download"]
                    )
                }

                // 2. 流式下载到安全临时文件
                let downloadedURL = try await client.downloadForPreview(item: preItem) { transfer in
                    if let fraction = transfer.fractionCompleted {
                        progress.completedUnitCount = Int64(fraction * 100)
                    }
                }

                temporaryURL = downloadedURL
                try Task.checkCancellation()

                // 3. 下载后校验：再次 list parent 检查远端属性，变动即冲突并清临时文件
                let postRemoteItems = try await client.list(path: parentPath)
                guard let postItem = postRemoteItems.first(where: { $0.path == record.remotePath }) else {
                    try? FileManager.default.removeItem(at: downloadedURL)
                    throw NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.Code.noSuchItem.rawValue, userInfo: nil)
                }

                let postVersion = ItemVersionRecord.make(
                    etag: postItem.etag,
                    modifiedAt: postItem.modifiedAt,
                    contentLength: postItem.contentLength
                )

                if postVersion.contentVersionString != preVersion.contentVersionString {
                    // 下载期间远端发生变动，坚决禁止旧内容标记新版本，清理临时文件并报错
                    try? FileManager.default.removeItem(at: downloadedURL)
                    throw NSError(
                        domain: NSFileProviderErrorDomain,
                        code: NSFileProviderError.Code.cannotSynchronize.rawValue,
                        userInfo: [NSLocalizedDescriptionKey: "Remote file modified during download"]
                    )
                }

                // 4. 前后完全一致：更新注册表
                let updatedRecord = try registry.registerOrUpdate(
                    remotePath: record.remotePath,
                    name: record.filename,
                    isDirectory: false,
                    parentIdentifier: record.parentItemIdentifier,
                    contentLength: postItem.contentLength,
                    modifiedAt: postItem.modifiedAt,
                    contentType: postItem.contentType,
                    etag: postItem.etag
                )
                registry.markAccessed(identifier: itemIdentifier)

                let finalItem = FileProviderItem(record: updatedRecord, domainDisplayName: self.domain.displayName)
                progress.completedUnitCount = 100
                temporaryURL = nil // Ownership of the completed file passes to File Provider.
                completionHandler(downloadedURL, finalItem, nil)
            } catch {
                let mapped = ExternalStorageErrorMapper.mapToNSFileProviderError(error)
                completionHandler(nil, nil, mapped)
            }
        }

        progress.cancellationHandler = { downloadTask.cancel() }
        return progress
    }

    // MARK: - Create Item

    func createItem(
        basedOn itemTemplate: NSFileProviderItem,
        fields: NSFileProviderItemFields,
        contents url: URL?,
        options: NSFileProviderCreateItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, (any Error)?) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: 1)

        guard let registry = try? getRegistry() else {
            completionHandler(nil, fields, false, NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.Code.notAuthenticated.rawValue, userInfo: nil))
            return progress
        }

        let parentID = itemTemplate.parentItemIdentifier
        guard let parentRecord = registry.resolve(identifier: parentID) else {
            completionHandler(nil, fields, false, NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.Code.noSuchItem.rawValue, userInfo: nil))
            return progress
        }

        let task = Task {
            do {
                let client = try self.getClient()
                let filename = itemTemplate.filename
                try ExternalStoragePathUtility.validatePathComponent(filename)
                let newRemotePath = ExternalStoragePathUtility.join(parentRecord.remotePath, filename)
                try ExternalStoragePathUtility.validatePath(newRemotePath)

                guard parentRecord.isDirectory else { throw NSFileProviderError(.noSuchItem) }
                let isFolder = (itemTemplate.contentType == .folder)
                try Task.checkCancellation()
                if isFolder {
                    try await client.createDirectory(path: newRemotePath)
                    let newRecord = try registry.registerOrUpdate(
                        remotePath: newRemotePath,
                        name: filename,
                        isDirectory: true,
                        parentIdentifier: parentID,
                        contentLength: nil,
                        modifiedAt: Date(),
                        contentType: nil,
                        etag: nil
                    )
                    let remoteRecord = try await refreshed(newRecord, client: client, registry: registry)
                    let newItem = FileProviderItem(record: remoteRecord, domainDisplayName: self.domain.displayName)
                    progress.completedUnitCount = 1
                    completionHandler(newItem, fields.subtracting([.filename, .parentItemIdentifier, .contents]), false, nil)
                } else {
                    guard let contentsURL = url else {
                        throw ExternalStorageError.invalidRemotePath(path: newRemotePath)
                    }

                    // uploadExact: 目标若存在直接报错冲突，不进行 auto-rename
                    try await client.uploadExact(localURL: contentsURL, remotePath: newRemotePath)

                    let attrs = try? FileManager.default.attributesOfItem(atPath: contentsURL.path)
                    let size = (attrs?[.size] as? NSNumber)?.int64Value
                    let mtime = (attrs?[.modificationDate] as? Date) ?? Date()

                    let newRecord = try registry.registerOrUpdate(
                        remotePath: newRemotePath,
                        name: filename,
                        isDirectory: false,
                        parentIdentifier: parentID,
                        contentLength: size,
                        modifiedAt: mtime,
                        contentType: itemTemplate.contentType.preferredMIMEType,
                        etag: nil
                    )

                    // 返回 unsupported changedFields 作为 remainingFields，不虚报全部成功
                    let supportedFields: NSFileProviderItemFields = [.contents, .filename, .parentItemIdentifier]
                    let unsupported = fields.subtracting(supportedFields)

                    let remoteRecord = try await refreshed(newRecord, client: client, registry: registry)
                    let newItem = FileProviderItem(record: remoteRecord, domainDisplayName: self.domain.displayName)
                    progress.completedUnitCount = 1
                    completionHandler(newItem, unsupported, false, nil)
                }
            } catch {
                let mapped = ExternalStorageErrorMapper.mapToNSFileProviderError(error)
                completionHandler(nil, fields, false, mapped)
            }
        }

        progress.cancellationHandler = { task.cancel() }
        return progress
    }

    // MARK: - Modify Item

    func modifyItem(
        _ item: NSFileProviderItem,
        baseVersion version: NSFileProviderItemVersion,
        changedFields: NSFileProviderItemFields,
        contents newContents: URL?,
        options: NSFileProviderModifyItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, (any Error)?) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: 1)

        guard let registry = try? getRegistry() else {
            completionHandler(nil, changedFields, false, NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.Code.notAuthenticated.rawValue, userInfo: nil))
            return progress
        }

        // 根目录绝不允许重命名、修改或移动
        guard item.itemIdentifier != .rootContainer && item.itemIdentifier != .workingSet else {
            completionHandler(nil, changedFields, false, NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.Code.cannotSynchronize.rawValue, userInfo: nil))
            return progress
        }

        guard let currentRecord = registry.resolve(identifier: item.itemIdentifier) else {
            completionHandler(nil, changedFields, false, NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.Code.noSuchItem.rawValue, userInfo: nil))
            return progress
        }

        // 修改冲突不静默覆盖，严格校验 baseVersion
        let currentVersion = currentRecord.version.fileProviderItemVersion
        if currentVersion.contentVersion != version.contentVersion || currentVersion.metadataVersion != version.metadataVersion {
            let conflictError = NSError(
                domain: NSFileProviderErrorDomain,
                code: NSFileProviderError.Code.cannotSynchronize.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "Remote version conflict. Item has been modified."]
            )
            completionHandler(nil, changedFields, false, conflictError)
            return progress
        }

        let task = Task {
            do {
                let client = try self.getClient()
                let fresh = try await refreshed(currentRecord, client: client, registry: registry)
                let freshVersion = fresh.version.fileProviderItemVersion
                guard freshVersion.contentVersion == version.contentVersion,
                      freshVersion.metadataVersion == version.metadataVersion else {
                    throw NSError(
                        domain: NSFileProviderErrorDomain,
                        code: NSFileProviderError.Code.cannotSynchronize.rawValue,
                        userInfo: [NSLocalizedDescriptionKey: "Remote version conflict. Refresh before retrying."]
                    )
                }
                try Task.checkCancellation()
                var updatedRecord = fresh
                let webDAVItem = WebDAVItem(
                    path: fresh.remotePath,
                    name: fresh.filename,
                    kind: fresh.isDirectory ? .directory : .file,
                    contentLength: fresh.contentLength,
                    modifiedAt: fresh.modifiedAt,
                    contentType: fresh.contentType,
                    etag: fresh.etag
                )

                // 1. 处理重命名 / 移动
                if changedFields.contains(.filename) || changedFields.contains(.parentItemIdentifier) {
                    let newName = item.filename
                    try ExternalStoragePathUtility.validatePathComponent(newName)

                    let newParentID = item.parentItemIdentifier
                    guard let newParentRecord = registry.resolve(identifier: newParentID), newParentRecord.isDirectory else {
                        throw ExternalStorageError.itemNotFound(pathOrID: newParentID.rawValue)
                    }

                    let newRemotePath = ExternalStoragePathUtility.join(newParentRecord.remotePath, newName)
                    try ExternalStoragePathUtility.validatePath(newRemotePath)

                    if newRemotePath != currentRecord.remotePath {
                        try await client.move(item: webDAVItem, to: newRemotePath)
                        // 子树路径更新而 ID 保持不变
                        updatedRecord = try registry.renameOrMove(
                            identifier: item.itemIdentifier,
                            newParentIdentifier: newParentID,
                            newName: newName,
                            newRemotePath: newRemotePath
                        )
                    }
                }

                // 2. 处理文件内容修改
                if changedFields.contains(.contents) {
                    guard let localURL = newContents, !updatedRecord.isDirectory else {
                        throw ExternalStorageError.invalidRemotePath(path: updatedRecord.remotePath)
                    }

                    let currentWebDAVItem = WebDAVItem(
                        path: updatedRecord.remotePath,
                        name: updatedRecord.filename,
                        kind: .file,
                        contentLength: updatedRecord.contentLength,
                        modifiedAt: updatedRecord.modifiedAt,
                        contentType: updatedRecord.contentType,
                        etag: updatedRecord.etag
                    )

                    try await client.replace(localURL: localURL, item: currentWebDAVItem, force: false)

                    let attrs = try? FileManager.default.attributesOfItem(atPath: localURL.path)
                    let newSize = (attrs?[.size] as? NSNumber)?.int64Value
                    let newMtime = (attrs?[.modificationDate] as? Date) ?? Date()

                    updatedRecord = try registry.registerOrUpdate(
                        remotePath: updatedRecord.remotePath,
                        name: updatedRecord.filename,
                        isDirectory: false,
                        parentIdentifier: updatedRecord.parentItemIdentifier,
                        contentLength: newSize,
                        modifiedAt: newMtime,
                        contentType: updatedRecord.contentType,
                        etag: nil
                    )
                }

                // 3. 计算不支持的变更字段并返回，绝不虚报全部成功
                updatedRecord = try await refreshed(updatedRecord, client: client, registry: registry)
                let supportedFields: NSFileProviderItemFields = [.filename, .parentItemIdentifier, .contents]
                let remainingFields = changedFields.subtracting(supportedFields)

                let finalItem = FileProviderItem(record: updatedRecord, domainDisplayName: self.domain.displayName)
                progress.completedUnitCount = 1
                completionHandler(finalItem, remainingFields, false, nil)
            } catch {
                let mapped = ExternalStorageErrorMapper.mapToNSFileProviderError(error)
                completionHandler(nil, changedFields, false, mapped)
            }
        }

        progress.cancellationHandler = { task.cancel() }
        return progress
    }

    // MARK: - Delete Item

    func deleteItem(
        identifier: NSFileProviderItemIdentifier,
        baseVersion version: NSFileProviderItemVersion,
        options: NSFileProviderDeleteItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping ((any Error)?) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: 1)

        guard let registry = try? getRegistry() else {
            completionHandler(NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.Code.notAuthenticated.rawValue, userInfo: nil))
            return progress
        }

        // 绝对拒绝删除根目录或 workingSet
        guard identifier != .rootContainer && identifier != .workingSet && identifier != .trashContainer else {
            completionHandler(NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.Code.deletionRejected.rawValue, userInfo: nil))
            return progress
        }

        guard let record = registry.resolve(identifier: identifier) else {
            completionHandler(NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.Code.noSuchItem.rawValue, userInfo: nil))
            return progress
        }

        let task = Task {
            do {
                let client = try self.getClient()
                let parentPath = ExternalStoragePathUtility.parentPath(of: record.remotePath)

                // 关键验收要求：必须比较传入 baseVersion 与刷新后远端版本再删除
                let remoteItems = try await client.list(path: parentPath)
                if let remoteItem = remoteItems.first(where: { $0.path == record.remotePath }) {
                    do {
                        let remoteVersion = ItemVersionRecord.make(
                            etag: remoteItem.etag,
                            modifiedAt: remoteItem.modifiedAt,
                            contentLength: remoteItem.contentLength
                        )
                        if remoteVersion.fileProviderItemVersion.contentVersion != version.contentVersion {
                            throw NSError(
                                domain: NSFileProviderErrorDomain,
                                code: NSFileProviderError.Code.cannotSynchronize.rawValue,
                                userInfo: [NSLocalizedDescriptionKey: "Remote version conflict before deletion"]
                            )
                        }
                    }
                    try await client.delete(item: remoteItem)
                }

                try registry.delete(identifier: identifier)
                progress.completedUnitCount = 1
                completionHandler(nil)
            } catch {
                let mapped = ExternalStorageErrorMapper.mapToNSFileProviderError(error)
                completionHandler(mapped)
            }
        }

        progress.cancellationHandler = { task.cancel() }
        return progress
    }

    // MARK: - Enumerator

    func enumerator(
        for containerItemIdentifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest
    ) throws -> any NSFileProviderEnumerator {
        let reg = try getRegistry()
        let cli = try getClient()

        return FileProviderEnumerator(
            containerItemIdentifier: containerItemIdentifier,
            registry: reg,
            client: cli,
            domainDisplayName: domain.displayName
        )
    }
}
