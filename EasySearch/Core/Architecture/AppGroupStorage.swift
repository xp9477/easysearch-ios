import Foundation

/// 曾经为 Widget 共享数据而使用的 App Group UserDefaults。
///
/// Widget 已下线,数据回归 `UserDefaults.standard`;此处只保留一次性回退迁移,
/// 把装过 Widget 版本期间写入 App Group 的数据搬回 standard。
enum AppGroupStorage {
    static let suiteName = "group.com.easysearch.xp9477"

    static let rollbackMarkerKey = "appgroup.rollback.v1"

    /// Widget 时期落在 App Group 的数据 key。
    static let sharedKeys = [
        UTTrackerStorage.entriesKey,
        TrainingLogStorage.snapshotKey,
        ExpenseAssistantStorage.snapshotKey,
        SearchEngineUsageStore.countsKey,
        SearchEngineUsageStore.lastUsedKey
    ]

    /// 节假日缓存 key 前缀(按年份动态生成,迁移时按前缀匹配)。
    static let holidayCacheKeyPrefix = "ut_holiday_calendar_"

    /// 把 App Group 里的数据一次性覆盖写回 standard。只执行一次。
    static func rollbackToStandardIfNeeded(
        standard: UserDefaults = .standard,
        group: UserDefaults? = UserDefaults(suiteName: suiteName)
    ) {
        guard !standard.bool(forKey: rollbackMarkerKey) else { return }
        defer { standard.set(true, forKey: rollbackMarkerKey) }

        guard let group, group !== standard else { return }

        for key in sharedKeys {
            if let value = group.object(forKey: key) {
                standard.set(value, forKey: key)
            }
        }

        for (key, value) in group.dictionaryRepresentation()
        where key.hasPrefix(holidayCacheKeyPrefix) {
            standard.set(value, forKey: key)
        }
    }
}
