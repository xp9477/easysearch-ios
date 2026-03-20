import Foundation
import Vision

struct EmailAssistantConfigurationState: Equatable {
    let hasAPIKey: Bool
    let keySummary: String?
}

enum EmailAssistantError: LocalizedError {
    case missingAPIKey
    case emptyContext
    case emptyResponse
    case invalidResponse
    case serverError(String)
    case networkError(String)
    case imageLoadFailed
    case ocrFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "请先到设置页或当前模块里配置 DeepSeek API Key。"
        case .emptyContext:
            return "请先输入草稿、来信内容、截图文字或补充要求。"
        case .emptyResponse:
            return "DeepSeek 没有返回可用内容，请稍后再试。"
        case .invalidResponse:
            return "DeepSeek 返回了无法识别的结果。"
        case let .serverError(message):
            return message
        case let .networkError(message):
            return message
        case .imageLoadFailed:
            return "截图读取失败，请重新选择图片。"
        case let .ocrFailed(message):
            return "截图识别失败：\(message)"
        }
    }
}

private struct DeepSeekChatCompletionRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
    let stream: Bool
}

private struct DeepSeekChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message
    }

    let choices: [Choice]
}

private struct DeepSeekErrorEnvelope: Decodable {
    struct DeepSeekErrorPayload: Decodable {
        let message: String?
    }

    let error: DeepSeekErrorPayload?
    let message: String?
}

actor EmailAssistantService {
    static let shared = EmailAssistantService()

    private let configurationStore: ImageTranslateConfigurationStore
    private let urlSession: URLSession
    private let endpoint = URL(string: "https://api.deepseek.com/chat/completions")!

    private init(
        configurationStore: ImageTranslateConfigurationStore = .shared,
        urlSession: URLSession? = nil
    ) {
        self.configurationStore = configurationStore

        if let urlSession {
            self.urlSession = urlSession
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 90
            configuration.urlCache = nil
            self.urlSession = URLSession(configuration: configuration)
        }
    }

    func loadConfigurationState() -> EmailAssistantConfigurationState {
        let configuration = configurationStore.loadConfiguration()
        let trimmed = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return EmailAssistantConfigurationState(hasAPIKey: false, keySummary: nil)
        }

        let suffix = String(trimmed.suffix(min(4, trimmed.count)))
        return EmailAssistantConfigurationState(
            hasAPIKey: true,
            keySummary: "已保存 API Key，尾号 \(suffix)，模型 \(configuration.resolvedModel)"
        )
    }

    func saveAPIKey(_ rawValue: String) throws {
        let configuration = configurationStore.loadConfiguration()
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        try configurationStore.saveConfiguration(
            apiKey: trimmed,
            model: configuration.resolvedModel,
            targetLanguage: configuration.targetLanguage
        )
    }

    func clearAPIKey() throws {
        let configuration = configurationStore.loadConfiguration()
        try configurationStore.saveConfiguration(
            apiKey: "",
            model: configuration.resolvedModel,
            targetLanguage: configuration.targetLanguage
        )
    }

    func generateReply(
        context: EmailAssistantContext,
        conversationHistory: [EmailAssistantThreadMessage],
        latestUserMessage: String
    ) async throws -> String {
        guard context.hasUsableContent || !conversationHistory.isEmpty else {
            throw EmailAssistantError.emptyContext
        }

        let configuration = configurationStore.loadConfiguration()
        let apiKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw EmailAssistantError.missingAPIKey
        }

        let systemPrompt = Self.systemPrompt(for: context)
        let trimmedHistory = Array(conversationHistory.suffix(10))
        let messages = [DeepSeekChatCompletionRequest.Message(role: "system", content: systemPrompt)]
            + trimmedHistory.map {
                DeepSeekChatCompletionRequest.Message(role: $0.role.rawValue, content: $0.content)
            }
            + [DeepSeekChatCompletionRequest.Message(role: "user", content: latestUserMessage)]

        let payload = DeepSeekChatCompletionRequest(
            model: configuration.resolvedModel,
            messages: messages,
            temperature: 0.35,
            stream: false
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw EmailAssistantError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EmailAssistantError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw Self.serverError(from: data, statusCode: httpResponse.statusCode)
        }

        let completion = try JSONDecoder().decode(DeepSeekChatCompletionResponse.self, from: data)
        guard let content = completion.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw EmailAssistantError.emptyResponse
        }

        return content
    }

    private static func systemPrompt(for context: EmailAssistantContext) -> String {
        """
        You are an email writing assistant inside an iOS app for Chinese-speaking users.
        Help the user write concise, practical, natural English emails.
        Prefer short paragraphs and direct wording.
        Preserve facts, names, dates, numbers, commitments, and intent from the provided context.
        If the user shared a received email, infer the safest reasonable reply and keep assumptions minimal.
        When revising follow-up turns, update the latest draft based on the conversation history.
        Unless the user explicitly asks for explanation, alternatives, or analysis, return only the final English email content that is ready to send.
        Avoid markdown fences.

        Current context:
        \(context.serializedSummary)
        """
    }

    private static func serverError(from data: Data, statusCode: Int) -> EmailAssistantError {
        if let envelope = try? JSONDecoder().decode(DeepSeekErrorEnvelope.self, from: data) {
            if let message = envelope.error?.message?.trimmingCharacters(in: .whitespacesAndNewlines),
               !message.isEmpty {
                return .serverError(message)
            }

            if let message = envelope.message?.trimmingCharacters(in: .whitespacesAndNewlines),
               !message.isEmpty {
                return .serverError(message)
            }
        }

        if let message = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            return .serverError("DeepSeek 请求失败（\(statusCode)）：\(message)")
        }

        return .serverError("DeepSeek 请求失败，状态码 \(statusCode)。")
    }
}

enum EmailAssistantOCRService {
    static func extractText(from imageData: Data) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: EmailAssistantError.ocrFailed(error.localizedDescription))
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                guard !text.isEmpty else {
                    continuation.resume(throwing: EmailAssistantError.ocrFailed("没有识别到可用文字"))
                    return
                }

                continuation.resume(returning: text)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US", "zh-Hans"]

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let handler = VNImageRequestHandler(data: imageData, options: [:])
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: EmailAssistantError.ocrFailed(error.localizedDescription))
                }
            }
        }
    }
}
