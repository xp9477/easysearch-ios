import Foundation

extension Notification.Name {
    static let qingLongPanelDidChange = Notification.Name("qingLongPanelDidChange")
}

protocol QingLongPanelStore {
    func loadProfile() -> QingLongPanelProfile?
    func saveProfile(_ profile: QingLongPanelProfile, postsNotification: Bool)
    func deleteProfile()
}

struct QingLongPanelLocalStore: QingLongPanelStore {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadProfile() -> QingLongPanelProfile? {
        guard let data = userDefaults.data(forKey: QingLongStorage.panelProfileKey),
              let profile = try? JSONDecoder().decode(QingLongPanelProfile.self, from: data) else {
            return nil
        }

        return profile
    }

    func saveProfile(_ profile: QingLongPanelProfile, postsNotification: Bool = true) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        userDefaults.set(data, forKey: QingLongStorage.panelProfileKey)
        guard postsNotification else { return }
        NotificationCenter.default.post(name: .qingLongPanelDidChange, object: nil)
    }

    func deleteProfile() {
        userDefaults.removeObject(forKey: QingLongStorage.panelProfileKey)
        NotificationCenter.default.post(name: .qingLongPanelDidChange, object: nil)
    }
}
