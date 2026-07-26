import Foundation

protocol ExpenseAssistantStore {
    func loadSnapshot() -> ExpenseAssistantSnapshot
    func saveSnapshot(_ snapshot: ExpenseAssistantSnapshot)
}

struct ExpenseAssistantLocalStore: ExpenseAssistantStore {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadSnapshot() -> ExpenseAssistantSnapshot {
        guard let data = userDefaults.data(forKey: ExpenseAssistantStorage.snapshotKey),
              let snapshot = try? JSONDecoder().decode(ExpenseAssistantSnapshot.self, from: data) else {
            return ExpenseAssistantSnapshot()
        }

        return snapshot
    }

    func saveSnapshot(_ snapshot: ExpenseAssistantSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        userDefaults.set(data, forKey: ExpenseAssistantStorage.snapshotKey)
        NotificationCenter.default.post(name: .expenseAssistantDataDidChange, object: nil)
    }
}
