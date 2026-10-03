import Combine
import FileProvider
import Foundation

@MainActor
final class ExternalStorageFilesCoordinator: ObservableObject {
    static let shared = ExternalStorageFilesCoordinator()

    @Published private(set) var lastError: String?
    @Published private(set) var statusMessage: String?
    @Published private(set) var syncedDomainCount: Int = 0

    var status: String? { statusMessage }

    private let sharedStore: ExternalStorageSharedStore
    private var ongoingSyncTask: Task<Void, Error>?
    private var pendingLocations: [WebDAVLocation]?

    init(sharedStore: ExternalStorageSharedStore = .shared) {
        self.sharedStore = sharedStore
    }

    func sync(locations: [WebDAVLocation]) async throws {
        pendingLocations = locations
        if let task = ongoingSyncTask {
            try await task.value
            return
        }
        let task = Task { @MainActor in
            defer { self.ongoingSyncTask = nil }
            while let latest = self.pendingLocations {
                self.pendingLocations = nil
                do {
                    try await self.performSync(locations: latest)
                } catch {
                    // A newer configuration may fix the error; always drain it.
                    if self.pendingLocations == nil { throw error }
                }
            }
        }
        ongoingSyncTask = task
        try await task.value
    }

    private func performSync(locations: [WebDAVLocation]) async throws {
        do {
            // 0. 根目录检测：若根目录未就绪或 AppGroup 不可用，立即失败且绝不向系统发布 domain
            _ = try sharedStore.rootDirectoryURL()

            // 1. 同步无密码元数据到 App Group，并将密码镜像至共享钥匙串（事务发布）
            try sharedStore.publish(locations: locations)

            // 2. 读取当前注册的所有 FileProvider domains
            let existingDomains = try await NSFileProviderManager.domains()
            let targetIDs = Set(locations.map { $0.id.uuidString })

            // 3. 删除本应用的陈旧 domain（只处理符合本应用 UUID 规则的 domain，绝不触碰第三方 provider）
            for domain in existingDomains {
                let domainID = domain.identifier.rawValue
                if UUID(uuidString: domainID) != nil && !targetIDs.contains(domainID) {
                    try await NSFileProviderManager.remove(domain)
                }
            }

            // 4. 为每个有效 location 注册或更新 domain（含 displayName 重命名更新）
            for location in locations {
                let domainID = NSFileProviderDomainIdentifier(location.id.uuidString)
                let targetDisplayName = location.name.isEmpty ? (location.baseURL.host ?? "外部存储") : location.name

                if let existing = existingDomains.first(where: { $0.identifier == domainID }) {
                    // 若显示名称变更，重新调用 add 触发系统更新 displayName
                    if existing.displayName != targetDisplayName {
                        let updatedDomain = NSFileProviderDomain(identifier: domainID, displayName: targetDisplayName)
                        try await NSFileProviderManager.add(updatedDomain)
                    }
                } else {
                    let newDomain = NSFileProviderDomain(identifier: domainID, displayName: targetDisplayName)
                    try await NSFileProviderManager.add(newDomain)
                }
            }

            self.syncedDomainCount = locations.count
            self.statusMessage = "外部存储同步完成（已同步 \(locations.count) 个存储位置）"
            self.lastError = nil
        } catch {
            self.lastError = error.localizedDescription
            self.statusMessage = nil
            throw error // 严格向上抛出错误，不吞错
        }
    }

    func notifyChanges(locationID: UUID, path: String) async throws {
        let domainID = NSFileProviderDomainIdentifier(locationID.uuidString)
        let domain = NSFileProviderDomain(identifier: domainID, displayName: "")
        guard let manager = NSFileProviderManager(for: domain) else {
            return
        }

        // 始终刷新工作集
        try await manager.signalEnumerator(for: .workingSet)

        let cleanPath = ExternalStoragePathUtility.normalize(path: path)
        if cleanPath.isEmpty {
            try await manager.signalEnumerator(for: .rootContainer)
        } else {
            // 通过 registry 解析对应 path 的具体 itemIdentifier，按需 signal 具体目录
            if let rootURL = try? sharedStore.rootDirectoryURL(),
               let registry = try? ExternalStorageItemRegistry(domainID: locationID.uuidString, baseStorageURL: rootURL),
               let item = registry.resolve(remotePath: cleanPath) {
                try await manager.signalEnumerator(for: item.itemIdentifier)
            } else {
                try await manager.signalEnumerator(for: .rootContainer)
            }
        }
    }
}
