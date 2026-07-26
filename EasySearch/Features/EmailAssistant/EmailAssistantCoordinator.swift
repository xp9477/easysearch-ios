import Foundation

enum EmailAssistantError: LocalizedError {
    case missingAPIKey
    case emptyContext
    case emptyResponse
    case invalidResponse
    case serverError(String)
    case networkError(String)
    case imageLoadFailed
    case cropFailed
    case ocrFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "请先到设置页配置 AI API Key。"
        case .emptyContext:
            return "请先输入草稿、来信，或在下方写要求。"
        case .emptyResponse:
            return "AI 服务没有返回可用内容，请稍后再试。"
        case .invalidResponse:
            return "AI 服务返回了无法识别的结果。"
        case let .serverError(message):
            return message
        case let .networkError(message):
            return message
        case .imageLoadFailed:
            return "截图读取失败，请重新选择图片。"
        case .cropFailed:
            return "裁剪失败，请重试。"
        case let .ocrFailed(message):
            return "截图识别失败：\(message)"
        }
    }
}

actor EmailAssistantService {
    static let shared = EmailAssistantService()

    private let configurationStore: AIConfigurationStore
    private let client: DeepSeekClient

    private init(
        configurationStore: AIConfigurationStore = .shared,
        client: DeepSeekClient = .shared
    ) {
        self.configurationStore = configurationStore
        self.client = client
    }

    func generateReply(
        context: EmailAssistantContext,
        conversationHistory: [EmailAssistantThreadMessage],
        latestUserMessage: String
    ) async throws -> EmailAssistantStructuredOutput {
        guard context.hasUsableContent ||
                !conversationHistory.isEmpty ||
                !latestUserMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EmailAssistantError.emptyContext
        }

        let configuration = configurationStore.loadConfiguration()
        guard configuration.hasAPIKey else {
            throw EmailAssistantError.missingAPIKey
        }

        let messages = buildMessages(
            context: context,
            conversationHistory: conversationHistory,
            latestUserMessage: latestUserMessage
        )

        do {
            let content = try await client.completeText(
                configuration: configuration.deepSeekConfiguration,
                messages: messages,
                responseFormat: nil,
                temperature: 0.35,
                maxTokens: 2200
            )
            return try parseStructuredOutput(from: content)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as DeepSeekClientError {
            throw mapDeepSeekError(error)
        } catch let error as EmailAssistantError {
            throw error
        } catch {
            throw EmailAssistantError.networkError(error.localizedDescription)
        }
    }

    private func buildMessages(
        context: EmailAssistantContext,
        conversationHistory: [EmailAssistantThreadMessage],
        latestUserMessage: String
    ) -> [DeepSeekChatMessage] {
        let systemMessage = DeepSeekChatMessage(
            role: "system",
            content: Self.systemPrompt(for: context)
        )

        let historyMessages = Array(
            conversationHistory
                .filter { !$0.isPartial }
                .suffix(10)
        )
        .map { message in
            DeepSeekChatMessage(role: message.role.rawValue, content: message.transcriptContent)
        }

        let latestMessage = DeepSeekChatMessage(role: "user", content: latestUserMessage)
        return [systemMessage] + historyMessages + [latestMessage]
    }

    private static func systemPrompt(for context: EmailAssistantContext) -> String {
        """
        You are an email writing assistant inside an iOS app for Chinese-speaking users.
        Your job is to write practical English emails with high usability.

        Follow these rules strictly:
        1. Preserve facts, names, dates, commitments, numbers, and tone intent from the provided context.
        2. Write in English for the email itself.
        3. Follow this task rule exactly: \(context.modePromptInstruction)
        4. Keep the email aligned with this scenario: \(context.scenario.promptDescription).
        5. Use this tone: \(context.tone.promptDescription).
        6. Apply this length preference: \(context.length.promptDescription).
        7. Generate only one final email draft.
        8. Do not add explanations, options, or alternative versions.
        9. Do not use markdown code fences.
        10. Output only in the exact plain-text block format below.

        Required output format:
        [SUBJECT]
        <english subject line>
        [BODY]
        <english email body>

        Current context:
        \(context.serializedSummary)
        """
    }

    private func parseStructuredOutput(from rawText: String) throws -> EmailAssistantStructuredOutput {
        let sections = parseSections(from: rawText)

        let subject = normalizedSection(sections["SUBJECT"], fallback: sections["PRIMARY_SUBJECT"])
        let body = normalizedSection(sections["BODY"], fallback: sections["PRIMARY_BODY"])

        if subject.isEmpty && body.isEmpty {
            let fallback = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !fallback.isEmpty else {
                throw EmailAssistantError.emptyResponse
            }

            return EmailAssistantStructuredOutput(
                subject: inferredSubject(from: fallback),
                body: fallback
            )
        }

        return EmailAssistantStructuredOutput(
            subject: subject.isEmpty ? inferredSubject(from: body) : subject,
            body: body
        )
    }

    private func parseSections(from rawText: String) -> [String: String] {
        let markers = [
            "SUBJECT",
            "BODY",
            "PRIMARY_SUBJECT",
            "PRIMARY_BODY"
        ]

        var result: [String: String] = [:]
        for (index, marker) in markers.enumerated() {
            let startToken = "[\(marker)]"
            guard let startRange = rawText.range(of: startToken) else { continue }

            let contentStart = startRange.upperBound
            let endIndex: String.Index = {
                for nextMarker in markers.dropFirst(index + 1) {
                    if let nextRange = rawText.range(of: "[\(nextMarker)]", range: contentStart..<rawText.endIndex) {
                        return nextRange.lowerBound
                    }
                }
                return rawText.endIndex
            }()

            let content = String(rawText[contentStart..<endIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            result[marker] = content
        }

        return result
    }

    private func normalizedSection(_ value: String?, fallback: String? = nil) -> String {
        let primary = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !primary.isEmpty {
            return primary
        }
        return fallback?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func inferredSubject(from text: String) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = cleaned
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        return firstLine ?? ""
    }

    private func mapDeepSeekError(_ error: DeepSeekClientError) -> EmailAssistantError {
        switch error {
        case .missingAPIKey:
            return .missingAPIKey
        case .invalidResponse:
            return .invalidResponse
        case .emptyResponse:
            return .emptyResponse
        case let .serverError(message):
            return .serverError(message)
        case let .networkError(message):
            return .networkError(message)
        }
    }
}

enum EmailAssistantOCRService {
    static func extractText(from imageData: Data) async throws -> String {
        do {
            let result = try await ImageOCRService.extractText(
                from: imageData,
                recognitionLanguages: ["en-US", "zh-Hans", "zh-Hant"]
            )
            return result.fullText
        } catch let error as ImageTranslateError {
            switch error {
            case .noTextRecognized:
                throw EmailAssistantError.ocrFailed("没有识别到可用文字")
            case let .ocrFailure(message):
                throw EmailAssistantError.ocrFailed(message)
            default:
                throw EmailAssistantError.ocrFailed(error.localizedDescription)
            }
        } catch {
            throw EmailAssistantError.ocrFailed(error.localizedDescription)
        }
    }
}
