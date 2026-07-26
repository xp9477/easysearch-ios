import Foundation

/// 引擎使用频次统计,用于常用置顶与"最近使用"默认引擎。
final class SearchEngineUsageStore {
    static let countsKey = "search.engineUsage.counts.v1"
    static let lastUsedKey = "search.engineUsage.lastUsed.v1"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var lastUsedEngineName: String? {
        userDefaults.string(forKey: Self.lastUsedKey)
    }

    func recordUse(engineName: String) {
        var counts = loadCounts()
        counts[engineName, default: 0] += 1
        userDefaults.set(counts, forKey: Self.countsKey)
        userDefaults.set(engineName, forKey: Self.lastUsedKey)
    }

    func useCount(for engineName: String) -> Int {
        loadCounts()[engineName] ?? 0
    }

    /// 按使用频次排序(次数相同保持原顺序)。
    func sortedByUsage(_ engines: [SearchEngine]) -> [SearchEngine] {
        let counts = loadCounts()
        return engines.enumerated().sorted { lhs, rhs in
            let lhsCount = counts[lhs.element.name] ?? 0
            let rhsCount = counts[rhs.element.name] ?? 0
            if lhsCount != rhsCount { return lhsCount > rhsCount }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// 高频引擎(至少用过一次),用于"常用"横滑行。
    func frequentEngines(from engines: [SearchEngine], limit: Int = 6) -> [SearchEngine] {
        let counts = loadCounts()
        return engines
            .filter { (counts[$0.name] ?? 0) > 0 }
            .sorted { (counts[$0.name] ?? 0) > (counts[$1.name] ?? 0) }
            .prefix(limit)
            .map { $0 }
    }

    private func loadCounts() -> [String: Int] {
        userDefaults.dictionary(forKey: Self.countsKey) as? [String: Int] ?? [:]
    }
}
