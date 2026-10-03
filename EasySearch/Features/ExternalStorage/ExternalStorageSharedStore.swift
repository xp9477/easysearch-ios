import Foundation
import Security

protocol ExternalStorageKeychainProtocol: Sendable {
    func savePassword(password: String, locationID: UUID) throws
    func readPassword(locationID: UUID) throws -> String
    func deletePassword(locationID: UUID) throws
}

struct ExternalStorageSharedKeychain: ExternalStorageKeychainProtocol {
    static let sharedAccessGroup = "group.com.easysearch.xp9477"
    static let sharedServiceName = "com.easysearch.xp9477.external-storage"

    private let accessGroup: String
    private let serviceName: String

    init(
        accessGroup: String = ExternalStorageSharedKeychain.sharedAccessGroup,
        serviceName: String = ExternalStorageSharedKeychain.sharedServiceName
    ) {
        self.accessGroup = accessGroup
        self.serviceName = serviceName
    }

    private func account(for locationID: UUID) -> String {
        "external-storage.password.\(locationID.uuidString)"
    }

    func savePassword(password: String, locationID: UUID) throws {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account(for: locationID),
            kSecAttrAccessGroup as String: accessGroup,
            kSecUseDataProtectionKeychain as String: true
        ]

        let updateAttributes: [String: Any] = [
            kSecValueData as String: Data(password.utf8)
        ]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus == errSecItemNotFound {
            var insertQuery = baseQuery
            insertQuery[kSecValueData as String] = Data(password.utf8)
            insertQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(insertQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw ExternalStorageError.keychainFailure(status: addStatus)
            }
            return
        }

        throw ExternalStorageError.keychainFailure(status: updateStatus)
    }

    func readPassword(locationID: UUID) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account(for: locationID),
            kSecAttrAccessGroup as String: accessGroup,
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            throw ExternalStorageError.passwordNotFound(locationID: locationID)
        }

        guard status == errSecSuccess, let data = item as? Data, let password = String(data: data, encoding: .utf8) else {
            throw ExternalStorageError.keychainFailure(status: status)
        }

        return password
    }

    func deletePassword(locationID: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account(for: locationID),
            kSecAttrAccessGroup as String: accessGroup,
            kSecUseDataProtectionKeychain as String: true
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw ExternalStorageError.keychainFailure(status: status)
        }
    }
}

final class ExternalStorageSharedStore: @unchecked Sendable {
    static let shared = ExternalStorageSharedStore()

    static let appGroupIdentifier = "group.com.easysearch.xp9477"
    private static let storageDirectoryName = "ExternalStorage"
    private static let locationsFileName = "locations.json"

    private let fileManager: FileManager
    private let appGroupIdentifier: String
    private let keychain: ExternalStorageKeychainProtocol
    private let customRootURL: URL?

    init(
        appGroupIdentifier: String = ExternalStorageSharedStore.appGroupIdentifier,
        fileManager: FileManager = .default,
        keychain: ExternalStorageKeychainProtocol = ExternalStorageSharedKeychain(),
        customRootURL: URL? = nil
    ) {
        self.appGroupIdentifier = appGroupIdentifier
        self.fileManager = fileManager
        self.keychain = keychain
        self.customRootURL = customRootURL
    }

    func rootDirectoryURL() throws -> URL {
        if let customRootURL {
            let root = customRootURL.appendingPathComponent(Self.storageDirectoryName, isDirectory: true)
            if !fileManager.fileExists(atPath: root.path) {
                try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            }
            return root
        }

        guard let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw ExternalStorageError.appGroupUnavailable(identifier: appGroupIdentifier)
        }
        let root = container.appendingPathComponent(Self.storageDirectoryName, isDirectory: true)
        if !fileManager.fileExists(atPath: root.path) {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        }
        return root
    }

    func locationsFileURL() throws -> URL {
        try rootDirectoryURL().appendingPathComponent(Self.locationsFileName, isDirectory: false)
    }

    // Each publication gets fresh credential IDs. The atomic metadata rename is
    // the commit point, so a failed update never overwrites an old password.
    func publish(locations: [WebDAVLocation]) throws {
        let root = try rootDirectoryURL()
        try ProcessFileLock(lockFileURL: root.appendingPathComponent("publish.lock")).withLock {
            let previous = try readLocationsUnlocked()
            var staged: [ExternalStorageLocationMetadata] = []
            do {
                for location in locations {
                    guard location.configuration.isValid else { throw WebDAVError.invalidConfiguration }
                    let credentialID = UUID()
                    try keychain.savePassword(password: location.password, locationID: credentialID)
                    staged.append(ExternalStorageLocationMetadata(
                        id: location.id, name: location.name, baseURL: location.baseURL,
                        username: location.username, credentialID: credentialID
                    ))
                }
                let data = try JSONEncoder().encode(staged)
                try data.write(to: try locationsFileURL(), options: .atomic)
            } catch {
                for item in staged { try? keychain.deletePassword(locationID: item.credentialID ?? item.id) }
                throw error
            }
            // Readers hold the same lock through credential lookup.
            for item in previous { try? keychain.deletePassword(locationID: item.credentialID ?? item.id) }
        }
    }

    private func readLocationsUnlocked() throws -> [ExternalStorageLocationMetadata] {
        let fileURL = try locationsFileURL()
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        return try JSONDecoder().decode([ExternalStorageLocationMetadata].self, from: Data(contentsOf: fileURL))
    }

    func loadLocations() throws -> [ExternalStorageLocationMetadata] {
        let root = try rootDirectoryURL()
        return try ProcessFileLock(lockFileURL: root.appendingPathComponent("publish.lock")).withLock {
            try readLocationsUnlocked()
        }
    }

    func configuration(locationID: UUID) throws -> WebDAVConfiguration {
        let root = try rootDirectoryURL()
        return try ProcessFileLock(lockFileURL: root.appendingPathComponent("publish.lock")).withLock {
            guard let meta = try readLocationsUnlocked().first(where: { $0.id == locationID }) else {
                throw ExternalStorageError.locationNotFound(locationID: locationID)
            }
            let password = try keychain.readPassword(locationID: meta.credentialID ?? meta.id)
            return WebDAVConfiguration(locationID: meta.id, displayName: meta.name,
                                       baseURL: meta.baseURL, username: meta.username, password: password)
        }
    }
}
