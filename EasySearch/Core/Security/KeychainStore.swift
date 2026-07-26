import Foundation
import Security

/// Small shared helper for generic-password Keychain items.
/// Features keep their own service/account names; this only centralizes SecItem boilerplate.
struct KeychainStore {
    let service: String

    enum StoreError: LocalizedError {
        case status(OSStatus)
        case encoding

        var errorDescription: String? {
            switch self {
            case let .status(status):
                return "Keychain 操作失败，状态码 \(status)。"
            case .encoding:
                return "Keychain 数据编码失败。"
            }
        }
    }

    func loadData(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess, let data = item as? Data else {
            throw StoreError.status(status)
        }

        return data
    }

    func saveData(_ data: Data, account: String) throws {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw StoreError.status(updateStatus)
        }

        var insert = baseQuery
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let insertStatus = SecItemAdd(insert as CFDictionary, nil)
        guard insertStatus == errSecSuccess else {
            throw StoreError.status(insertStatus)
        }
    }

    func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    func loadString(account: String) throws -> String? {
        guard let data = try loadData(account: account) else { return nil }
        guard let value = String(data: data, encoding: .utf8) else {
            throw StoreError.encoding
        }
        return value
    }

    func saveString(_ value: String, account: String) throws {
        try saveData(Data(value.utf8), account: account)
    }

    /// Replace semantics used by some callers: delete then add.
    func replaceData(_ data: Data, account: String) throws {
        delete(account: account)
        var insert: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw StoreError.status(status)
        }
    }
}
