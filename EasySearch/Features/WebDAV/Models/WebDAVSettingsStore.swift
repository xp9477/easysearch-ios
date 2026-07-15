import Foundation
import Combine
import Security

final class WebDAVSettingsStore: ObservableObject {
    static let shared = WebDAVSettingsStore()

    @Published private(set) var configuration: WebDAVConfiguration?

    private let userDefaults: UserDefaults
    private let keychain: WebDAVKeychain

    private enum Keys {
        static let baseURL = "webdav.baseURL"
        static let username = "webdav.username"
    }

    init(
        userDefaults: UserDefaults = .standard,
        keychain: WebDAVKeychain = WebDAVKeychain()
    ) {
        self.userDefaults = userDefaults
        self.keychain = keychain
        configuration = Self.loadConfiguration(userDefaults: userDefaults, keychain: keychain)
    }

    func reload() {
        configuration = Self.loadConfiguration(userDefaults: userDefaults, keychain: keychain)
    }

    @discardableResult
    func save(baseURLString: String, username: String, password: String) -> Result<Void, WebDAVError> {
        switch makeConfiguration(baseURLString: baseURLString, username: username, password: password) {
        case let .success(configuration):
            return save(configuration: configuration)
        case let .failure(error):
            return .failure(error)
        }
    }

    func makeConfiguration(
        baseURLString: String,
        username: String,
        password: String
    ) -> Result<WebDAVConfiguration, WebDAVError> {
        let trimmedURL = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host != nil else {
            return .failure(.invalidURL)
        }

        return .success(WebDAVConfiguration(
            baseURL: Self.normalizedBaseURL(url),
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        ))
    }

    @discardableResult
    func save(configuration newConfiguration: WebDAVConfiguration) -> Result<Void, WebDAVError> {
        guard newConfiguration.isValid else { return .failure(.invalidConfiguration) }
        do {
            try keychain.save(password: newConfiguration.password)
            userDefaults.set(newConfiguration.baseURL.absoluteString, forKey: Keys.baseURL)
            userDefaults.set(newConfiguration.username, forKey: Keys.username)
            reload()
            return .success(())
        } catch {
            return .failure(.server(statusCode: 0, message: "无法保存密码：\(error.localizedDescription)"))
        }
    }

    func clear() {
        userDefaults.removeObject(forKey: Keys.baseURL)
        userDefaults.removeObject(forKey: Keys.username)
        try? keychain.deletePassword()
        configuration = nil
    }

    private static func loadConfiguration(
        userDefaults: UserDefaults,
        keychain: WebDAVKeychain
    ) -> WebDAVConfiguration? {
        guard let value = userDefaults.string(forKey: Keys.baseURL),
              let url = URL(string: value),
              let password = try? keychain.readPassword() else {
            return nil
        }

        let configuration = WebDAVConfiguration(
            baseURL: normalizedBaseURL(url),
            username: userDefaults.string(forKey: Keys.username) ?? "",
            password: password
        )
        return configuration.isValid ? configuration : nil
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
        return components.url ?? url
    }
}

struct WebDAVKeychain {
    private let service: String
    private let account: String

    init(
        service: String = Bundle.main.bundleIdentifier ?? "com.easysearch.xp9477",
        account: String = "webdav-password"
    ) {
        self.service = service
        self.account = account
    }

    func save(password: String) throws {
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

    func readPassword() throws -> String {
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

    func deletePassword() throws {
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
