import Combine
import Foundation
import Security

@MainActor
final class WebDAVSettingsStore: ObservableObject {
    static let shared = WebDAVSettingsStore()

    @Published private(set) var locations: [WebDAVLocation]
    @Published private(set) var selectedLocationID: UUID?
    @Published private(set) var showsHiddenFolders: Bool

    private let userDefaults: UserDefaults
    private let keychain: WebDAVCredentialStoring

    private enum Keys {
        static let locations = "webdav.locations.v2"
        static let selectedLocationID = "webdav.selectedLocationID"
        static let showsHiddenFolders = "webdav.showsHiddenFolders"
        static let legacyBaseURL = "webdav.baseURL"
        static let legacyUsername = "webdav.username"
    }

    private struct StoredLocation: Codable {
        let id: UUID
        let name: String
        let baseURL: String
        let username: String
    }

    var selectedLocation: WebDAVLocation? {
        guard let selectedLocationID else { return locations.first }
        return locations.first(where: { $0.id == selectedLocationID }) ?? locations.first
    }

    var configuration: WebDAVConfiguration? {
        selectedLocation?.configuration
    }

    init(
        userDefaults: UserDefaults = .standard,
        keychain: WebDAVCredentialStoring = WebDAVKeychain()
    ) {
        self.userDefaults = userDefaults
        self.keychain = keychain
        self.locations = []
        self.selectedLocationID = userDefaults.string(forKey: Keys.selectedLocationID).flatMap(UUID.init(uuidString:))
        self.showsHiddenFolders = userDefaults.bool(forKey: Keys.showsHiddenFolders)
        self.locations = loadLocations()
        migrateLegacyConfigurationIfNeeded()
        normalizeSelection()
    }

    func reload() {
        locations = loadLocations()
        selectedLocationID = userDefaults.string(forKey: Keys.selectedLocationID).flatMap(UUID.init(uuidString:))
        showsHiddenFolders = userDefaults.bool(forKey: Keys.showsHiddenFolders)
        normalizeSelection()
    }

    func location(withID id: UUID) -> WebDAVLocation? {
        locations.first(where: { $0.id == id })
    }

    func select(locationID: UUID) {
        guard locations.contains(where: { $0.id == locationID }) else { return }
        selectedLocationID = locationID
        userDefaults.set(locationID.uuidString, forKey: Keys.selectedLocationID)
    }

    func setShowsHiddenFolders(_ value: Bool) {
        showsHiddenFolders = value
        userDefaults.set(value, forKey: Keys.showsHiddenFolders)
    }

    func makeLocation(
        id: UUID = UUID(),
        name: String,
        baseURLString: String,
        username: String,
        password: String
    ) -> Result<WebDAVLocation, WebDAVError> {
        let trimmedURL = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host != nil else {
            return .failure(.invalidURL)
        }

        let normalizedURL = Self.normalizedBaseURL(url)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmedName.isEmpty ? (normalizedURL.host ?? "WebDAV") : trimmedName
        return .success(WebDAVLocation(
            id: id,
            name: displayName,
            baseURL: normalizedURL,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        ))
    }

    @discardableResult
    func save(location: WebDAVLocation, select: Bool = true) -> Result<Void, WebDAVError> {
        guard location.configuration.isValid else { return .failure(.invalidConfiguration) }
        do {
            try keychain.save(password: location.password, locationID: location.id)
            if let index = locations.firstIndex(where: { $0.id == location.id }) {
                locations[index] = location
            } else {
                locations.append(location)
            }
            locations.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            try persistLocations()
            if select || selectedLocationID == nil {
                self.select(locationID: location.id)
            }
            return .success(())
        } catch {
            return .failure(.server(statusCode: 0, message: "无法保存 WebDAV 位置：\(error.localizedDescription)"))
        }
    }

    func remove(locationID: UUID) {
        locations.removeAll(where: { $0.id == locationID })
        try? keychain.deletePassword(locationID: locationID)
        try? persistLocations()
        if selectedLocationID == locationID {
            selectedLocationID = locations.first?.id
            if let selectedLocationID {
                userDefaults.set(selectedLocationID.uuidString, forKey: Keys.selectedLocationID)
            } else {
                userDefaults.removeObject(forKey: Keys.selectedLocationID)
            }
        }
    }

