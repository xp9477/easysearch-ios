import Foundation
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
            return "请先到设置页填写 AI API Key。"
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
            return "翻译结果解析失败，请再试一次。"
        case .emptyModelResponse:
            return "没有拿到有效译文，请再试一次。"
        case let .ocrFailure(message):
            return "文字识别失败：\(message)"
        case let .serverError(message):
            return message
        case let .networkError(message):
            return message
        }
    }
}

/// Feature-local preferences (target language) layered on shared `AIConfigurationStore`.
final class ImageTranslateConfigurationStore {
    static let shared = ImageTranslateConfigurationStore()

    private let userDefaults: UserDefaults
    private let aiStore: AIConfigurationStore
    private let notificationCenter: NotificationCenter
    private let targetLanguageKey = "imageTranslate.targetLanguage"

    private init(
        userDefaults: UserDefaults = .standard,
        aiStore: AIConfigurationStore = .shared,
        notificationCenter: NotificationCenter = .default
    ) {
        self.userDefaults = userDefaults
        self.aiStore = aiStore
        self.notificationCenter = notificationCenter
    }

    func loadConfiguration() -> ImageTranslateConfiguration {
        let service = aiStore.loadConfiguration()
        let rawTargetLanguage = userDefaults.string(forKey: targetLanguageKey)
        let targetLanguage = rawTargetLanguage.flatMap(ImageTranslateTargetLanguage.init(rawValue:)) ?? .simplifiedChinese
        return ImageTranslateConfiguration(service: service, targetLanguage: targetLanguage)
    }

    func saveConfiguration(
        baseURL: String,
        apiKey: String,
        model: String,
        targetLanguage: ImageTranslateTargetLanguage
    ) throws {
        try aiStore.saveConfiguration(baseURL: baseURL, apiKey: apiKey, model: model)
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
    let meanings: [ImageTranslateMeaningPayload]?
    let examples: [ImageTranslateExamplePayload]?
    let collocations: [ImageTranslateCollocationPayload]?
    let suggestedReplies: [String]?

    enum CodingKeys: String, CodingKey {
        case translation
        case reply
        case notes
        case detectedSourceLanguage = "detected_source_language"
        case meanings
        case examples
        case collocations
        case suggestedReplies = "suggested_replies"
    }
}

private struct ImageTranslateMeaningPayload: Decodable {
    let partOfSpeech: String?
    let meaning: String?

    enum CodingKeys: String, CodingKey {
        case partOfSpeech = "part_of_speech"
        case meaning
    }
}

private struct ImageTranslateExamplePayload: Decodable {
    let source: String?
    let translation: String?
}

private struct ImageTranslateCollocationPayload: Decodable {
    let phrase: String?
    let translation: String?
    let note: String?
}

/// Pure helpers for translation request shaping / response parsing (unit-testable).
enum ImageTranslateResponseParser {
    static func isLikelyLexicalQuery(_ sourceText: String) -> Bool {
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard trimmed.count <= 48 else { return false }
        guard !trimmed.contains("\n") else { return false }

        let sentencePunctuation = CharacterSet(charactersIn: ".!?。！？;；：:")
        if trimmed.rangeOfCharacter(from: sentencePunctuation) != nil {
            return false
        }

        let tokens = trimmed.split { $0.isWhitespace }
        if tokens.count <= 4 {
            return true
        }

        let compact = trimmed.replacingOccurrences(of: " ", with: "")
        return compact.count <= 12
    }

    static func sanitizeJSONContent(_ content: String) -> String {
        var text = content
            .replacingOccurrences(of: "```json", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}"),
           start < end {
            text = String(text[start...end])
        }

        return text
    }

