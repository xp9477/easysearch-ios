import Foundation

enum GitHubUpdatesStorage {
    static let watchedRepositoriesKey = "github_updates.watched_repositories.v1"
    static let lastAutoRefreshAtKey = "github_updates.last_auto_refresh_at.v1"
}

struct GitHubWatchedRepository: Identifiable, Codable, Hashable {
    let id: String
    let owner: String
    let name: String
    let fullName: String
    let htmlURL: URL
    let repositoryDescription: String
    let defaultBranch: String
    let isArchived: Bool
    let isDisabled: Bool
    let lastKnownPushedAt: Date?
    let lastCheckedAt: Date?
    let lastNotifiedPushedAt: Date?
    let createdAt: Date
    let updatedAt: Date

    init(
        id: String,
        owner: String,
        name: String,
        fullName: String,
        htmlURL: URL,
        repositoryDescription: String,
        defaultBranch: String,
        isArchived: Bool,
        isDisabled: Bool,
        lastKnownPushedAt: Date?,
        lastCheckedAt: Date?,
        lastNotifiedPushedAt: Date?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.owner = owner
        self.name = name
        self.fullName = fullName
        self.htmlURL = htmlURL
        self.repositoryDescription = repositoryDescription
        self.defaultBranch = defaultBranch
        self.isArchived = isArchived
        self.isDisabled = isDisabled
        self.lastKnownPushedAt = lastKnownPushedAt
        self.lastCheckedAt = lastCheckedAt
        self.lastNotifiedPushedAt = lastNotifiedPushedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var sortDate: Date {
        lastKnownPushedAt ?? lastCheckedAt ?? updatedAt
    }

    static func sort(lhs: GitHubWatchedRepository, rhs: GitHubWatchedRepository) -> Bool {
        if lhs.sortDate == rhs.sortDate {
            return lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName) == .orderedAscending
        }

        return lhs.sortDate > rhs.sortDate
    }

    func applying(snapshot: GitHubRepositorySnapshot, checkedAt: Date, notifiedAt: Date?) -> GitHubWatchedRepository {
        GitHubWatchedRepository(
            id: snapshot.normalizedID,
            owner: snapshot.owner,
            name: snapshot.name,
            fullName: snapshot.fullName,
            htmlURL: snapshot.htmlURL,
            repositoryDescription: snapshot.repositoryDescription,
            defaultBranch: snapshot.defaultBranch,
            isArchived: snapshot.isArchived,
            isDisabled: snapshot.isDisabled,
            lastKnownPushedAt: snapshot.pushedAt ?? lastKnownPushedAt,
            lastCheckedAt: checkedAt,
            lastNotifiedPushedAt: notifiedAt ?? lastNotifiedPushedAt,
            createdAt: createdAt,
            updatedAt: checkedAt
        )
    }

    func markingChecked(at checkedAt: Date) -> GitHubWatchedRepository {
        GitHubWatchedRepository(
            id: id,
            owner: owner,
            name: name,
            fullName: fullName,
            htmlURL: htmlURL,
            repositoryDescription: repositoryDescription,
            defaultBranch: defaultBranch,
            isArchived: isArchived,
            isDisabled: isDisabled,
            lastKnownPushedAt: lastKnownPushedAt,
            lastCheckedAt: checkedAt,
            lastNotifiedPushedAt: lastNotifiedPushedAt,
            createdAt: createdAt,
            updatedAt: checkedAt
        )
    }
}
