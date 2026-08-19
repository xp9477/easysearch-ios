import Foundation

enum CloudSyncIdentityMatch: Equatable {
    case unbound
    case matches
    case mismatches
}

struct CloudSyncIdentityStore {
    static let defaultKey = "cloudSync.boundUserID.v1"

    private let userDefaults: UserDefaults
    private let key: String

    init(
        userDefaults: UserDefaults = .standard,
        key: String = Self.defaultKey
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    func match(for userID: UUID) -> CloudSyncIdentityMatch {
        guard let value = userDefaults.string(forKey: key) else {
            return .unbound
        }
        // A corrupt binding is evidence that the ownership boundary is unknown,
        // not that this installation has no owner. Fail closed instead of
        // silently rebinding all local data to the next account.
        guard let boundUserID = UUID(uuidString: value) else { return .mismatches }
        return boundUserID == userID ? .matches : .mismatches
    }

    func bind(to userID: UUID) {
        userDefaults.set(userID.uuidString, forKey: key)
    }
}
