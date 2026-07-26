import Foundation

struct SearchHistoryEntry: Codable, Identifiable, Equatable {
    let query: String
    let engineName: String
    let searchedAt: Date

    var id: String { "\(query)|\(engineName)" }
}

/// 搜索历史(App Group 存储,供主 App 与 Widget 共享)。
final class SearchHistoryStore {
    static let appGroupID = "group.com.easysearch.xp9477"
    private static let storageKey = "search.history.v1"
    private static let migrationKey = "search.history.migrated"
    static let maxEntries = 20

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults? = nil) {
        self.userDefaults = userDefaults
            ?? UserDefaults(suiteName: Self.appGroupID)
            ?? .standard
    }

    func load() -> [SearchHistoryEntry] {
        guard let data = userDefaults.data(forKey: Self.storageKey),
              let entries = try? JSONDecoder().decode([SearchHistoryEntry].self, from: data) else {
            return []
        }
        return entries
    }

    func record(query: String, engineName: String, at date: Date = Date()) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var entries = load()
        entries.removeAll { $0.query == trimmed }
        entries.insert(SearchHistoryEntry(query: trimmed, engineName: engineName, searchedAt: date), at: 0)
        if entries.count > Self.maxEntries {
            entries = Array(entries.prefix(Self.maxEntries))
        }
        save(entries)
    }

    func remove(query: String) {
        var entries = load()
        entries.removeAll { $0.query == query }
        save(entries)
    }

    func clear() {
        userDefaults.removeObject(forKey: Self.storageKey)
    }

    private func save(_ entries: [SearchHistoryEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        userDefaults.set(data, forKey: Self.storageKey)
    }
}
