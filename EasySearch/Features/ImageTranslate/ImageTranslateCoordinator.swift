import Foundation
import Security
import UIKit

enum ImageTranslateError: LocalizedError {
    case missingAPIKey
    case emptySourceText
    case invalidImage
    case invalidCropArea
    case noTextRecognized
    case noImageInPasteboard
    case cameraUnavailable
    case invalidResponse
    case emptyModelResponse
    case ocrFailure(String)
    case serverError(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "请先到设置页填写 DeepSeek API Key。"
        case .emptySourceText:
            return "没有可翻译的文字，请先识别图片或手动补充文本。"
        case .invalidImage:
            return "图片读取失败，请重新选择。"
        case .invalidCropArea:
            return "裁剪区域太小或无效，请重新框选。"
        case .noTextRecognized:
            return "没有识别到清晰文字，建议换一张更清楚的图片。"
        case .noImageInPasteboard:
            return "剪贴板里没有图片。"
        case .cameraUnavailable:
            return "当前设备暂时不能使用相机。"
        case .invalidResponse:
            return "DeepSeek 返回了无法识别的结果。"
        case .emptyModelResponse:
            return "DeepSeek 没有返回有效内容，请重试。"
        case let .ocrFailure(message):
            return "文字识别失败：\(message)"
        case let .serverError(message):
            return message
        case let .networkError(message):
            return message
        }
    }
}

private struct ImageTranslateKeychainStore {
    private let service = "com.easysearch.image-translate"
    private let account = "deepseek.api-key.v1"

    func loadAPIKey() throws -> String? {
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

        guard status == errSecSuccess,
              let data = item as? Data,
              let apiKey = String(data: data, encoding: .utf8) else {
            throw ImageTranslateError.serverError("读取 DeepSeek API Key 失败，Keychain 状态码 \(status)。")
        }

        return apiKey
    }

    func saveAPIKey(_ apiKey: String) throws {
        let data = Data(apiKey.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(baseQuery as CFDictionary)

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ImageTranslateError.serverError("保存 DeepSeek API Key 失败，Keychain 状态码 \(status)。")
        }
    }

    func deleteAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

final class ImageTranslateConfigurationStore {
    static let shared = ImageTranslateConfigurationStore()

    private let userDefaults: UserDefaults
    private let keychainStore: ImageTranslateKeychainStore
    private let notificationCenter: NotificationCenter
    private let modelKey = "imageTranslate.deepseek.model"
    private let targetLanguageKey = "imageTranslate.targetLanguage"

    private init(
        userDefaults: UserDefaults = .standard,
        keychainStore: ImageTranslateKeychainStore = ImageTranslateKeychainStore(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.userDefaults = userDefaults
        self.keychainStore = keychainStore
        self.notificationCenter = notificationCenter
    }

    func loadConfiguration() -> ImageTranslateConfiguration {
        let bundledAPIKey = (Bundle.main.object(forInfoDictionaryKey: "DEEPSEEK_API_KEY") as? String) ?? ""
        let bundledModel = (Bundle.main.object(forInfoDictionaryKey: "DEEPSEEK_MODEL") as? String) ?? "deepseek-chat"
        let storedAPIKey = (try? keychainStore.loadAPIKey()) ?? nil
        let storedModel = userDefaults.string(forKey: modelKey) ?? bundledModel
        let rawTargetLanguage = userDefaults.string(forKey: targetLanguageKey)
        let targetLanguage = rawTargetLanguage.flatMap(ImageTranslateTargetLanguage.init(rawValue:)) ?? .simplifiedChinese

        return ImageTranslateConfiguration(
            apiKey: storedAPIKey ?? bundledAPIKey,
            model: storedModel,
            targetLanguage: targetLanguage
        )
    }

    func saveConfiguration(
        apiKey: String,
        model: String,
        targetLanguage: ImageTranslateTargetLanguage
    ) throws {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedAPIKey.isEmpty {
            keychainStore.deleteAPIKey()
        } else {
            try keychainStore.saveAPIKey(trimmedAPIKey)
        }

        userDefaults.set(trimmedModel.isEmpty ? "deepseek-chat" : trimmedModel, forKey: modelKey)
        userDefaults.set(targetLanguage.rawValue, forKey: targetLanguageKey)

        notificationCenter.post(name: .imageTranslateConfigurationDidChange, object: nil)
    }

    func updateTargetLanguage(_ targetLanguage: ImageTranslateTargetLanguage) {
        userDefaults.set(targetLanguage.rawValue, forKey: targetLanguageKey)
        notificationCenter.post(name: .imageTranslateConfigurationDidChange, object: nil)
    }
}

private struct ImageTranslateModelPayload: Decodable {
    let translation: String?
    let reply: String?
    let notes: String?
    let detectedSourceLanguage: String?
    let suggestedReplies: [String]?

