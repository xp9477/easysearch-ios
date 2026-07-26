import Foundation

/// App 与 Widget 共享的 App Group 存储。
enum AppGroupStorage {
    static let suiteName = "group.com.easysearch.xp9477"

    static let shared: UserDefaults = UserDefaults(suiteName: suiteName) ?? .standard

    /// 把旧的 standard UserDefaults 数据一次性迁移到 App Group(带迁移标记)。
    static func migrateIfNeeded(keys: [String], migrationKey: String) {
        let target = shared
        guard target !== UserDefaults.standard else { return }
        guard !target.bool(forKey: migrationKey) else { return }

        let source = UserDefaults.standard
        for key in keys where target.object(forKey: key) == nil {
            if let value = source.object(forKey: key) {
                target.set(value, forKey: key)
            }
        }
        target.set(true, forKey: migrationKey)
    }
}
