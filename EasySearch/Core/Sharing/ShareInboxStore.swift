import Foundation
import Combine

struct SharedInboxItem: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let batchID: UUID?
    let displayName: String
    let relativePath: String
    let contentType: String?
    let createdAt: Date

    var resolvedBatchID: UUID { batchID ?? id }

    var localURL: URL {
        let itemDirectory = SharedInboxStore.containerURL
            .appendingPathComponent(SharedInboxStore.inboxDirectoryName, isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
        let candidate = itemDirectory.appendingPathComponent(relativePath).standardizedFileURL
        guard candidate.path.hasPrefix(itemDirectory.standardizedFileURL.path + "/") else {
            return itemDirectory.appendingPathComponent("invalid-share-item")
        }
        return candidate
    }
}

struct SharedInboxBatch: Hashable, Identifiable, Sendable {
    let id: UUID
    let items: [SharedInboxItem]
}

enum SharedInboxStore {
    static let appGroupID = "group.com.easysearch.xp9477"
    static let inboxDirectoryName = "ShareInbox"
    private static let manifestName = "manifest.json"
    private static let batchMarkerPrefix = ".batch-"

    static var containerURL: URL {
        if let sharedURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) {
            return sharedURL
        }

        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return applicationSupport.appendingPathComponent("EasySearch", isDirectory: true)
    }

    static var inboxURL: URL {
        let url = containerURL.appendingPathComponent(inboxDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func pendingItems() -> [SharedInboxItem] {
        let fileManager = FileManager.default
        cleanupStagingDirectories(fileManager: fileManager)
        guard let directories = try? fileManager.contentsOfDirectory(
            at: inboxURL,
            includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedItems: [SharedInboxItem] = directories
            .filter { directory in
                (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            .compactMap { directory in
                let manifestURL = directory.appendingPathComponent(manifestName)
                guard let data = try? Data(contentsOf: manifestURL),
                      let item = try? decoder.decode(SharedInboxItem.self, from: data),
                      directory.lastPathComponent == item.id.uuidString else {
                    return nil
                }
                return item
            }
        cleanupIncompleteBatches(decodedItems, fileManager: fileManager)
        return decodedItems
            .filter(isBatchCommitted)
            .sorted { $0.createdAt < $1.createdAt }
    }

    static func remove(_ item: SharedInboxItem) {
        let directory = inboxURL.appendingPathComponent(item.id.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
    }

    static func removeAll(_ items: [SharedInboxItem]) {
        items.forEach(remove)
        Set(items.compactMap(\.batchID)).forEach { batchID in
            try? FileManager.default.removeItem(at: batchMarkerURL(for: batchID))
        }
    }

    static func importExternalItem(at sourceURL: URL, contentType: String? = nil) throws -> SharedInboxItem {
        let fileManager = FileManager.default
        let id = UUID()
        let stagingDirectory = inboxURL.appendingPathComponent(".staging-\(id.uuidString)", isDirectory: true)
        let finalDirectory = inboxURL.appendingPathComponent(id.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)

        do {
            let fileName = sanitizedFileName(sourceURL.lastPathComponent)
            let destination = stagingDirectory.appendingPathComponent(fileName)
            let didStartAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess { sourceURL.stopAccessingSecurityScopedResource() }
            }
            try fileManager.copyItem(at: sourceURL, to: destination)

            let item = SharedInboxItem(
                id: id,
                batchID: id,
                displayName: fileName,
                relativePath: fileName,
                contentType: contentType,
                createdAt: Date()
            )
            try writeManifest(item, in: stagingDirectory)
            try fileManager.moveItem(at: stagingDirectory, to: finalDirectory)
            try Data().write(to: batchMarkerURL(for: id), options: .atomic)
            return item
        } catch {
            try? fileManager.removeItem(at: stagingDirectory)
            try? fileManager.removeItem(at: finalDirectory)
            try? fileManager.removeItem(at: batchMarkerURL(for: id))
            throw error
        }
    }

    static func writeManifest(_ item: SharedInboxItem, in directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(item)
        try data.write(to: directory.appendingPathComponent(manifestName), options: .atomic)
    }

    private static func sanitizedFileName(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:\0")
        let cleaned = value.components(separatedBy: forbidden).joined(separator: "_")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != ".", trimmed != ".." else { return "分享文件" }
        return trimmed
    }

    private static func cleanupStagingDirectories(fileManager: FileManager) {
        guard let directories = try? fileManager.contentsOfDirectory(
            at: inboxURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsSubdirectoryDescendants]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for directory in directories where directory.lastPathComponent.hasPrefix(".staging-") {
            let modifiedAt = try? directory.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if (modifiedAt ?? .distantPast) < cutoff {
                try? fileManager.removeItem(at: directory)
            }
        }
    }

    private static func isBatchCommitted(_ item: SharedInboxItem) -> Bool {
        guard let batchID = item.batchID else { return true }
        return FileManager.default.fileExists(atPath: batchMarkerURL(for: batchID).path)
    }

    private static func batchMarkerURL(for batchID: UUID) -> URL {
        inboxURL.appendingPathComponent("\(batchMarkerPrefix)\(batchID.uuidString).complete")
    }

    private static func cleanupIncompleteBatches(
        _ items: [SharedInboxItem],
        fileManager: FileManager
    ) {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        let groupedItems = Dictionary(grouping: items.compactMap { item -> SharedInboxItem? in
            guard item.batchID != nil else { return nil }
            return item
        }, by: \.resolvedBatchID)

        for (batchID, batchItems) in groupedItems {
            guard !fileManager.fileExists(atPath: batchMarkerURL(for: batchID).path),
                  (batchItems.map(\.createdAt).max() ?? .distantPast) < cutoff else {
                continue
            }
            batchItems.forEach(remove)
        }
    }
}

@MainActor
final class ShareInboxCoordinator: ObservableObject {
    @Published var presentedBatch: SharedInboxBatch?

    func refreshIfNeeded() {
        guard presentedBatch == nil else { return }
        let allItems = SharedInboxStore.pendingItems()
        guard let newestItem = allItems.max(by: { $0.createdAt < $1.createdAt }) else {
            return
        }
        let items = allItems.filter { $0.resolvedBatchID == newestItem.resolvedBatchID }
        guard !items.isEmpty else { return }
        presentedBatch = SharedInboxBatch(id: newestItem.resolvedBatchID, items: items)
    }

    func handleIncomingURL(_ url: URL) {
        if url.isFileURL {
            do {
                _ = try SharedInboxStore.importExternalItem(at: url)
            } catch {
                return
            }
        } else {
            guard url.scheme?.lowercased() == "easysearch" else { return }
        }
        refreshIfNeeded()
    }

    func consume(_ batch: SharedInboxBatch) {
        SharedInboxStore.removeAll(batch.items)
        if presentedBatch?.id == batch.id {
            presentedBatch = nil
        }
    }
}
