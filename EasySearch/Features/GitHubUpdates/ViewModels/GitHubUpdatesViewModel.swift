import Foundation

enum GitHubUpdatesNoticeTone: Equatable {
    case neutral
    case success
    case caution
}

struct GitHubUpdatesNotice: Equatable {
    let tone: GitHubUpdatesNoticeTone
    let message: String
}

@MainActor
final class GitHubUpdatesViewModel: ObservableObject {
    @Published private(set) var repositories: [GitHubWatchedRepository] = []
    @Published var draftRepositoryAddress = ""
    @Published private(set) var isRefreshing = false
    @Published private(set) var isAddingRepository = false
    @Published private(set) var deletingRepositoryIDs: Set<String> = []
    @Published private(set) var notice: GitHubUpdatesNotice?

    private let store: any GitHubWatchedRepositoryStore
    private let notificationCenter: NotificationCenter
    private var repositoriesDidChangeObserver: NSObjectProtocol?

    init(
        store: any GitHubWatchedRepositoryStore = GitHubWatchedRepositoryLocalStore(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.store = store
        self.notificationCenter = notificationCenter
        repositoriesDidChangeObserver = notificationCenter.addObserver(
            forName: .gitHubWatchedRepositoriesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadFromStore()
            }
        }
        reloadFromStore()
    }

    deinit {
        if let repositoriesDidChangeObserver {
            notificationCenter.removeObserver(repositoriesDidChangeObserver)
        }
    }

    func prepare() async {
        reloadFromStore()
        await GitHubUpdatesBackgroundRefreshManager.scheduleNextRefresh()

        if repositories.isEmpty, notice == nil {
            setNotice(
                tone: .neutral,
                message: "添加公开仓库后，应用会在后台检查最新 push；打开 App 时也会补查一次。"
            )
        }
    }

    func addRepository() async {
        let rawValue = draftRepositoryAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawValue.isEmpty else {
            setNotice(tone: .caution, message: GitHubUpdatesError.emptyRepositoryAddress.localizedDescription)
            return
        }

        isAddingRepository = true
        defer { isAddingRepository = false }

        do {
            let repository = try await GitHubUpdatesService.shared.addRepository(from: rawValue)
            draftRepositoryAddress = ""
            repositories = await GitHubUpdatesService.shared.loadRepositories()
            setNotice(tone: .success, message: "已开始关注 \(repository.fullName)")
            await HiddenCloudSyncViewModel.shared.syncGitHubRepoWatchUpsertIfPossible(repository)
            await GitHubUpdatesBackgroundRefreshManager.scheduleNextRefresh()
        } catch {
            setNotice(tone: .caution, message: error.localizedDescription)
        }
    }

    func refreshAll() async {
        guard !repositories.isEmpty else {
            setNotice(tone: .neutral, message: "还没有添加 GitHub 仓库。")
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        let summary = await GitHubUpdatesService.shared.refreshRepositories(trigger: .manual, force: true)
        repositories = await GitHubUpdatesService.shared.loadRepositories()
        setNotice(tone: noticeTone(for: summary), message: summary.messageText)

        if summary.didPersistChanges, !repositories.isEmpty {
            await HiddenCloudSyncViewModel.shared.syncGitHubRepoWatchesIfPossible(repositories)
        }

        await GitHubUpdatesBackgroundRefreshManager.scheduleNextRefresh()
    }

    func deleteRepository(_ repository: GitHubWatchedRepository) async {
        let inserted = deletingRepositoryIDs.insert(repository.id).inserted
        guard inserted else { return }
        defer { deletingRepositoryIDs.remove(repository.id) }

        guard let removed = await GitHubUpdatesService.shared.deleteRepository(id: repository.id) else { return }
        repositories = await GitHubUpdatesService.shared.loadRepositories()
        setNotice(tone: .neutral, message: "已移除 \(removed.fullName)")
        await HiddenCloudSyncViewModel.shared.syncGitHubRepoWatchDeletionIfPossible(removed)
        await GitHubUpdatesBackgroundRefreshManager.scheduleNextRefresh()
    }

    var canAddRepository: Bool {
        !draftRepositoryAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isAddingRepository
            && !isRefreshing
    }

    var canRefreshRepositories: Bool {
        !repositories.isEmpty && !isRefreshing && !isAddingRepository && deletingRepositoryIDs.isEmpty
    }

    var hasRepositories: Bool {
        !repositories.isEmpty
    }

    var latestCheckedAt: Date? {
        repositories.compactMap(\.lastCheckedAt).max()
    }

    func isDeletingRepository(_ repository: GitHubWatchedRepository) -> Bool {
        deletingRepositoryIDs.contains(repository.id)
    }

    func canDeleteRepository(_ repository: GitHubWatchedRepository) -> Bool {
        !isRefreshing && !isAddingRepository && !deletingRepositoryIDs.contains(repository.id)
    }

    private func reloadFromStore() {
        let reloaded = store.loadRepositories().sorted(by: GitHubWatchedRepository.sort(lhs:rhs:))
        guard reloaded != repositories else { return }
        repositories = reloaded
    }

    private func setNotice(tone: GitHubUpdatesNoticeTone, message: String?) {
        guard let message, !message.isEmpty else {
            notice = nil
            return
        }

        notice = GitHubUpdatesNotice(tone: tone, message: message)
    }

    private func noticeTone(for summary: GitHubRefreshSummary) -> GitHubUpdatesNoticeTone {
        if summary.updatedRepositories.isEmpty {
            return summary.hasUnavailableResults && summary.checkedCount == 0 ? .caution : .neutral
        }

        return .success
    }
}
