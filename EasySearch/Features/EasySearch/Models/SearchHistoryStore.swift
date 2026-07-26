import Foundation

struct SearchHistoryEntry: Codable, Identifiable, Equatable {
    let query: String
    let engineName: String
    let searchedAt: Date

    var id: String { "\(query)|\(engineName)" }
}

/// 搜索历史。
final class SearchHistoryStore {
    static let storageKey = "search.history.v1"
    static let maxEntries = 20

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
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
