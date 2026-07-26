import Foundation

/// Shared AI service configuration (base URL / API key / model).
/// Owned by Core so Email, Settings, and Status Center do not depend on ImageTranslate.
struct AIServiceConfiguration: Equatable {
    var baseURL: String
    var apiKey: String
    var model: String

    var hasAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var resolvedModel: String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "deepseek-chat" : trimmed
    }

    var deepSeekConfiguration: DeepSeekClientConfiguration {
        DeepSeekClientConfiguration(
            baseURL: baseURL,
            apiKey: apiKey,
            model: resolvedModel
        )
    }
}

extension Notification.Name {
    /// Posted when shared AI service configuration changes.
    static let aiConfigurationDidChange = Notification.Name("aiConfigurationDidChange")
    /// Backward-compatible alias for Image Translate listeners.
    static let imageTranslateConfigurationDidChange = Notification.Name("imageTranslateConfigurationDidChange")
}

final class AIConfigurationStore {
    static let shared = AIConfigurationStore()

    /// Historical UserDefaults / Keychain keys kept for migration compatibility.
    private let baseURLKey = "imageTranslate.ai.baseURL"
    private let modelKey = "imageTranslate.deepseek.model"
    private let keychainService = "com.easysearch.image-translate"
    private let keychainAccount = "ai.api-key.v1"

    private let userDefaults: UserDefaults
    private let keychain: KeychainStore
    private let notificationCenter: NotificationCenter

    private init(
        userDefaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        self.userDefaults = userDefaults
        self.keychain = KeychainStore(service: keychainService)
        self.notificationCenter = notificationCenter
    }

    func loadConfiguration() -> AIServiceConfiguration {
        let bundledBaseURL = (Bundle.main.object(forInfoDictionaryKey: "AI_BASE_URL") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "DEEPSEEK_BASE_URL") as? String)
            ?? DeepSeekClientConfiguration.defaultBaseURL
        let bundledAPIKey = (Bundle.main.object(forInfoDictionaryKey: "AI_API_KEY") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "DEEPSEEK_API_KEY") as? String)
            ?? ""
        let bundledModel = (Bundle.main.object(forInfoDictionaryKey: "AI_MODEL") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "DEEPSEEK_MODEL") as? String)
            ?? "deepseek-chat"

        let storedBaseURL = userDefaults.string(forKey: baseURLKey) ?? bundledBaseURL
        let storedAPIKey = (try? keychain.loadString(account: keychainAccount)) ?? nil
        let storedModel = userDefaults.string(forKey: modelKey) ?? bundledModel

        return AIServiceConfiguration(
            baseURL: storedBaseURL,
            apiKey: storedAPIKey ?? bundledAPIKey,
            model: storedModel
        )
    }

    func saveConfiguration(baseURL: String, apiKey: String, model: String) throws {
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedAPIKey.isEmpty {
            keychain.delete(account: keychainAccount)
        } else {
            try keychain.replaceData(Data(trimmedAPIKey.utf8), account: keychainAccount)
        }

        userDefaults.set(
            trimmedBaseURL.isEmpty ? DeepSeekClientConfiguration.defaultBaseURL : trimmedBaseURL,
            forKey: baseURLKey
        )
        userDefaults.set(trimmedModel.isEmpty ? "deepseek-chat" : trimmedModel, forKey: modelKey)

        notificationCenter.post(name: .aiConfigurationDidChange, object: nil)
        notificationCenter.post(name: .imageTranslateConfigurationDidChange, object: nil)
    }
}
