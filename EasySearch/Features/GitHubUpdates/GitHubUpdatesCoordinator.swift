import BackgroundTasks
import Foundation
import UserNotifications

enum GitHubRefreshTrigger {
    case manual
    case foreground
    case background

    var shouldDeliverNotifications: Bool {
        self == .background
    }
}

struct GitHubRefreshSummary {
    let checkedCount: Int
    let updatedRepositories: [GitHubWatchedRepository]
    let hasUnavailableResults: Bool
    let skipped: Bool
    let didPersistChanges: Bool

    var messageText: String {
        if skipped {
            return "刚做过自动检查，稍后会再刷新。"
        }

        if checkedCount == 0 && !hasUnavailableResults {
            return "还没有添加 GitHub 仓库。"
        }

        if checkedCount == 0 && hasUnavailableResults {
            return "这次刷新没有拿到可用结果，稍后再试。"
        }

        var parts: [String] = []

        if checkedCount > 0 {
            parts.append("已检查 \(checkedCount) 个仓库")
        }

        if !updatedRepositories.isEmpty {
            parts.append("发现 \(updatedRepositories.count) 个更新")
        }

        if hasUnavailableResults {
            parts.append("部分仓库稍后再试")
        }

        return parts.isEmpty ? "这次刷新没有拿到可用结果，稍后再试。" : parts.joined(separator: "，")
    }
}

enum GitHubUpdatesError: LocalizedError {
    case emptyRepositoryAddress
    case invalidRepositoryAddress
    case unsupportedHost
    case invalidRepositoryPath
    case duplicateRepository(String)
    case repositoryNotFound(String)
    case rateLimited
    case serverError(String)
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .emptyRepositoryAddress:
            return "请先填写 GitHub 仓库地址。"
        case .invalidRepositoryAddress:
            return "仓库地址格式不正确。"
        case .unsupportedHost:
            return "当前只支持 github.com 仓库地址。"
        case .invalidRepositoryPath:
            return "请使用 owner/repo 形式的仓库地址。"
        case let .duplicateRepository(fullName):
            return "\(fullName) 已经在提醒列表里。"
        case let .repositoryNotFound(fullName):
            return "找不到仓库 \(fullName)，或者它不是公开仓库。"
        case .rateLimited:
            return "GitHub 接口请求过于频繁，请稍后再试。"
        case let .serverError(message):
            return message
        case .unexpectedResponse:
            return "GitHub 返回了无法识别的结果。"
        }
    }
}

struct GitHubRepositorySnapshot: Hashable {
    let owner: String
    let name: String
    let fullName: String
    let normalizedID: String
    let htmlURL: URL
    let repositoryDescription: String
    let defaultBranch: String
    let isArchived: Bool
    let isDisabled: Bool
    let pushedAt: Date?
}

private struct GitHubRepositoryTarget {
    let owner: String
    let name: String

    var normalizedID: String {
        "\(owner.lowercased())/\(name.lowercased())"
    }

    static func parse(_ rawValue: String) throws -> GitHubRepositoryTarget {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GitHubUpdatesError.emptyRepositoryAddress
        }

        if trimmed.lowercased().hasPrefix("git@github.com:") {
            let path = String(trimmed.dropFirst("git@github.com:".count))
            return try parsePath(path)
        }

        if trimmed.contains("://") {
            guard let url = URL(string: trimmed),
                  let host = url.host?.lowercased() else {
                throw GitHubUpdatesError.invalidRepositoryAddress
            }

            guard host == "github.com" || host == "www.github.com" else {
                throw GitHubUpdatesError.unsupportedHost
            }

            return try parsePath(url.path)
        }

        return try parsePath(trimmed)
    }

    private static func parsePath(_ path: String) throws -> GitHubRepositoryTarget {
        let segments = path
            .split(separator: "/")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard segments.count >= 2 else {
            throw GitHubUpdatesError.invalidRepositoryPath
        }

        let owner = segments[0].removingPercentEncoding ?? segments[0]
        var name = segments[1].removingPercentEncoding ?? segments[1]

        if name.lowercased().hasSuffix(".git") {
            name.removeLast(4)
        }

        guard !owner.isEmpty, !name.isEmpty else {
            throw GitHubUpdatesError.invalidRepositoryPath
        }

        return GitHubRepositoryTarget(owner: owner, name: name)
    }
}

