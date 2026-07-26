import Foundation
import WidgetKit

protocol TrainingLogStore {
    func loadSnapshot() -> TrainingLogSnapshot
    func saveSnapshot(_ snapshot: TrainingLogSnapshot)
}

struct TrainingLogLocalStore: TrainingLogStore {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults? = nil) {
        if let userDefaults {
            self.userDefaults = userDefaults
        } else {
            AppGroupStorage.migrateIfNeeded(
                keys: [TrainingLogStorage.snapshotKey],
                migrationKey: "traininglog.appgroup.migrated"
            )
            self.userDefaults = AppGroupStorage.shared
        }
    }

    func loadSnapshot() -> TrainingLogSnapshot {
        guard let data = userDefaults.data(forKey: TrainingLogStorage.snapshotKey),
              let snapshot = try? JSONDecoder().decode(TrainingLogSnapshot.self, from: data) else {
            return TrainingLogSnapshot()
        }
        return snapshot
    }

    func saveSnapshot(_ snapshot: TrainingLogSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        userDefaults.set(data, forKey: TrainingLogStorage.snapshotKey)
        NotificationCenter.default.post(name: .trainingLogDidChange, object: nil)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
