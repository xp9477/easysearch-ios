import FileProvider
import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import EasySearch

// MARK: - Mocks & Stubs

private final class MockExternalStorageKeychain: ExternalStorageKeychainProtocol, @unchecked Sendable {
    private var passwords: [UUID: String] = [:]
    private let lock = NSLock()
    var failOnPassword: String?

    func savePassword(password: String, locationID: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        if let failOnPassword, password == failOnPassword {
            throw ExternalStorageError.keychainFailure(status: -1)
        }
        passwords[locationID] = password
    }

    func readPassword(locationID: UUID) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        guard let pass = passwords[locationID] else {
            throw ExternalStorageError.passwordNotFound(locationID: locationID)
        }
        return pass
    }

    func deletePassword(locationID: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        passwords.removeValue(forKey: locationID)
    }

    func storedPasswordCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return passwords.count
    }
}

private final class MockExternalStorageClient: ExternalStorageClientProtocol, @unchecked Sendable {
    var itemsToList: [WebDAVItem] = []
    var shouldFailListWithError: Error?
    var uploadedPaths: [String] = []
    var movedPaths: [(from: String, to: String)] = []
    var deletedPaths: [String] = []

    func list(path: String) async throws -> [WebDAVItem] {
        if let err = shouldFailListWithError {
            throw err
        }
        return itemsToList
    }

    func createDirectory(path: String) async throws {}

    func uploadExact(localURL: URL, remotePath: String) async throws {
        uploadedPaths.append(remotePath)
    }

    func move(item: WebDAVItem, to newPath: String) async throws {
        movedPaths.append((from: item.path, to: newPath))
    }

    func delete(item: WebDAVItem) async throws {
        deletedPaths.append(item.path)
    }

    func replace(localURL: URL, item: WebDAVItem, force: Bool) async throws {}

    func downloadForPreview(
        item: WebDAVItem,
        progress: @escaping (WebDAVTransferProgress) -> Void
    ) async throws -> URL {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("test".utf8).write(to: temp)
        return temp
    }

    func makeStreamingRequest(for item: WebDAVItem, rangeHeader: String?) throws -> URLRequest {
        URLRequest(url: URL(string: "https://example.com/test")!)
    }
}

private final class MockChangeObserver: NSObject, NSFileProviderChangeObserver {
    var updatedItems: [any NSFileProviderItemProtocol] = []
    var deletedIdentifiers: [NSFileProviderItemIdentifier] = []
    var finishedAnchor: NSFileProviderSyncAnchor?
    var finishedError: Error?

    func didUpdate(_ updatedItems: [any NSFileProviderItemProtocol]) {
        self.updatedItems.append(contentsOf: updatedItems)
    }

    func didDeleteItems(withIdentifiers deletedItemIdentifiers: [NSFileProviderItemIdentifier]) {
        self.deletedIdentifiers.append(contentsOf: deletedItemIdentifiers)
    }

    func finishEnumeratingChanges(upTo anchor: NSFileProviderSyncAnchor, moreComing: Bool) {
        self.finishedAnchor = anchor
    }

    func finishEnumeratingWithError(_ error: Error) {
        self.finishedError = error
    }
}

private final class MockEnumerationObserver: NSObject, NSFileProviderEnumerationObserver {
    var items: [any NSFileProviderItemProtocol] = []
    var finishedError: Error?
    var nextPage: NSFileProviderPage?
    let completion: XCTestExpectation

    init(completion: XCTestExpectation) {
        self.completion = completion
        super.init()
    }

    func didEnumerate(_ updatedItems: [any NSFileProviderItemProtocol]) {
        items.append(contentsOf: updatedItems)
    }

    func finishEnumerating(upTo nextPage: NSFileProviderPage?) {
        self.nextPage = nextPage
        completion.fulfill()
    }

    func finishEnumeratingWithError(_ error: Error) {
        finishedError = error
        completion.fulfill()
    }
}

// MARK: - Test Case