    static func maxTokens(isLexical: Bool, isMinimal: Bool) -> Int {
        if isMinimal { return 320 }
        return isLexical ? 700 : 1200
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

        let isLexical = ImageTranslateResponseParser.isLikelyLexicalQuery(trimmedSourceText)
        let messages = [
            DeepSeekChatMessage(role: "system", content: translationSystemPrompt(isLexical: isLexical)),
            DeepSeekChatMessage(
                role: "user",
                content: initialUserPrompt(
                    sourceText: trimmedSourceText,
                    targetLanguage: targetLanguage,
                    isLexical: isLexical
                )
            )
        ]

        return try await sendChatRequest(
            configuration: configuration,
            messages: messages,
            sourceText: trimmedSourceText,
            targetLanguage: targetLanguage,
            isLexical: isLexical,
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

        let isLexical = ImageTranslateResponseParser.isLikelyLexicalQuery(trimmedSourceText)
        let transcript = history
            .map { message in
                let role = message.role == .user ? "user" : "assistant"
                return "\(role): \(message.text)"
            }
            .joined(separator: "\n")

        let messages = [
            DeepSeekChatMessage(role: "system", content: translationSystemPrompt(isLexical: isLexical)),
            DeepSeekChatMessage(
                role: "user",
                content: followUpUserPrompt(
                    sourceText: trimmedSourceText,
                    currentTranslation: trimmedCurrentTranslation,
                    transcript: transcript,
                    latestUserPrompt: trimmedUserPrompt,
                    targetLanguage: targetLanguage,
                    isLexical: isLexical
                )
            )
        ]

        return try await sendChatRequest(
            configuration: configuration,
            messages: messages,
            sourceText: trimmedSourceText,
            targetLanguage: targetLanguage,
            isLexical: isLexical,
            fallbackTranslation: trimmedCurrentTranslation
        )
    }

    private func sendChatRequest(
        configuration: ImageTranslateConfiguration,
        messages: [DeepSeekChatMessage],
        sourceText: String,
        targetLanguage: ImageTranslateTargetLanguage,
        isLexical: Bool,
        fallbackTranslation: String?
    ) async throws -> ImageTranslateResult {
        do {
            return try await performChatRequest(
                configuration: configuration,
                messages: messages,
                isLexical: isLexical,
                isMinimal: false,
                fallbackTranslation: fallbackTranslation
            )
        } catch let error as ImageTranslateError where shouldRetryWithMinimalPrompt(error) {
            // First response arrived but was unusable — fall back to a tiny translate-only request.
            let minimalMessages = [
                DeepSeekChatMessage(role: "system", content: minimalSystemPrompt),
                DeepSeekChatMessage(
                    role: "user",
                    content: minimalUserPrompt(sourceText: sourceText, targetLanguage: targetLanguage)
                )
            ]
            return try await performChatRequest(
                configuration: configuration,
                messages: minimalMessages,
                isLexical: isLexical,
                isMinimal: true,
                fallbackTranslation: fallbackTranslation
            )
        }
    }

    private func performChatRequest(
        configuration: ImageTranslateConfiguration,
        messages: [DeepSeekChatMessage],
        isLexical: Bool,
        isMinimal: Bool,
        fallbackTranslation: String?
    ) async throws -> ImageTranslateResult {
        do {
            let content = try await client.completeText(
                configuration: configuration.deepSeekConfiguration,
                messages: messages,
                responseFormat: .jsonObject,
                temperature: 0.2,
                maxTokens: ImageTranslateResponseParser.maxTokens(isLexical: isLexical, isMinimal: isMinimal)
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

    private func shouldRetryWithMinimalPrompt(_ error: ImageTranslateError) -> Bool {
        switch error {
        case .invalidResponse, .emptyModelResponse:
            return true
        default:
            return false
        }
    }

    private func parseModelPayload(
        _ content: String,
        fallbackTranslation: String?
    ) throws -> ImageTranslateResult {
        let cleanedContent = ImageTranslateResponseParser.sanitizeJSONContent(content)
        guard let data = cleanedContent.data(using: .utf8) else {
            throw ImageTranslateError.invalidResponse
        }

        let payload: ImageTranslateModelPayload
        do {
            payload = try decoder.decode(ImageTranslateModelPayload.self, from: data)
        } catch {
            throw ImageTranslateError.invalidResponse
        }

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
            meanings: normalizeMeanings(payload.meanings),
            examples: normalizeExamples(payload.examples),
            collocations: normalizeCollocations(payload.collocations),
            suggestedReplies: normalizeSuggestedReplies(payload.suggestedReplies)
        )
    }

    private func normalizeMeanings(_ meanings: [ImageTranslateMeaningPayload]?) -> [ImageTranslateMeaning] {
        let normalized = (meanings ?? []).compactMap { item -> ImageTranslateMeaning? in
            let partOfSpeech = item.partOfSpeech?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let meaning = item.meaning?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !meaning.isEmpty else { return nil }
            return ImageTranslateMeaning(partOfSpeech: partOfSpeech, meaning: meaning)
        }

        return Array(normalized.prefix(3))
    }

    private func normalizeExamples(_ examples: [ImageTranslateExamplePayload]?) -> [ImageTranslateExample] {
        let normalized = (examples ?? []).compactMap { item -> ImageTranslateExample? in
            let source = item.source?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let translation = item.translation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !source.isEmpty, !translation.isEmpty else { return nil }
            return ImageTranslateExample(source: source, translation: translation)
        }

        return Array(normalized.prefix(2))
    }

    private func normalizeCollocations(_ collocations: [ImageTranslateCollocationPayload]?) -> [ImageTranslateCollocation] {
        let normalized = (collocations ?? []).compactMap { item -> ImageTranslateCollocation? in
            let phrase = item.phrase?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let translation = item.translation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let note = item.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !phrase.isEmpty, !translation.isEmpty else { return nil }
            return ImageTranslateCollocation(phrase: phrase, translation: translation, note: note)
        }

        return Array(normalized.prefix(3))
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

    private func translationSystemPrompt(isLexical: Bool) -> String {
        if isLexical {
            return """
            You are a fast dictionary-style translator. Return valid JSON only, no markdown.
            Schema:
            {
              "translation": "string",
              "notes": "string",
              "detected_source_language": "string",
              "meanings": [{"part_of_speech":"string","meaning":"string"}],
              "examples": [{"source":"string","translation":"string"}],
              "collocations": [{"phrase":"string","translation":"string","note":"string"}]
            }
            Rules:
            - Keep output compact. Prefer fewer high-value items over long lists.
            - meanings: up to 3 short senses (Chinese explanations unless target is English).
            - examples: up to 2 short practical sentences.
            - collocations: up to 3 common phrases; note may be empty.
            - notes: empty string unless there is real ambiguity.
            - detected_source_language: short label like English / Japanese.
            - Do not invent fields. Do not wrap JSON in code fences.
            """
        }

        return """
        You are a fast translation assistant. Return valid JSON only, no markdown.
        Schema:
        {
          "translation": "string",
          "notes": "string",
          "detected_source_language": "string",
          "meanings": [],
          "examples": [],
          "collocations": []
        }
        Rules:
        - translation is the complete polished result.
        - Keep meanings/examples/collocations as empty arrays for sentences/paragraphs.
        - notes: empty string unless OCR noise or terminology needs a short note.
        - detected_source_language: short label like English / Japanese.
        - Preserve proper nouns, numbers, code, and list structure when useful.
        - Do not wrap JSON in code fences.
        """
    }

    private var minimalSystemPrompt: String {
        """
        Translate text. Return valid JSON only:
        {"translation":"string","notes":"","detected_source_language":"string","meanings":[],"examples":[],"collocations":[]}
        """
    }

    private func initialUserPrompt(
        sourceText: String,
        targetLanguage: ImageTranslateTargetLanguage,
        isLexical: Bool
    ) -> String {
        if isLexical {
            return """
            Translate this word/phrase into \(targetLanguage.promptLabel). Return JSON only.
            Source: \(sourceText)
            Include compact meanings/examples/collocations as specified in the system rules.
            """
        }

        return """
        Translate into \(targetLanguage.promptLabel). Return JSON only.
        Source:
        \(sourceText)
        Keep meanings/examples/collocations empty arrays.
        """
    }

    private func followUpUserPrompt(
        sourceText: String,
        currentTranslation: String,
        transcript: String,
        latestUserPrompt: String,
        targetLanguage: ImageTranslateTargetLanguage,
        isLexical: Bool
    ) -> String {
        let transcriptBlock = transcript.isEmpty ? "(none)" : transcript
        let lexicalHint = isLexical
            ? "If still a word/phrase lookup, keep compact meanings/examples/collocations."
            : "Keep meanings/examples/collocations empty unless the user asks for dictionary detail."

        return """
        Continue translation work in \(targetLanguage.promptLabel). Return JSON only.
        Source:
        \(sourceText)
        Current translation:
        \(currentTranslation)
        Transcript:
        \(transcriptBlock)
        Latest request:
        \(latestUserPrompt)
        \(lexicalHint)
        """
    }

    private func minimalUserPrompt(
        sourceText: String,
        targetLanguage: ImageTranslateTargetLanguage
    ) -> String {
        """
        Translate into \(targetLanguage.promptLabel). JSON only with key translation.
        Source: \(sourceText)
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
