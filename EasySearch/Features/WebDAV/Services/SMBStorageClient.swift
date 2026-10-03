import Foundation
import AMSMB2

final class SMBStorageClient: @unchecked Sendable {
    private let configuration: WebDAVConfiguration
    private let fileManager: FileManager

    init(configuration: WebDAVConfiguration, fileManager: FileManager = .default) {
        self.configuration = configuration
        self.fileManager = fileManager
    }

    // MARK: - Connection & Target Parsing

    struct SMBConnectionTarget {
        let serverURL: URL
        let shareName: String
        let baseFolder: String
    }

    func parseTarget() throws -> SMBConnectionTarget {
        guard configuration.isValid, configuration.isSMB else {
            throw WebDAVError.invalidConfiguration
        }
        guard let host = configuration.baseURL.host, !host.isEmpty else {
            throw WebDAVError.invalidURL
        }

        // Inline credentials in URL are prohibited to prevent plain-text exposure in UserDefaults
        if configuration.baseURL.user != nil || configuration.baseURL.password != nil {
            throw WebDAVError.invalidURL
        }

        let rawPath = configuration.baseURL.path
        if rawPath.contains("..") || rawPath.contains("\\") || rawPath.contains("\0") {
            throw WebDAVError.invalidURL
        }

        var urlComponents = URLComponents()
        urlComponents.scheme = "smb"
        urlComponents.host = host
        urlComponents.port = configuration.baseURL.port

        guard let serverURL = urlComponents.url else {
            throw WebDAVError.invalidURL
        }

        let segments = rawPath
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }

        for segment in segments {
            if segment == "." || segment == ".." || segment.contains("\\") || segment.contains("\0") {
                throw WebDAVError.invalidURL
            }
        }

        guard let shareName = segments.first, !shareName.isEmpty else {
            throw WebDAVError.invalidURL
        }