    func clear() {
        for location in locations {
            try? keychain.deletePassword(locationID: location.id)
        }
        locations = []
        selectedLocationID = nil
        userDefaults.removeObject(forKey: Keys.locations)
        userDefaults.removeObject(forKey: Keys.selectedLocationID)
        userDefaults.removeObject(forKey: Keys.legacyBaseURL)
        userDefaults.removeObject(forKey: Keys.legacyUsername)
        try? keychain.deleteLegacyPassword()
    }

    private func loadLocations() -> [WebDAVLocation] {
        guard let data = userDefaults.data(forKey: Keys.locations),
              let stored = try? JSONDecoder().decode([StoredLocation].self, from: data) else {
            return []
        }
        return stored.compactMap { value in
            guard let url = URL(string: value.baseURL) else { return nil }
            let password = (try? keychain.readPassword(locationID: value.id)) ?? ""
            let location = WebDAVLocation(
                id: value.id,
                name: value.name,
                baseURL: Self.normalizedBaseURL(url),
                username: value.username,
                password: password
            )
            return location.configuration.isValid ? location : nil
        }
    }

    private func persistLocations() throws {
        let stored = locations.map {
            StoredLocation(
                id: $0.id,
                name: $0.name,
                baseURL: $0.baseURL.absoluteString,
                username: $0.username
            )
        }
        userDefaults.set(try JSONEncoder().encode(stored), forKey: Keys.locations)
    }

    private func migrateLegacyConfigurationIfNeeded() {
        guard locations.isEmpty,
              let value = userDefaults.string(forKey: Keys.legacyBaseURL),
              let url = URL(string: value) else { return }
        let password = (try? keychain.readLegacyPassword()) ?? ""
        let id = UUID()
        let location = WebDAVLocation(
            id: id,
            name: url.host ?? "WebDAV",
            baseURL: Self.normalizedBaseURL(url),
            username: userDefaults.string(forKey: Keys.legacyUsername) ?? "",
            password: password
        )
        guard location.configuration.isValid else { return }
        do {
            try keychain.save(password: password, locationID: id)
            locations = [location]
            try persistLocations()
            select(locationID: id)
            userDefaults.removeObject(forKey: Keys.legacyBaseURL)
            userDefaults.removeObject(forKey: Keys.legacyUsername)
            try? keychain.deleteLegacyPassword()
        } catch {
            locations = []
        }
    }

    private func normalizeSelection() {
        if let selectedLocationID,
           locations.contains(where: { $0.id == selectedLocationID }) {
            return
        }
        selectedLocationID = locations.first?.id
        if let selectedLocationID {
            userDefaults.set(selectedLocationID.uuidString, forKey: Keys.selectedLocationID)
        } else {
            userDefaults.removeObject(forKey: Keys.selectedLocationID)
        }
    }

    private static func normalizedBaseURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        var path = components.path
        if !path.hasSuffix("/") {
            path.append("/")
        }
        components.path = path
        components.query = nil
        components.fragment = nil
        return components.url ?? url
    }
}

protocol WebDAVCredentialStoring {
    func save(password: String, locationID: UUID) throws
    func readPassword(locationID: UUID) throws -> String
    func deletePassword(locationID: UUID) throws
    func readLegacyPassword() throws -> String
    func deleteLegacyPassword() throws
}

struct WebDAVKeychain: WebDAVCredentialStoring {
    private let service: String
    private let legacyAccount: String

    init(
        service: String = Bundle.main.bundleIdentifier ?? "com.easysearch.xp9477",
        legacyAccount: String = "webdav-password"
    ) {
        self.service = service
        self.legacyAccount = legacyAccount
    }

    func save(password: String, locationID: UUID) throws {
        try save(password: password, account: account(for: locationID))
    }

    func readPassword(locationID: UUID) throws -> String {
        try readPassword(account: account(for: locationID))
    }

    func deletePassword(locationID: UUID) throws {
        try deletePassword(account: account(for: locationID))
    }

    func readLegacyPassword() throws -> String {
        try readPassword(account: legacyAccount)
    }

    func deleteLegacyPassword() throws {
        try deletePassword(account: legacyAccount)
    }

    private func account(for locationID: UUID) -> String {
        "webdav-password.\(locationID.uuidString)"
    }

    private func save(password: String, account: String) throws {
        let data = Data(password.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = baseQuery
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus))
            }
        } else if status != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private func readPassword(account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return password
    }

    private func deletePassword(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}