final class ExternalStorageProviderTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExternalStorageTests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try super.tearDownWithError()
    }

    // MARK: - 1. Identifier Roundtrip & Persistence

    func testIdentifierRegistryRoundtrip() throws {
        let domainID = UUID().uuidString
        let registry1 = try ExternalStorageItemRegistry(domainID: domainID, baseStorageURL: tempDirectory)

        let file1 = try registry1.registerOrUpdate(
            remotePath: "folder/test.pdf",
            name: "test.pdf",
            isDirectory: false,
            parentIdentifier: .rootContainer,
            contentLength: 1024,
            modifiedAt: Date(timeIntervalSince1970: 1700000000),
            contentType: "application/pdf",
            etag: "\"etag-123\""
        )

        let initialUUID = file1.id
        XCTAssertFalse(initialUUID.isEmpty)

        // 重新从相同持久化文件加载新 registry 实例
        let registry2 = try ExternalStorageItemRegistry(domainID: domainID, baseStorageURL: tempDirectory)
        let resolved = registry2.resolve(remotePath: "folder/test.pdf")

        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.id, initialUUID, "持久化恢复后相同路径必须返回相同的稳定 UUID")
        XCTAssertEqual(resolved?.filename, "test.pdf")
        XCTAssertEqual(resolved?.contentLength, 1024)
        XCTAssertEqual(resolved?.etag, "\"etag-123\"")
        XCTAssertEqual(resolved?.version.contentVersionString, "etag-123")
    }

    // MARK: - 2. Traversal Protection

    func testTraversalProtection() throws {
        let domainID = UUID().uuidString
        let registry = try ExternalStorageItemRegistry(domainID: domainID, baseStorageURL: tempDirectory)

        XCTAssertThrowsError(try registry.registerOrUpdate(
            remotePath: "../secret.txt",
            name: "secret.txt",
            isDirectory: false,
            parentIdentifier: .rootContainer
        )) { error in
            guard case ExternalStorageError.traversalDetected = error else {
                XCTFail("应当拦截 .. 路径穿越并抛出 traversalDetected，得到：\(error)")
                return
            }
        }

        XCTAssertThrowsError(try registry.registerOrUpdate(
            remotePath: "folder/../../root.txt",
            name: "root.txt",
            isDirectory: false,
            parentIdentifier: .rootContainer
        )) { error in
            guard case ExternalStorageError.traversalDetected = error else {
                XCTFail("应当拦截多级 .. 路径穿越，得到：\(error)")
                return
            }
        }

        XCTAssertThrowsError(try ExternalStoragePathUtility.validatePathComponent("evil/name"))
        XCTAssertThrowsError(try ExternalStoragePathUtility.validatePathComponent(".."))
    }

    // MARK: - 3. Rename Descendants (Subtree Path Migration with Stable UUIDs)

    func testRenameAndMoveUpdatesDescendantsWhilePreservingUUIDs() throws {
        let domainID = UUID().uuidString
        let registry = try ExternalStorageItemRegistry(domainID: domainID, baseStorageURL: tempDirectory)

        let docDir = try registry.registerOrUpdate(
            remotePath: "Documents",
            name: "Documents",
            isDirectory: true,
            parentIdentifier: .rootContainer
        )
        let workDir = try registry.registerOrUpdate(
            remotePath: "Documents/Work",
            name: "Work",
            isDirectory: true,
            parentIdentifier: docDir.itemIdentifier
        )
        let notesFile = try registry.registerOrUpdate(
            remotePath: "Documents/Work/notes.txt",
            name: "notes.txt",
            isDirectory: false,
            parentIdentifier: workDir.itemIdentifier,
            contentLength: 42
        )

        let docID = docDir.id
        let workID = workDir.id
        let notesID = notesFile.id

        // 将 Documents 重命名为 Archive
        let updatedDoc = try registry.renameOrMove(
            identifier: docDir.itemIdentifier,
            newParentIdentifier: .rootContainer,
            newName: "Archive",
            newRemotePath: "Archive"
        )

        // 验证自身 UUID 不变，路径更新
        XCTAssertEqual(updatedDoc.id, docID)
        XCTAssertEqual(updatedDoc.remotePath, "Archive")
        XCTAssertEqual(updatedDoc.filename, "Archive")

        // 验证子目录 Work：UUID 绝对不变，路径自动同步迁移为 Archive/Work
        let resolvedWork = registry.resolve(identifier: workDir.itemIdentifier)
        XCTAssertNotNil(resolvedWork)
        XCTAssertEqual(resolvedWork?.id, workID)
        XCTAssertEqual(resolvedWork?.remotePath, "Archive/Work")

        // 验证子文件 notes.txt：UUID 绝对不变，路径自动同步迁移为 Archive/Work/notes.txt
        let resolvedNotes = registry.resolve(identifier: notesFile.itemIdentifier)
        XCTAssertNotNil(resolvedNotes)
        XCTAssertEqual(resolvedNotes?.id, notesID)
        XCTAssertEqual(resolvedNotes?.remotePath, "Archive/Work/notes.txt")

        // 验证旧路径在索引中已被清理
        XCTAssertNil(registry.resolve(remotePath: "Documents/Work/notes.txt"))
        // 验证新路径能准确解析到该文件
        XCTAssertEqual(registry.resolve(remotePath: "Archive/Work/notes.txt")?.id, notesID)
    }

    // MARK: - 4. Enumeration: Network Failure Safety & Remote Deletions

    func testEnumerationNetworkFailureDoesNotDeleteLocalItems() async throws {
        let domainID = UUID().uuidString
        let registry = try ExternalStorageItemRegistry(domainID: domainID, baseStorageURL: tempDirectory)

        let fileA = try registry.registerOrUpdate(
            remotePath: "fileA.txt",
            name: "fileA.txt",
            isDirectory: false,
            parentIdentifier: .rootContainer
        )
        let fileB = try registry.registerOrUpdate(
            remotePath: "fileB.txt",
            name: "fileB.txt",
            isDirectory: false,
            parentIdentifier: .rootContainer
        )

        let mockClient = MockExternalStorageClient()
        mockClient.shouldFailListWithError = WebDAVError.server(statusCode: 503, message: "Service Unavailable")

        let enumerator = FileProviderEnumerator(
            containerItemIdentifier: .rootContainer,
            registry: registry,
            client: mockClient
        )

        let observer = MockChangeObserver()
        let anchor = registry.currentAnchor()

        enumerator.enumerateChanges(for: observer, from: anchor)

        try await Task.sleep(nanoseconds: 100_000_000)

        // 核心验收验证：网络失败必须报错退出，绝不进入比对，本地记录完好无损
        XCTAssertNotNil(observer.finishedError)
        XCTAssertTrue(observer.deletedIdentifiers.isEmpty, "网络失败时绝不能删除本地项目")
        XCTAssertNotNil(registry.resolve(identifier: fileA.itemIdentifier))
        XCTAssertNotNil(registry.resolve(identifier: fileB.itemIdentifier))
    }

    func testEnumerationRemoteDeletionsDetectedWhenNetworkSucceeds() async throws {
        let domainID = UUID().uuidString
        let registry = try ExternalStorageItemRegistry(domainID: domainID, baseStorageURL: tempDirectory)

        let fileA = try registry.registerOrUpdate(
            remotePath: "fileA.txt",
            name: "fileA.txt",
            isDirectory: false,
            parentIdentifier: .rootContainer
        )
        let fileB = try registry.registerOrUpdate(
            remotePath: "fileB.txt",
            name: "fileB.txt",
            isDirectory: false,
            parentIdentifier: .rootContainer
        )

        let mockClient = MockExternalStorageClient()
        mockClient.itemsToList = [
            WebDAVItem(path: "fileA.txt", name: "fileA.txt", kind: .file, contentLength: 100, modifiedAt: Date())
        ]

        let enumerator = FileProviderEnumerator(
            containerItemIdentifier: .rootContainer,
            registry: registry,
            client: mockClient
        )

        let observer = MockChangeObserver()
        let anchor = registry.currentAnchor()

        enumerator.enumerateChanges(for: observer, from: anchor)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNil(observer.finishedError)
        XCTAssertEqual(observer.deletedIdentifiers.count, 1)
        XCTAssertEqual(observer.deletedIdentifiers.first, fileB.itemIdentifier)
        XCTAssertNil(registry.resolve(identifier: fileB.itemIdentifier), "被远端删除的项已从注册表安全清理")
        XCTAssertNotNil(registry.resolve(identifier: fileA.itemIdentifier), "保留的项仍在注册表中")
    }

    // MARK: - 5. Version Conflict Check

    func testVersionConflictDetection() throws {
        let version1 = ItemVersionRecord.make(etag: "\"v1\"", modifiedAt: Date(timeIntervalSince1970: 100), contentLength: 50)
        let version2 = ItemVersionRecord.make(etag: "\"v2\"", modifiedAt: Date(timeIntervalSince1970: 200), contentLength: 80)

        let fpVersion1 = version1.fileProviderItemVersion
        let fpVersion2 = version2.fileProviderItemVersion

        XCTAssertNotEqual(fpVersion1.contentVersion, fpVersion2.contentVersion, "不同 etag/mtime 生成的版本 contentVersion 必须不同")
    }

    // MARK: - 6. Root Capabilities & Forbidden Operations

    func testRootCapabilitiesAndForbiddenOperations() throws {
        let domainID = UUID().uuidString
        let registry = try ExternalStorageItemRegistry(domainID: domainID, baseStorageURL: tempDirectory)

        let rootRecord = registry.resolve(identifier: .rootContainer)!
        let rootItem = FileProviderItem(record: rootRecord, domainDisplayName: "测试存储")

        let caps = rootItem.capabilities
        XCTAssertTrue(caps.contains(.allowsAddingSubItems))
        XCTAssertTrue(caps.contains(.allowsContentEnumerating))
        XCTAssertTrue(caps.contains(.allowsReading))

        // 核心验收验证：根目录绝对禁止删除、重命名、重定向
        XCTAssertFalse(caps.contains(.allowsDeleting))
        XCTAssertFalse(caps.contains(.allowsRenaming))
        XCTAssertFalse(caps.contains(.allowsReparenting))
        XCTAssertFalse(caps.contains(.allowsWriting))

        // 验证对根目录进行重命名、移动或删除操作被严格抛错拒绝
        XCTAssertThrowsError(try registry.renameOrMove(
            identifier: .rootContainer,
            newParentIdentifier: .rootContainer,
            newName: "NewRoot",
            newRemotePath: "NewRoot"
        )) { error in
            guard case ExternalStorageError.rootOperationForbidden = error else {
                XCTFail("根目录重命名应抛出 rootOperationForbidden")
                return
            }
        }

        XCTAssertThrowsError(try registry.delete(identifier: .rootContainer)) { error in
            guard case ExternalStorageError.rootOperationForbidden = error else {
                XCTFail("根目录删除应抛出 rootOperationForbidden")
                return
            }
        }
    }

    // MARK: - 7. Shared Store & Keychain Lifecycle

    func testSharedStorePublishAndKeychainCleanup() throws {
        let mockKeychain = MockExternalStorageKeychain()
        let store = ExternalStorageSharedStore(
            appGroupIdentifier: "group.com.easysearch.xp9477",
            fileManager: .default,
            keychain: mockKeychain,
            customRootURL: tempDirectory
        )

        let loc1 = WebDAVLocation(
            id: UUID(),
            name: "Server 1",
            baseURL: URL(string: "https://dav1.example.com")!,
            username: "user1",
            password: "secretPassword1"
        )
        let loc2 = WebDAVLocation(
            id: UUID(),
            name: "Server 2",
            baseURL: URL(string: "https://dav2.example.com")!,
            username: "user2",
            password: "secretPassword2"
        )

        try store.publish(locations: [loc1, loc2])

        // 验证密码已镜像到 Keychain
        XCTAssertEqual(try store.configuration(locationID: loc1.id).password, "secretPassword1")
        XCTAssertEqual(try store.configuration(locationID: loc2.id).password, "secretPassword2")

        XCTAssertEqual(mockKeychain.storedPasswordCount(), 2)

        // 下一次 publish 移除了 loc2
        try store.publish(locations: [loc1])

        // 验证 loc1 密码依然在，而 loc2 的密码已被清理
        XCTAssertEqual(try store.configuration(locationID: loc1.id).password, "secretPassword1")
        XCTAssertThrowsError(try store.configuration(locationID: loc2.id).password, "已删除位置的密码应被安全清理")
        XCTAssertEqual(mockKeychain.storedPasswordCount(), 1)
    }

    // MARK: - 8. Dual Registry Instances Concurrency (No Overwrite / Drop)

    func testDualRegistryInstancesDoNotDropUpdates() throws {
        let domainID = UUID().uuidString
        let regA = try ExternalStorageItemRegistry(domainID: domainID, baseStorageURL: tempDirectory)
        let regB = try ExternalStorageItemRegistry(domainID: domainID, baseStorageURL: tempDirectory)

        // 实例 A 写入 item1
        let item1 = try regA.registerOrUpdate(
            remotePath: "file1.txt",
            name: "file1.txt",
            isDirectory: false,
            parentIdentifier: .rootContainer
        )

        // 实例 B 写入 item2
        let item2 = try regB.registerOrUpdate(
            remotePath: "file2.txt",
            name: "file2.txt",
            isDirectory: false,
            parentIdentifier: .rootContainer
        )

        // 验证实例 A 能读取到实例 B 写入的内容
        let aReads2 = regA.resolve(remotePath: "file2.txt")
        XCTAssertNotNil(aReads2, "实例 A 必须通过锁内 reload 读到实例 B 写入的数据")
        XCTAssertEqual(aReads2?.id, item2.id)

        // 验证实例 B 能读取到实例 A 写入的内容
        let bReads1 = regB.resolve(remotePath: "file1.txt")
        XCTAssertNotNil(bReads1, "实例 B 必须通过锁内 reload 读到实例 A 写入的数据")
        XCTAssertEqual(bReads1?.id, item1.id)
    }

    // MARK: - 9. Initial Anchor Incremental Sync Does Not Expire

    func testInitialAnchorIncrementalSyncDoesNotExpire() throws {
        let domainID = UUID().uuidString
        let registry = try ExternalStorageItemRegistry(domainID: domainID, baseStorageURL: tempDirectory)

        // 初始 anchor（sequence == 1）
        let initialAnchor = registry.currentAnchor()

        // 触发一次文件注册变动（sequence 递增至 2）
        let item = try registry.registerOrUpdate(
            remotePath: "new_file.txt",
            name: "new_file.txt",
            isDirectory: false,
            parentIdentifier: .rootContainer
        )

        // 请求从 initialAnchor 开始的变更
        let changes = registry.incrementalChanges(since: initialAnchor)
        XCTAssertNotNil(changes, "初始 anchor 在首次变更后绝不应被判定为过期")
        XCTAssertEqual(changes?.updated.count, 1)
        XCTAssertEqual(changes?.updated.first?.id, item.id)
    }

    // MARK: - 10. Filename with Spaces Preserved

    func testFilenameWithSpacesPreservedWithoutTrimming() throws {
        let filenameWithSpaces = " My Report (2026) .pdf "
        let remotePath = "Folder/\(filenameWithSpaces)"

        XCTAssertNoThrow(try ExternalStoragePathUtility.validatePathComponent(filenameWithSpaces))
        XCTAssertNoThrow(try ExternalStoragePathUtility.validatePath(remotePath))

        let domainID = UUID().uuidString
        let registry = try ExternalStorageItemRegistry(domainID: domainID, baseStorageURL: tempDirectory)

        let record = try registry.registerOrUpdate(
            remotePath: remotePath,
            name: filenameWithSpaces,
            isDirectory: false,
            parentIdentifier: .rootContainer
        )

        // 验证空格未被意外 trim
        XCTAssertEqual(record.filename, filenameWithSpaces, "文件名包含的首尾空格必须完整保留")
        XCTAssertEqual(record.remotePath, "Folder/\(filenameWithSpaces)")
    }

    // MARK: - 11. Publish Failure Cleans Staged Credentials and Preserves Previous

    func testPublishFailureCleansStagedCredentialsAndPreservesPrevious() throws {
        let mockKeychain = MockExternalStorageKeychain()
        let store = ExternalStorageSharedStore(
            appGroupIdentifier: "group.com.easysearch.xp9477",
            fileManager: .default,
            keychain: mockKeychain,
            customRootURL: tempDirectory
        )

        let initialLoc = WebDAVLocation(
            id: UUID(),
            name: "Initial NAS",
            baseURL: URL(string: "https://dav.example.com")!,
            username: "user1",
            password: "initialPassword"
        )
        try store.publish(locations: [initialLoc])
        XCTAssertEqual(try store.configuration(locationID: initialLoc.id).password, "initialPassword")
        XCTAssertEqual(mockKeychain.storedPasswordCount(), 1)

        let loc1 = WebDAVLocation(
            id: UUID(),
            name: "Server 1",
            baseURL: URL(string: "https://dav1.example.com")!,
            username: "user1",
            password: "validPassword1"
        )
        let loc2 = WebDAVLocation(
            id: UUID(),
            name: "Server 2",
            baseURL: URL(string: "https://dav2.example.com")!,
            username: "user2",
            password: "failPassword2"
        )

        mockKeychain.failOnPassword = "failPassword2"

        XCTAssertThrowsError(try store.publish(locations: [loc1, loc2]), "第二位置保存密码失败时 publish 必须抛错")

        // 验证本次为 loc1 暂存的 credential 已被清理，且上一批 initialLoc 的配置与密码完整保留
        XCTAssertEqual(try store.configuration(locationID: initialLoc.id).password, "initialPassword")
        XCTAssertEqual(mockKeychain.storedPasswordCount(), 1, "staged 凭据必须已清理，仅保留上一批有效密码")
    }

    // MARK: - 12. Registry Rename and Move Updates MetadataVersion While Preserving ContentVersion

    func testRegistryRenameAndMoveUpdatesMetadataVersionWhilePreservingContentVersion() throws {
        let domainID = UUID().uuidString
        let registry = try ExternalStorageItemRegistry(domainID: domainID, baseStorageURL: tempDirectory)

        let initialRecord = try registry.registerOrUpdate(
            remotePath: "documents/report.pdf",
            name: "report.pdf",
            isDirectory: false,
            parentIdentifier: .rootContainer,
            contentLength: 4096,
            modifiedAt: Date(timeIntervalSince1970: 1700000000),
            contentType: "application/pdf",
            etag: "\"etag-v1\""
        )

        let originalContentVersion = initialRecord.version.contentVersionString
        let originalMetadataVersion = initialRecord.version.metadataVersionString

        // 1. 重命名：同一目录下修改文件名
        let renamedRecord = try registry.renameOrMove(
            identifier: initialRecord.itemIdentifier,
            newParentIdentifier: .rootContainer,
            newName: "report_final.pdf",
            newRemotePath: "documents/report_final.pdf"
        )

        XCTAssertEqual(renamedRecord.version.contentVersionString, originalContentVersion, "重命名时文件数据未修改，contentVersion 必须保持不变")
        XCTAssertNotEqual(renamedRecord.version.metadataVersionString, originalMetadataVersion, "重命名改变了名称，metadataVersion 必须变化")

        // 2. 移动：变更父目录
        let targetFolderID = NSFileProviderItemIdentifier(UUID().uuidString)
        let movedRecord = try registry.renameOrMove(
            identifier: renamedRecord.itemIdentifier,
            newParentIdentifier: targetFolderID,
            newName: "report_final.pdf",
            newRemotePath: "archive/report_final.pdf"
        )

        XCTAssertEqual(movedRecord.version.contentVersionString, originalContentVersion, "跨目录移动时 contentVersion 必须保持不变")
        XCTAssertNotEqual(movedRecord.version.metadataVersionString, renamedRecord.version.metadataVersionString, "跨目录移动时 metadataVersion 必须变化")
    }

    // MARK: - iOS-compatible conflict errors

    func testVersionConflictMapsToIOSCompatibleErrorAndPreservesVersions() {
        let conflict = ExternalStorageError.versionConflict(expected: "v1", actual: "v2")
        let direct = conflict.toNSFileProviderError() as NSError
        let mapped = ExternalStorageErrorMapper.mapToNSFileProviderError(conflict) as NSError

        for error in [direct, mapped] {
            XCTAssertEqual(error.domain, NSFileProviderErrorDomain)
            XCTAssertEqual(error.code, NSFileProviderError.Code.cannotSynchronize.rawValue)
            XCTAssertEqual(error.localizedDescription, conflict.localizedDescription)
            XCTAssertTrue(error.localizedDescription.contains("v1"))
            XCTAssertTrue(error.localizedDescription.contains("v2"))
        }
    }

    func testWebDAVEditConflictRemainsAConflictRatherThanNetworkFailure() {
        let conflict = WebDAVError.editConflict
        let error = ExternalStorageErrorMapper.mapToNSFileProviderError(conflict) as NSError

        XCTAssertEqual(error.domain, NSFileProviderErrorDomain)
        XCTAssertEqual(error.code, NSFileProviderError.Code.cannotSynchronize.rawValue)
        XCTAssertNotEqual(error.code, NSFileProviderError.Code.serverUnreachable.rawValue)
        XCTAssertEqual(error.localizedDescription, conflict.localizedDescription)
    }

    func testWebDAVPreconditionFailureRemainsRejectedWithHTTPContext() {
        let conflict = WebDAVError.server(statusCode: 412, message: "Precondition Failed")
        let error = ExternalStorageErrorMapper.mapToNSFileProviderError(conflict) as NSError

        XCTAssertEqual(error.domain, NSFileProviderErrorDomain)
        XCTAssertEqual(error.code, NSFileProviderError.Code.cannotSynchronize.rawValue)
        XCTAssertNotEqual(error.code, NSFileProviderError.Code.serverUnreachable.rawValue)
        XCTAssertTrue(error.localizedDescription.contains("412"))
    }

    func testInitialPagesEnumerateDirectoryAndWorkingSet() async throws {
        let initialPages = [
            NSFileProviderPage(NSFileProviderPage.initialPageSortedByName as Data),
            NSFileProviderPage(NSFileProviderPage.initialPageSortedByDate as Data)
        ]
        let containers: [NSFileProviderItemIdentifier] = [.rootContainer, .workingSet]

        for container in containers {
            for page in initialPages {
                let registry = try ExternalStorageItemRegistry(
                    domainID: UUID().uuidString, baseStorageURL: tempDirectory
                )
                let record = try registry.registerOrUpdate(
                    remotePath: "report.txt", name: "report.txt", isDirectory: false,
                    parentIdentifier: .rootContainer
                )
                registry.markAccessed(identifier: record.itemIdentifier)
                let client = MockExternalStorageClient()
                client.itemsToList = [WebDAVItem(
                    path: "report.txt", name: "report.txt", kind: .file,
                    contentLength: nil, modifiedAt: nil
                )]
                let enumerator = FileProviderEnumerator(
                    containerItemIdentifier: container, registry: registry,
                    client: client, domainDisplayName: "Test"
                )
                let completed = expectation(description: "Initial page enumerated")
                let observer = MockEnumerationObserver(completion: completed)

                enumerator.enumerateItems(for: observer, startingAt: page)
                await fulfillment(of: [completed], timeout: 3)
                enumerator.invalidate()

                XCTAssertNil(observer.finishedError)
                XCTAssertNil(observer.nextPage)
                XCTAssertEqual(observer.items.map(\.filename), ["report.txt"])
            }
        }
    }

    func testSyncAnchorRoundtripPreservesUInt64Range() throws {
        let registry = try ExternalStorageItemRegistry(
            domainID: UUID().uuidString, baseStorageURL: tempDirectory
        )
        XCTAssertEqual(registry.parseAnchor(registry.currentAnchor()), UInt64(1))
        _ = try registry.registerOrUpdate(
            remotePath: "report.txt", name: "report.txt", isDirectory: false,
            parentIdentifier: .rootContainer
        )
        XCTAssertEqual(registry.parseAnchor(registry.currentAnchor()), UInt64(2))
        let maximumAnchor = NSFileProviderSyncAnchor(Data(String(UInt64.max).utf8))
        XCTAssertEqual(registry.parseAnchor(maximumAnchor), UInt64.max)
    }

}