        let baseFolder = segments.dropFirst().joined(separator: "/")
        return SMBConnectionTarget(serverURL: serverURL, shareName: shareName, baseFolder: baseFolder)
    }

    private func connect() async throws -> (SMB2Manager, String) {
        let target = try parseTarget()
        let credential = URLCredential(
            user: configuration.username,
            password: configuration.password,
            persistence: .none
        )
        guard let manager = SMB2Manager(url: target.serverURL, credential: credential) else {
            throw WebDAVError.invalidURL
        }
        try await manager.connectShare(name: target.shareName)
        return (manager, target.baseFolder)
    }

    func resolveSMBPath(baseFolder: String, relativePath: String) throws -> String {
        let cleanRel = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))
        let segments = cleanRel.split(separator: "/").map(String.init)
        guard !segments.contains(where: { $0 == "." || $0 == ".." || $0.contains("..") || $0.contains("\\") || $0.contains("\0") }) else {
            throw WebDAVError.invalidURL
        }

        let cleanBase = baseFolder.trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))
        if cleanBase.contains("..") || cleanBase.contains("\\") || cleanBase.contains("\0") {
            throw WebDAVError.invalidURL
        }

        if cleanBase.isEmpty {
            return segments.joined(separator: "/")
        }
        if segments.isEmpty {
            return cleanBase
        }
        return "\(cleanBase)/\(segments.joined(separator: "/"))"
    }

    // MARK: - Cancellation Support

    final class SMBCancellationBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _isCancelled = false

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return _isCancelled
        }

        func cancel() {
            lock.lock()
            _isCancelled = true
            lock.unlock()
        }
    }

    // MARK: - Error Classification Helpers

    private func isNotFoundError(_ error: Error) -> Bool {
        if let posix = error as? POSIXError, posix.code == .ENOENT {
            return true
        }
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain && ns.code == Int(POSIXError.Code.ENOENT.rawValue) {
            return true
        }
        let desc = error.localizedDescription.lowercased()
        return desc.contains("no such file") || desc.contains("not found") || desc.contains("enoent")
    }

    private func isAlreadyExistsError(_ error: Error) -> Bool {
        if let posix = error as? POSIXError, posix.code == .EEXIST {
            return true
        }
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain && ns.code == Int(POSIXError.Code.EEXIST.rawValue) {
            return true
        }
        let desc = error.localizedDescription.lowercased()
        return desc.contains("exist") || desc.contains("collision") || desc.contains("eexist")
    }

    // MARK: - Operations

    func list(path: String = "") async throws -> [WebDAVItem] {
        let (manager, baseFolder) = try await connect()
        let smbPath = try resolveSMBPath(baseFolder: baseFolder, relativePath: path)
        let entries = try await manager.contentsOfDirectory(atPath: smbPath)

        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))
        var items: [WebDAVItem] = []

        for entry in entries {
            guard let name = entry[.nameKey] as? String, !name.isEmpty, name != ".", name != ".." else {
                continue
            }
            let isDirectory = (entry[.isDirectoryKey] as? NSNumber)?.boolValue ?? false
            let size = (entry[.fileSizeKey] as? NSNumber)?.int64Value
            let modDate = entry[.contentModificationDateKey] as? Date
            let itemPath = cleanPath.isEmpty ? name : "\(cleanPath)/\(name)"

            items.append(WebDAVItem(
                path: itemPath,
                name: name,
                kind: isDirectory ? .directory : .file,
                contentLength: isDirectory ? nil : size,
                modifiedAt: modDate,
                contentType: nil,
                etag: nil
            ))
        }

        return items.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func createDirectory(path: String) async throws {
        let (manager, baseFolder) = try await connect()
        let smbPath = try resolveSMBPath(baseFolder: baseFolder, relativePath: path)
        try await manager.createDirectory(atPath: smbPath)
    }

    func delete(item: WebDAVItem) async throws {
        let (manager, baseFolder) = try await connect()
        let smbPath = try resolveSMBPath(baseFolder: baseFolder, relativePath: item.path)
        if item.isDirectory {
            try await manager.removeDirectory(atPath: smbPath, recursive: true)
        } else {
            try await manager.removeItem(atPath: smbPath)
        }
    }

    func move(item: WebDAVItem, to destinationPath: String) async throws {
        let cleanDest = destinationPath.trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))
        guard !cleanDest.isEmpty else { throw WebDAVError.invalidDestination }
        guard cleanDest != item.path else { return }

        if item.isDirectory {
            if cleanDest == item.path || cleanDest.hasPrefix(item.path + "/") {
                throw WebDAVError.destinationIsDescendant
            }
        }

        let (manager, baseFolder) = try await connect()
        let sourceSMB = try resolveSMBPath(baseFolder: baseFolder, relativePath: item.path)
        let destSMB = try resolveSMBPath(baseFolder: baseFolder, relativePath: cleanDest)

        // Pre-check if destination exists; only proceed if error is explicitly not found
        do {
            _ = try await manager.attributesOfItem(atPath: destSMB)
            throw WebDAVError.destinationExists
        } catch let err as WebDAVError {
            throw err
        } catch {
            guard isNotFoundError(error) else {
                throw error
            }
        }

        // AMSMB2 moveItem uses smb2_rename_async with rn_info.replace_if_exist = 0,
        // which enforces server-side non-overwriting atomic rename.
        do {
            try await manager.moveItem(atPath: sourceSMB, toPath: destSMB)
        } catch {
            if isAlreadyExistsError(error) {
                throw WebDAVError.destinationExists
            }
            throw error
        }
    }

    func uploadExact(localURL: URL, remotePath: String) async throws {
        guard fileManager.fileExists(atPath: localURL.path) else {
            throw WebDAVError.localFileMissing
        }
        let resourceValues = try localURL.resourceValues(forKeys: [.isSymbolicLinkKey])
        if resourceValues.isSymbolicLink == true {
            throw WebDAVError.symbolicLinkUnsupported
        }

        let (manager, baseFolder) = try await connect()
        let smbPath = try resolveSMBPath(baseFolder: baseFolder, relativePath: remotePath)

        // Check if destination exists
        do {
            _ = try await manager.attributesOfItem(atPath: smbPath)
            throw WebDAVError.destinationExists
        } catch let err as WebDAVError {
            throw err
        } catch {
            guard isNotFoundError(error) else {
                throw error
            }
        }

        // Upload to a temporary file in the same directory, then move into place
        let parentSMB = smbPath.split(separator: "/").dropLast().joined(separator: "/")
        let tmpFileName = ".tmp.\(UUID().uuidString).\(localURL.lastPathComponent)"
        let tmpPath = parentSMB.isEmpty ? tmpFileName : "\(parentSMB)/\(tmpFileName)"

        let cancelBox = SMBCancellationBox()
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    manager.uploadItem(at: localURL, toPath: tmpPath, progress: { _ in
                        if cancelBox.isCancelled { return false }
                        return true
                    }) { error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: ())
                        }
                    }
                }
            } onCancel: {
                cancelBox.cancel()
            }

            if cancelBox.isCancelled {
                try? await manager.removeItem(atPath: tmpPath)
                throw CancellationError()
            }

            try await manager.moveItem(atPath: tmpPath, toPath: smbPath)
        } catch {
            // Clean up temporary file on ANY failure path
            try? await manager.removeItem(atPath: tmpPath)
            if isAlreadyExistsError(error) {
                throw WebDAVError.destinationExists
            }
            throw error
        }
    }

    func upload(localURL: URL, remotePath: String) async throws {
        guard fileManager.fileExists(atPath: localURL.path) else {
            throw WebDAVError.localFileMissing
        }

        let resourceValues = try localURL.resourceValues(forKeys: [.isSymbolicLinkKey])
        if resourceValues.isSymbolicLink == true {
            throw WebDAVError.symbolicLinkUnsupported
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: localURL.path, isDirectory: &isDirectory) else {
            throw WebDAVError.localFileMissing
        }

        if isDirectory.boolValue {
            let createdPath = try await createUniqueDirectory(requestedPath: remotePath)
            let children = try fileManager.contentsOfDirectory(
                at: localURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                if try child.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                    continue
                }
                try await upload(localURL: child, remotePath: join(createdPath, child.lastPathComponent))
            }
            return
        }

        try await uploadSingleFile(localURL: localURL, requestedPath: remotePath)
    }

    private func uploadSingleFile(localURL: URL, requestedPath: String) async throws {
        let (manager, baseFolder) = try await connect()
        for attempt in 1...1_000 {
            let candidatePath = uniqueRemotePath(requestedPath, attempt: attempt, isDirectory: false)
            let smbPath = try resolveSMBPath(baseFolder: baseFolder, relativePath: candidatePath)

            var exists = false
            do {
                _ = try await manager.attributesOfItem(atPath: smbPath)
                exists = true
            } catch {
                if isNotFoundError(error) {
                    exists = false
                } else {
                    throw error
                }
            }
            if exists { continue }

            let parentSMB = smbPath.split(separator: "/").dropLast().joined(separator: "/")
            let tmpFileName = ".tmp.\(UUID().uuidString).\(localURL.lastPathComponent)"
            let tmpPath = parentSMB.isEmpty ? tmpFileName : "\(parentSMB)/\(tmpFileName)"

            let cancelBox = SMBCancellationBox()
            do {
                try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        manager.uploadItem(at: localURL, toPath: tmpPath, progress: { _ in
                            if cancelBox.isCancelled { return false }
                            return true
                        }) { error in
                            if let error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume(returning: ())
                            }
                        }
                    }
                } onCancel: {
                    cancelBox.cancel()
                }

                if cancelBox.isCancelled {
                    try? await manager.removeItem(atPath: tmpPath)
                    throw CancellationError()
                }

                try await manager.moveItem(atPath: tmpPath, toPath: smbPath)
                return
            } catch {
                try? await manager.removeItem(atPath: tmpPath)
                if isAlreadyExistsError(error) {
                    continue
                }
                throw error
            }
        }
        throw WebDAVError.tooManyNameConflicts
    }

    private func createUniqueDirectory(requestedPath: String) async throws -> String {
        let (manager, baseFolder) = try await connect()
        for attempt in 1...1_000 {
            let candidatePath = uniqueRemotePath(requestedPath, attempt: attempt, isDirectory: true)
            let smbPath = try resolveSMBPath(baseFolder: baseFolder, relativePath: candidatePath)

            do {
                try await manager.createDirectory(atPath: smbPath)
                return candidatePath
            } catch {
                // Only retry if the directory already exists (EEXIST); do not loop on permission/network errors!
                if isAlreadyExistsError(error) {
                    continue
                }
                throw error
            }
        }
        throw WebDAVError.tooManyNameConflicts
    }

    /// SMB replacement with 2-step backup-and-swap and optimistic concurrency check.
    ///
    /// Note: SMB protocol does not provide unconditional atomic CAS (Compare-And-Swap) headers
    /// like HTTP If-Match ETag. To prevent data loss, this method:
    /// 1. Uploads to staging (.tmp...)
    /// 2. If !force: checks original file mtime and size, aborting with .editConflict on mismatch
    /// 3. Moves original file to a backup path (.bak...)
    /// 4. Moves staged file into target
    /// 5. If moving staged file fails, restores backup; errors NEVER delete the backup file
    /// 6. Removes backup only after target is safely verified
    func replace(localURL: URL, item: WebDAVItem, force: Bool = false) async throws {
        guard !item.isDirectory, fileManager.fileExists(atPath: localURL.path) else {
            throw WebDAVError.localFileMissing
        }

        let (manager, baseFolder) = try await connect()
        let smbPath = try resolveSMBPath(baseFolder: baseFolder, relativePath: item.path)

        let parentSMB = smbPath.split(separator: "/").dropLast().joined(separator: "/")
        let tmpFileName = ".tmp.\(UUID().uuidString).\(localURL.lastPathComponent)"
        let tmpPath = parentSMB.isEmpty ? tmpFileName : "\(parentSMB)/\(tmpFileName)"

        // 1. Upload to temporary staging
        let cancelBox = SMBCancellationBox()
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    manager.uploadItem(at: localURL, toPath: tmpPath, progress: { _ in
                        if cancelBox.isCancelled { return false }
                        return true
                    }) { error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: ())
                        }
                    }
                }
            } onCancel: {
                cancelBox.cancel()
            }

            if cancelBox.isCancelled {
                try? await manager.removeItem(atPath: tmpPath)
                throw CancellationError()
            }
        } catch {
            try? await manager.removeItem(atPath: tmpPath)
            throw error
        }

        // Recheck after staging; deletion is a conflict, not an implicit create.
        // SMB has no atomic compare-and-swap equivalent to HTTP If-Match.
        do {
            try Task.checkCancellation()
            if !force {
                let currentAttrs = try await manager.attributesOfItem(atPath: smbPath)
                if let expectedMTime = item.modifiedAt {
                    guard let actualMTime = currentAttrs[.contentModificationDateKey] as? Date,
                          abs(actualMTime.timeIntervalSince(expectedMTime)) <= 0.000001 else {
                        throw WebDAVError.editConflict
                    }
                }
                if let expectedLength = item.contentLength {
                    guard let actualLength = (currentAttrs[.fileSizeKey] as? NSNumber)?.int64Value,
                          actualLength == expectedLength else {
                        throw WebDAVError.editConflict
                    }
                }
            }
        } catch {
            try? await manager.removeItem(atPath: tmpPath)
            if isNotFoundError(error) { throw WebDAVError.editConflict }
            throw error
        }

        // 3. Rename original file to backup
        let backupFileName = ".bak.\(UUID().uuidString).\(localURL.lastPathComponent)"
        let backupPath = parentSMB.isEmpty ? backupFileName : "\(parentSMB)/\(backupFileName)"
        var didBackup = false

        do {
            try await manager.moveItem(atPath: smbPath, toPath: backupPath)
            didBackup = true
        } catch {
            if isNotFoundError(error), force {
                didBackup = false
            } else {
                try? await manager.removeItem(atPath: tmpPath)
                throw error
            }
        }

        // 4. Move staged file into target
        do {
            try await manager.moveItem(atPath: tmpPath, toPath: smbPath)
            // 5. On success, remove backup
            if didBackup {
                try? await manager.removeItem(atPath: backupPath)
            }
        } catch {
            // Restore backup if original was moved; NEVER delete backup on failure
            if didBackup {
                try? await manager.moveItem(atPath: backupPath, toPath: smbPath)
            }
            try? await manager.removeItem(atPath: tmpPath)
            throw error
        }
    }

    func download(
        item: WebDAVItem,
        into localDirectory: URL,
        progress: @escaping (WebDAVTransferProgress) -> Void
    ) async throws -> URL {
        try fileManager.createDirectory(at: localDirectory, withIntermediateDirectories: true)
        let (manager, baseFolder) = try await connect()

        let rootName = WebDAVLocalFileStore.sanitizedFileName(item.name)
        let stagingRoot = fileManager.temporaryDirectory
            .appendingPathComponent("EasySearchSMBDownloads", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let stagedRoot = stagingRoot.appendingPathComponent(rootName, isDirectory: item.isDirectory)

        do {
            try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
            if item.isDirectory {
                let plan = try await makeDownloadPlan(manager: manager, baseFolder: baseFolder, root: item)
                for dir in plan.directories {
                    let target = stagingRoot.appendingPathComponent(dir.relativePath, isDirectory: true)
                    try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
                }

                var completedBytes: Int64 = 0
                var completedFiles = 0
                progress(WebDAVTransferProgress(
                    completedBytes: 0,
                    totalBytes: plan.totalBytes,
                    completedFiles: 0,
                    totalFiles: plan.files.count
                ))

                for file in plan.files {
                    try Task.checkCancellation()
                    let target = stagingRoot.appendingPathComponent(file.relativePath, isDirectory: false)
                    try fileManager.createDirectory(
                        at: target.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )

                    let smbFilePath = try resolveSMBPath(baseFolder: baseFolder, relativePath: file.item.path)
                    let bytesWritten = try await downloadSingleSMBFile(
                        manager: manager,
                        smbPath: smbFilePath,
                        to: target
                    ) { written, _ in
                        progress(WebDAVTransferProgress(
                            completedBytes: completedBytes + written,
                            totalBytes: plan.totalBytes,
                            completedFiles: completedFiles,
                            totalFiles: plan.files.count
                        ))
                    }
                    completedBytes += bytesWritten
                    completedFiles += 1
                    progress(WebDAVTransferProgress(
                        completedBytes: completedBytes,
                        totalBytes: plan.totalBytes,
                        completedFiles: completedFiles,
                        totalFiles: plan.files.count
                    ))
                }
            } else {
                progress(WebDAVTransferProgress(
                    completedBytes: 0,
                    totalBytes: item.contentLength,
                    completedFiles: 0,
                    totalFiles: 1
                ))
                let smbFilePath = try resolveSMBPath(baseFolder: baseFolder, relativePath: item.path)
                let bytesWritten = try await downloadSingleSMBFile(
                    manager: manager,
                    smbPath: smbFilePath,
                    to: stagedRoot
                ) { written, total in
                    progress(WebDAVTransferProgress(
                        completedBytes: written,
                        totalBytes: total > 0 ? total : item.contentLength,
                        completedFiles: 0,
                        totalFiles: 1
                    ))
                }
                progress(WebDAVTransferProgress(
                    completedBytes: bytesWritten,
                    totalBytes: item.contentLength ?? bytesWritten,
                    completedFiles: 1,
                    totalFiles: 1
                ))
            }

            try Task.checkCancellation()
            let finalTarget = WebDAVLocalFileStore.uniqueURL(
                for: localDirectory.appendingPathComponent(rootName, isDirectory: item.isDirectory)
            )
            try fileManager.moveItem(at: stagedRoot, to: finalTarget)
            try? fileManager.removeItem(at: stagingRoot)
            return finalTarget
        } catch {
            try? fileManager.removeItem(at: stagingRoot)
            throw error
        }
    }

    func downloadForPreview(
        item: WebDAVItem,
        progress: @escaping (WebDAVTransferProgress) -> Void
    ) async throws -> URL {
        guard !item.isDirectory else { throw WebDAVError.invalidURL }
        let (manager, baseFolder) = try await connect()

        let previewDirectory = try WebDAVLocalFileStore.makePreviewDirectory()
        let target = previewDirectory.appendingPathComponent(
            WebDAVLocalFileStore.sanitizedFileName(item.name),
            isDirectory: false
        )

        do {
            let smbFilePath = try resolveSMBPath(baseFolder: baseFolder, relativePath: item.path)
            let bytesWritten = try await downloadSingleSMBFile(
                manager: manager,
                smbPath: smbFilePath,
                to: target
            ) { written, total in
                progress(WebDAVTransferProgress(
                    completedBytes: written,
                    totalBytes: total > 0 ? total : item.contentLength,
                    completedFiles: 0,
                    totalFiles: 1
                ))
            }

            progress(WebDAVTransferProgress(
                completedBytes: bytesWritten,
                totalBytes: item.contentLength ?? bytesWritten,
                completedFiles: 1,
                totalFiles: 1
            ))
            return target
        } catch {
            try? fileManager.removeItem(at: previewDirectory)
            throw error
        }
    }

    private func downloadSingleSMBFile(
        manager: SMB2Manager,
        smbPath: String,
        to targetURL: URL,
        progress: @escaping (Int64, Int64) -> Void
    ) async throws -> Int64 {
        let tempURL = fileManager.temporaryDirectory
            .appendingPathComponent("EasySearchSMBDownload-\(UUID().uuidString).tmp")

        let cancelBox = SMBCancellationBox()
        var lastBytesWritten: Int64 = 0

        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    manager.downloadItem(atPath: smbPath, to: tempURL) { written, total in
                        if cancelBox.isCancelled {
                            return false
                        }
                        lastBytesWritten = written
                        progress(written, total)
                        return true
                    } completionHandler: { error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: ())
                        }
                    }
                }
            } onCancel: {
                cancelBox.cancel()
            }

            if cancelBox.isCancelled {
                try? fileManager.removeItem(at: tempURL)
                throw CancellationError()
            }

            try Task.checkCancellation()
            if fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }
            try fileManager.moveItem(at: tempURL, to: targetURL)
            if lastBytesWritten == 0 {
                let size = (try? targetURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
                lastBytesWritten = Int64(size ?? 0)
            }
            return lastBytesWritten
        } catch {
            try? fileManager.removeItem(at: tempURL)
            throw error
        }
    }

    func details(for item: WebDAVItem) async throws -> WebDAVItemDetails {
        if !item.isDirectory {
            return WebDAVItemDetails(
                fileCount: 1,
                folderCount: 0,
                totalSize: item.contentLength ?? 0,
                unknownSizeFileCount: item.contentLength == nil ? 1 : 0
            )
        }
        let (manager, baseFolder) = try await connect()
        let plan = try await makeDownloadPlan(manager: manager, baseFolder: baseFolder, root: item)
        return WebDAVItemDetails(
            fileCount: plan.files.count,
            folderCount: max(0, plan.directories.count - 1),
            totalSize: plan.files.reduce(0) { $0 + max($1.item.contentLength ?? 0, 0) },
            unknownSizeFileCount: plan.files.filter { $0.item.contentLength == nil }.count
        )
    }

    // MARK: - Plan & Helper

    private struct PlannedItem {
        let item: WebDAVItem
        let relativePath: String
    }

    private struct DownloadPlan {
        let directories: [PlannedItem]
        let files: [PlannedItem]
        let totalBytes: Int64?
    }

    private func makeDownloadPlan(manager: SMB2Manager, baseFolder: String, root: WebDAVItem) async throws -> DownloadPlan {
        let rootName = WebDAVLocalFileStore.sanitizedFileName(root.name)
        var pending = [PlannedItem(item: root, relativePath: rootName)]
        var directories: [PlannedItem] = []
        var files: [PlannedItem] = []
        var visited = Set<String>()

        while let current = pending.popLast() {
            try Task.checkCancellation()
            if current.item.isDirectory {
                guard visited.insert(current.item.path).inserted else { continue }
                directories.append(current)
                let smbPath = try resolveSMBPath(baseFolder: baseFolder, relativePath: current.item.path)
                let entries = try await manager.contentsOfDirectory(atPath: smbPath)
                let cleanRel = current.item.path.trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))

                var usedNames = Set<String>()
                var childItems: [PlannedItem] = []

                for entry in entries {
                    guard let name = entry[.nameKey] as? String, !name.isEmpty, name != ".", name != ".." else {
                        continue
                    }
                    let isDir = (entry[.isDirectoryKey] as? NSNumber)?.boolValue ?? false
                    let size = (entry[.fileSizeKey] as? NSNumber)?.int64Value
                    let modDate = entry[.contentModificationDateKey] as? Date
                    let childPath = cleanRel.isEmpty ? name : "\(cleanRel)/\(name)"

                    let childWebDAVItem = WebDAVItem(
                        path: childPath,
                        name: name,
                        kind: isDir ? .directory : .file,
                        contentLength: isDir ? nil : size,
                        modifiedAt: modDate,
                        contentType: nil,
                        etag: nil
                    )
                    let component = uniqueLocalName(
                        WebDAVLocalFileStore.sanitizedFileName(name),
                        isDirectory: isDir,
                        usedNames: &usedNames
                    )
                    childItems.append(PlannedItem(
                        item: childWebDAVItem,
                        relativePath: join(current.relativePath, component)
                    ))
                }
                pending.append(contentsOf: childItems.reversed())
            } else {
                files.append(current)
            }
        }

        let hasUnknownSize = files.contains { ($0.item.contentLength ?? -1) < 0 }
        let totalBytes = hasUnknownSize ? nil : files.reduce(Int64(0)) { $0 + ($1.item.contentLength ?? 0) }
        return DownloadPlan(directories: directories, files: files, totalBytes: totalBytes)
    }

    private func uniqueLocalName(
        _ requestedName: String,
        isDirectory: Bool,
        usedNames: inout Set<String>
    ) -> String {
        guard usedNames.contains(requestedName) else {
            usedNames.insert(requestedName)
            return requestedName
        }
        let source = requestedName as NSString
        let ext = isDirectory ? "" : source.pathExtension
        let stem = ext.isEmpty ? requestedName : source.deletingPathExtension
        var index = 2
        while true {
            let candidate = ext.isEmpty ? "\(stem) (\(index))" : "\(stem) (\(index)).\(ext)"
            if usedNames.insert(candidate).inserted { return candidate }
            index += 1
        }
    }

    private func uniqueRemotePath(_ requestedPath: String, attempt: Int, isDirectory: Bool) -> String {
        guard attempt > 1 else { return requestedPath }
        let parent = parentPath(of: requestedPath)
        let name = requestedPath.split(separator: "/").last.map(String.init) ?? "未命名文件"
        let renamed: String
        if isDirectory {
            renamed = "\(name) (\(attempt))"
        } else {
            let fileName = name as NSString
            let ext = fileName.pathExtension
            let stem = fileName.deletingPathExtension
            renamed = ext.isEmpty ? "\(stem) (\(attempt))" : "\(stem) (\(attempt)).\(ext)"
        }
        return join(parent, renamed)
    }

    private func parentPath(of path: String) -> String {
        let parts = path.split(separator: "/")
        guard parts.count > 1 else { return "" }
        return parts.dropLast().joined(separator: "/")
    }

    private func join(_ lhs: String, _ rhs: String) -> String {
        let left = lhs.trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))
        let right = rhs.trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))
        if left.isEmpty { return right }
        if right.isEmpty { return left }
        return "\(left)/\(right)"
    }
}