    enum CodingKeys: String, CodingKey {
        case translation
        case reply
        case notes
        case detectedSourceLanguage = "detected_source_language"
        case suggestedReplies = "suggested_replies"
    }
}

actor ImageTranslateService {
    static let shared = ImageTranslateService()

    private let configurationStore: ImageTranslateConfigurationStore
    private let client: DeepSeekClient
    private let decoder = JSONDecoder()
    private let recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"]

    init(
        configurationStore: ImageTranslateConfigurationStore = .shared,
        client: DeepSeekClient = .shared
    ) {
        self.configurationStore = configurationStore
        self.client = client
    }

    func loadConfiguration() -> ImageTranslateConfiguration {
        configurationStore.loadConfiguration()
    }

    func updateTargetLanguage(_ targetLanguage: ImageTranslateTargetLanguage) {
        configurationStore.updateTargetLanguage(targetLanguage)
    }

    func recognizeText(in image: UIImage) async throws -> String {
        let result = try await ImageOCRService.extractText(
            from: image,
            recognitionLanguages: recognitionLanguages
        )
        return result.fullText
    }

    func cropImage(
        _ image: UIImage,
        selection: ImageCropSelection
    ) throws -> UIImage {
        guard let croppedImage = ImageOCRService.cropImage(image, selection: selection) else {
            throw ImageTranslateError.invalidCropArea
        }

        return croppedImage
    }

    func storedImageData(from image: UIImage) -> Data? {
        ImageOCRService.storedImageData(from: image)
    }

    func previewImageData(from image: UIImage) -> Data? {
        ImageOCRService.previewImageData(from: image)
    }

    func translate(
        sourceText: String,
        targetLanguage: ImageTranslateTargetLanguage
    ) async throws -> ImageTranslateResult {
        let trimmedSourceText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSourceText.isEmpty else {
            throw ImageTranslateError.emptySourceText
        }

        let configuration = configurationStore.loadConfiguration()
        guard configuration.hasAPIKey else {
            throw ImageTranslateError.missingAPIKey
        }

        let messages = [
            DeepSeekChatMessage(role: "system", content: translationSystemPrompt),
            DeepSeekChatMessage(
                role: "user",
                content: initialUserPrompt(
                    sourceText: trimmedSourceText,
                    targetLanguage: targetLanguage
                )
            )
        ]

        return try await sendChatRequest(
            configuration: configuration,
            messages: messages,
            fallbackTranslation: nil
        )
    }

    func followUp(
        sourceText: String,
        currentTranslation: String,
        history: [ImageTranslateConversationMessage],
        userPrompt: String,
        targetLanguage: ImageTranslateTargetLanguage
    ) async throws -> ImageTranslateResult {
        let trimmedSourceText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUserPrompt = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCurrentTranslation = currentTranslation.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedSourceText.isEmpty else {
            throw ImageTranslateError.emptySourceText
        }
        guard !trimmedUserPrompt.isEmpty else {
            throw ImageTranslateError.networkError("请输入你想继续优化或追问的内容。")
        }

        let configuration = configurationStore.loadConfiguration()
        guard configuration.hasAPIKey else {
            throw ImageTranslateError.missingAPIKey
        }

        let transcript = history
            .map { message in
                let role = message.role == .user ? "user" : "assistant"
                return "\(role): \(message.text)"
            }
            .joined(separator: "\n")

        let messages = [
            DeepSeekChatMessage(role: "system", content: translationSystemPrompt),
            DeepSeekChatMessage(
                role: "user",
                content: followUpUserPrompt(
                    sourceText: trimmedSourceText,
                    currentTranslation: trimmedCurrentTranslation,
                    transcript: transcript,
                    latestUserPrompt: trimmedUserPrompt,
                    targetLanguage: targetLanguage
                )
            )
        ]

        return try await sendChatRequest(
            configuration: configuration,
            messages: messages,
            fallbackTranslation: trimmedCurrentTranslation
        )
    }

    private func sendChatRequest(
        configuration: ImageTranslateConfiguration,
        messages: [DeepSeekChatMessage],
        fallbackTranslation: String?
    ) async throws -> ImageTranslateResult {
        do {
            let content = try await client.completeText(
                configuration: configuration.deepSeekConfiguration,
                messages: messages,
                responseFormat: .jsonObject,
                maxTokens: 1800
            )
            return try parseModelPayload(content, fallbackTranslation: fallbackTranslation)
        } catch let error as DeepSeekClientError {
            throw mapDeepSeekError(error)
        } catch let error as ImageTranslateError {
            throw error
        } catch {
            throw ImageTranslateError.networkError(error.localizedDescription)
        }
    }

    private func parseModelPayload(
        _ content: String,
        fallbackTranslation: String?
    ) throws -> ImageTranslateResult {
        let cleanedContent = sanitizeJSONContent(content)
        guard let data = cleanedContent.data(using: .utf8) else {
            throw ImageTranslateError.invalidResponse
        }

        let payload = try decoder.decode(ImageTranslateModelPayload.self, from: data)
        let translation = payload.translation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let reply = payload.reply?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let notes = payload.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let detectedSourceLanguage = payload.detectedSourceLanguage?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTranslation = translation.isEmpty ? (fallbackTranslation ?? "") : translation

        guard !resolvedTranslation.isEmpty else {
            throw ImageTranslateError.emptyModelResponse
        }

        return ImageTranslateResult(
            translation: resolvedTranslation,
            reply: reply,
            notes: notes,
            detectedSourceLanguage: detectedSourceLanguage?.isEmpty == true ? nil : detectedSourceLanguage,
            suggestedReplies: normalizeSuggestedReplies(payload.suggestedReplies)
        )
    }

    private func normalizeSuggestedReplies(_ suggestions: [String]?) -> [String] {
        let normalized = (suggestions ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if normalized.count >= 3 {
            return Array(normalized.prefix(3))
        }

        let fallback = ["更自然一点", "解释关键词", "保留原文术语"]
        return Array((normalized + fallback).prefix(3))
    }

    private func sanitizeJSONContent(_ content: String) -> String {
        content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var translationSystemPrompt: String {
        """
        You are an OCR translation assistant. Always return valid json only.
        The required json schema is:
        {
          "translation": "string",
          "reply": "string",
          "notes": "string",
          "detected_source_language": "string",
          "suggested_replies": ["string", "string", "string"]
        }

        Rules:
        - translation must be the latest complete translation result after applying the user's newest request.
        - reply must be concise Chinese for the user, usually one or two sentences.
        - notes should mention OCR uncertainty, terminology choices, or be an empty string.
        - detected_source_language should be a short language label such as English or Japanese.
        - suggested_replies must contain exactly 3 short Chinese follow-up suggestions.
        - Preserve proper nouns, numbers, code snippets, and list structure when useful.
        - If the user asks to rewrite, simplify, formalize, or explain, update translation accordingly.
        - If OCR text is obviously incomplete or noisy, mention that in notes.
        """
    }

    private func initialUserPrompt(
        sourceText: String,
        targetLanguage: ImageTranslateTargetLanguage
    ) -> String {
        """
        Return json only.
        Task: translate the OCR text into \(targetLanguage.promptLabel).

        Source text:
        <source>
        \(sourceText)
        </source>

        Output guidance:
        - translation: the final polished translation in \(targetLanguage.promptLabel)
        - reply: short Chinese guidance telling the user the first draft is ready
        - notes: OCR uncertainty or terminology notes, otherwise empty string
        - detected_source_language: the most likely source language
        - suggested_replies: 3 short Chinese suggestions for multi-turn optimization
        """
    }

    private func followUpUserPrompt(
        sourceText: String,
        currentTranslation: String,
        transcript: String,
        latestUserPrompt: String,
        targetLanguage: ImageTranslateTargetLanguage
    ) -> String {
        let transcriptBlock = transcript.isEmpty ? "(none)" : transcript
        return """
        Return json only.
        Continue the translation conversation in \(targetLanguage.promptLabel).

        Source text:
        <source>
        \(sourceText)
        </source>

        Current translation:
        <translation>
        \(currentTranslation)
        </translation>

        Conversation so far:
        <transcript>
        \(transcriptBlock)
        </transcript>

        Latest user request:
        <request>
        \(latestUserPrompt)
        </request>

        Output guidance:
        - translation: the updated translation after applying the latest request; if the request is only explanatory, keep the best current translation
        - reply: short Chinese answer for the user
        - notes: OCR uncertainty or terminology notes, otherwise empty string
        - detected_source_language: the most likely source language
        - suggested_replies: 3 short Chinese suggestions for the next follow-up
        """
    }

    private func mapDeepSeekError(_ error: DeepSeekClientError) -> ImageTranslateError {
        switch error {
        case .missingAPIKey:
            return .missingAPIKey
        case .invalidResponse:
            return .invalidResponse
        case .emptyResponse:
            return .emptyModelResponse
        case let .serverError(message):
            return .serverError(message)
        case let .networkError(message):
            return .networkError(message)
        }
    }
}
