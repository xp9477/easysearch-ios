import Foundation
import WidgetKit

extension Notification.Name {
    static let utTrackerEntriesDidChange = Notification.Name("utTrackerEntriesDidChange")
}

protocol UTTrackerEntryStore {
    func loadEntries() -> [UTEntry]
    func saveEntries(_ entries: [UTEntry])
}

struct UTTrackerLocalStore: UTTrackerEntryStore {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults? = nil) {
        if let userDefaults {
            self.userDefaults = userDefaults
        } else {
            AppGroupStorage.migrateIfNeeded(
                keys: [UTTrackerStorage.entriesKey],
                migrationKey: "uttracker.appgroup.migrated"
            )
            self.userDefaults = AppGroupStorage.shared
        }
    }

    func loadEntries() -> [UTEntry] {
        guard let data = userDefaults.data(forKey: UTTrackerStorage.entriesKey),
              let storedEntries = try? JSONDecoder().decode([UTEntry].self, from: data) else {
            return []
        }

        return storedEntries
    }

    func saveEntries(_ entries: [UTEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        userDefaults.set(data, forKey: UTTrackerStorage.entriesKey)
        NotificationCenter.default.post(name: .utTrackerEntriesDidChange, object: nil)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