private struct GitHubAPIRepositoryResponse: Decodable {
    struct Owner: Decodable {
        let login: String
    }

    let name: String
    let full_name: String
    let html_url: String
    let description: String?
    let default_branch: String
    let archived: Bool
    let disabled: Bool
    let pushed_at: Date?
    let owner: Owner

    func asSnapshot() throws -> GitHubRepositorySnapshot {
        guard let htmlURL = URL(string: html_url) else {
            throw GitHubUpdatesError.unexpectedResponse
        }

        return GitHubRepositorySnapshot(
            owner: owner.login,
            name: name,
            fullName: full_name,
            normalizedID: "\(owner.login.lowercased())/\(name.lowercased())",
            htmlURL: htmlURL,
            repositoryDescription: description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            defaultBranch: default_branch,
            isArchived: archived,
            isDisabled: disabled,
            pushedAt: pushed_at
        )
    }
}

private struct GitHubAPIErrorResponse: Decodable {
    let message: String?
}

private extension CharacterSet {
    static let gitHubPathAllowed: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "/")
        return set
    }()
}

actor GitHubUpdatesService {
    static let shared = GitHubUpdatesService()

    private let store: any GitHubWatchedRepositoryStore
    private let userDefaults: UserDefaults
    private let urlSession: URLSession
    private let automaticRefreshInterval: TimeInterval = 30 * 60

    init(
        store: any GitHubWatchedRepositoryStore = GitHubWatchedRepositoryLocalStore(),
        userDefaults: UserDefaults = .standard,
        urlSession: URLSession? = nil
    ) {
        self.store = store
        self.userDefaults = userDefaults

        if let urlSession {
            self.urlSession = urlSession
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.urlCache = nil
            self.urlSession = URLSession(configuration: configuration)
        }
    }

    func loadRepositories() -> [GitHubWatchedRepository] {
        sortedRepositories(store.loadRepositories())
    }

    func hasRepositories() -> Bool {
        !store.loadRepositories().isEmpty
    }

    func addRepository(from rawValue: String) async throws -> GitHubWatchedRepository {
        let target = try GitHubRepositoryTarget.parse(rawValue)
        var repositories = store.loadRepositories()

        if repositories.contains(where: { $0.id == target.normalizedID }) {
            throw GitHubUpdatesError.duplicateRepository("\(target.owner)/\(target.name)")
        }

        let snapshot = try await fetchRepository(owner: target.owner, name: target.name)
        let now = Date()

        let repository = GitHubWatchedRepository(
            id: snapshot.normalizedID,
            owner: snapshot.owner,
            name: snapshot.name,
            fullName: snapshot.fullName,
            htmlURL: snapshot.htmlURL,
            repositoryDescription: snapshot.repositoryDescription,
            defaultBranch: snapshot.defaultBranch,
            isArchived: snapshot.isArchived,
            isDisabled: snapshot.isDisabled,
            lastKnownPushedAt: snapshot.pushedAt,
            lastCheckedAt: now,
            lastNotifiedPushedAt: nil,
            createdAt: now,
            updatedAt: now
        )

        repositories.append(repository)
        saveRepositories(repositories, updateAutoRefreshAt: now)
        return repository
    }

    func deleteRepository(id: String) -> GitHubWatchedRepository? {
        var repositories = store.loadRepositories()
        guard let index = repositories.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        let removed = repositories.remove(at: index)
        saveRepositories(repositories)
        return removed
    }

    func refreshRepositories(trigger: GitHubRefreshTrigger, force: Bool = false) async -> GitHubRefreshSummary {
        let now = Date()
        var repositories = store.loadRepositories()

        guard !repositories.isEmpty else {
            return GitHubRefreshSummary(
                checkedCount: 0,
                updatedRepositories: [],
                hasUnavailableResults: false,
                skipped: false,
                didPersistChanges: false
            )
        }

        if trigger == .foreground, !force, shouldSkipAutomaticRefresh(now: now) {
            return GitHubRefreshSummary(
                checkedCount: 0,
                updatedRepositories: [],
                hasUnavailableResults: false,
                skipped: true,
                didPersistChanges: false
            )
        }

        var checkedCount = 0
        var hasUnavailableResults = false
        var updatedRepositories: [GitHubWatchedRepository] = []
        var didPersistChanges = false

        for index in repositories.indices {
            let current = repositories[index]

            do {
                let snapshot = try await fetchRepository(owner: current.owner, name: current.name)
                let hasNewPush: Bool

                if let newPushedAt = snapshot.pushedAt, let previousPushedAt = current.lastKnownPushedAt {
                    hasNewPush = newPushedAt > previousPushedAt
                } else {
                    hasNewPush = false
                }

                let notifiedAt = trigger.shouldDeliverNotifications && hasNewPush
                    ? snapshot.pushedAt
                    : current.lastNotifiedPushedAt

                let refreshed = current.applying(snapshot: snapshot, checkedAt: now, notifiedAt: notifiedAt)
                repositories[index] = refreshed
                checkedCount += 1

                if refreshed != current {
                    didPersistChanges = true
                }

                if trigger.shouldDeliverNotifications && hasNewPush {
                    updatedRepositories.append(refreshed)
                }
            } catch {
                repositories[index] = current.markingChecked(at: now)
                hasUnavailableResults = true
                didPersistChanges = true
            }
        }

        if didPersistChanges || checkedCount > 0 {
            saveRepositories(repositories, updateAutoRefreshAt: now)
        }

        if trigger.shouldDeliverNotifications && !updatedRepositories.isEmpty {
            await GitHubUpdatesNotificationManager.shared.notifyAboutUpdates(updatedRepositories)
        }

        return GitHubRefreshSummary(
            checkedCount: checkedCount,
            updatedRepositories: updatedRepositories,
            hasUnavailableResults: hasUnavailableResults,
            skipped: false,
            didPersistChanges: didPersistChanges
        )
    }

    private func shouldSkipAutomaticRefresh(now: Date) -> Bool {
        guard let lastRefresh = userDefaults.object(forKey: GitHubUpdatesStorage.lastAutoRefreshAtKey) as? Date else {
            return false
        }

        return now.timeIntervalSince(lastRefresh) < automaticRefreshInterval
    }

    private func saveRepositories(_ repositories: [GitHubWatchedRepository], updateAutoRefreshAt: Date? = nil) {
        store.saveRepositories(sortedRepositories(repositories))

        if let updateAutoRefreshAt {
            userDefaults.set(updateAutoRefreshAt, forKey: GitHubUpdatesStorage.lastAutoRefreshAtKey)
        }
    }

    private func sortedRepositories(_ repositories: [GitHubWatchedRepository]) -> [GitHubWatchedRepository] {
        repositories.sorted(by: GitHubWatchedRepository.sort(lhs:rhs:))
    }

    private func fetchRepository(owner: String, name: String) async throws -> GitHubRepositorySnapshot {
        var request = URLRequest(url: try makeRepositoryURL(owner: owner, name: name))
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("EasySearch-iOS", forHTTPHeaderField: "User-Agent")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw GitHubUpdatesError.serverError("GitHub 请求失败：\(error.localizedDescription)")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubUpdatesError.unexpectedResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(GitHubAPIRepositoryResponse.self, from: data).asSnapshot()

        case 404:
            throw GitHubUpdatesError.repositoryNotFound("\(owner)/\(name)")

        case 403, 429:
            let remaining = httpResponse.value(forHTTPHeaderField: "x-ratelimit-remaining")
            if remaining == "0" {
                throw GitHubUpdatesError.rateLimited
            }

            throw GitHubUpdatesError.serverError(parsedErrorMessage(from: data) ?? "GitHub 暂时拒绝了这次请求。")

        default:
            throw GitHubUpdatesError.serverError(parsedErrorMessage(from: data) ?? "GitHub 返回了 \(httpResponse.statusCode) 错误。")
        }
    }

    private func makeRepositoryURL(owner: String, name: String) throws -> URL {
        guard
            let encodedOwner = owner.addingPercentEncoding(withAllowedCharacters: .gitHubPathAllowed),
            let encodedName = name.addingPercentEncoding(withAllowedCharacters: .gitHubPathAllowed),
            var components = URLComponents(string: "https://api.github.com")
        else {
            throw GitHubUpdatesError.invalidRepositoryPath
        }

        components.path = "/repos/\(encodedOwner)/\(encodedName)"

        guard let url = components.url else {
            throw GitHubUpdatesError.invalidRepositoryPath
        }

        return url
    }

    private func parsedErrorMessage(from data: Data) -> String? {
        (try? JSONDecoder().decode(GitHubAPIErrorResponse.self, from: data).message)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum GitHubUpdatesBackgroundRefreshManager {
    static let taskIdentifier = "com.easysearch.github.refresh"
    private static let minimumRefreshInterval: TimeInterval = 4 * 60 * 60

    static func scheduleNextRefresh() async {
        let hasRepositories = await GitHubUpdatesService.shared.hasRepositories()

        await MainActor.run {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)

            guard hasRepositories else { return }

            let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
            request.earliestBeginDate = Date(timeIntervalSinceNow: minimumRefreshInterval)

            do {
                try BGTaskScheduler.shared.submit(request)
            } catch {
                print("GitHub background refresh schedule failed: \(error.localizedDescription)")
            }
        }
    }

    static func handleBackgroundRefresh() async {
        await GitHubUpdatesNotificationManager.shared.refreshAuthorizationStatus()
        let summary = await GitHubUpdatesService.shared.refreshRepositories(trigger: .background, force: true)

        if summary.didPersistChanges {
            let repositories = await GitHubUpdatesService.shared.loadRepositories()
            if !repositories.isEmpty {
                await HiddenCloudSyncViewModel.shared.syncGitHubRepoWatchesIfPossible(repositories)
            }
        }

        await scheduleNextRefresh()
    }
}

