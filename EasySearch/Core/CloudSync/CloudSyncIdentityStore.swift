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
        guard let value = userDefaults.string(forKey: key),
              let boundUserID = UUID(uuidString: value) else {
            return .unbound
        }
        return boundUserID == userID ? .matches : .mismatches
    }

    func bind(to userID: UUID) {
        userDefaults.set(userID.uuidString, forKey: key)
    }
}
