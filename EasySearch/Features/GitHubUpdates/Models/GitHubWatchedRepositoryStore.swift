import Foundation

extension Notification.Name {
    static let gitHubWatchedRepositoriesDidChange = Notification.Name("gitHubWatchedRepositoriesDidChange")
}

protocol GitHubWatchedRepositoryStore {
    func loadRepositories() -> [GitHubWatchedRepository]
    func saveRepositories(_ repositories: [GitHubWatchedRepository])
}

struct GitHubWatchedRepositoryLocalStore: GitHubWatchedRepositoryStore {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadRepositories() -> [GitHubWatchedRepository] {
        guard let data = userDefaults.data(forKey: GitHubUpdatesStorage.watchedRepositoriesKey),
              let repositories = try? JSONDecoder().decode([GitHubWatchedRepository].self, from: data) else {
            return []
        }

        return repositories
    }

    func saveRepositories(_ repositories: [GitHubWatchedRepository]) {
        guard let data = try? JSONEncoder().encode(repositories) else { return }
        userDefaults.set(data, forKey: GitHubUpdatesStorage.watchedRepositoriesKey)
        NotificationCenter.default.post(name: .gitHubWatchedRepositoriesDidChange, object: nil)
    }
}