@MainActor
final class GitHubUpdatesNotificationManager: ObservableObject {
    static let shared = GitHubUpdatesNotificationManager()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let center: UNUserNotificationCenter

    private init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    var notificationsEnabled: Bool {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }

    var statusText: String {
        switch authorizationStatus {
        case .authorized:
            return "已开启 GitHub 更新提醒"
        case .provisional, .ephemeral:
            return "提醒已启用"
        case .denied:
            return "通知权限已关闭"
        case .notDetermined:
            return "尚未开启通知"
        @unknown default:
            return "通知状态未知"
        }
    }

    func configure() async {
        await refreshAuthorizationStatus()
    }

    func requestAuthorization() async {
        do {
            _ = try await requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            // Best effort. UI reads final status below.
        }

        await refreshAuthorizationStatus()
    }

    func refreshAuthorizationStatus() async {
        authorizationStatus = await notificationSettings().authorizationStatus
    }

    func notifyAboutUpdates(_ repositories: [GitHubWatchedRepository]) async {
        guard notificationsEnabled, !repositories.isEmpty else { return }

        let content = UNMutableNotificationContent()
        content.sound = .default
        content.title = "GitHub 项目有更新"

        if repositories.count == 1, let repository = repositories.first {
            content.body = "\(repository.fullName) 有新的 push，打开 App 查看详情。"
        } else if let first = repositories.first {
            content.body = "\(first.fullName) 等 \(repositories.count) 个仓库有新的 push。"
        } else {
            content.body = "你关注的 GitHub 项目有新的 push。"
        }

        let request = UNNotificationRequest(
            identifier: "github.update.\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )

        await add(request)
    }

    private func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            center.requestAuthorization(options: options) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func notificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    private func add(_ request: UNNotificationRequest) async {
        await withCheckedContinuation { continuation in
            center.add(request) { _ in
                continuation.resume()
            }
        }
    }
}
