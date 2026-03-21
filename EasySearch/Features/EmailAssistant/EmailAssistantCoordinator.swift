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
            return "请先到设置页配置 DeepSeek API Key。"
        case .emptyContext:
            return "请先输入草稿、来信或要求。"
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
        case .cropFailed:
            return "裁剪失败，请重试。"
        case let .ocrFailed(message):
            return "截图识别失败：\(message)"
        }
    }
}

actor EmailAssistantService {
    static let shared = EmailAssistantService()

    private let configurationStore: ImageTranslateConfigurationStore
    private let client: DeepSeekClient

    private init(
        configurationStore: ImageTranslateConfigurationStore = .shared,
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
        guard context.hasUsableContent || !conversationHistory.isEmpty else {
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
        3. Keep the email aligned with this scenario: \(context.scenario.promptDescription).
        4. Use this tone: \(context.tone.promptDescription).
        5. Apply this length preference: \(context.length.promptDescription).
        6. Generate one primary email and exactly two alternatives with visibly different tones or strategies.
        7. Do not use markdown code fences.
        8. Output only in the exact plain-text block format below.

        Required output format:
        [PRIMARY_SUBJECT]
        <english subject line>
        [PRIMARY_BODY]
        <english email body>
        [EXPLANATION]
        <1-2 short Chinese sentences explaining why this draft works>
        [ALTERNATIVE_1_TITLE]
        <short Chinese label such as 更正式 / 更直接 / 更友好>
        [ALTERNATIVE_1_SUBJECT]
        <english subject line>
        [ALTERNATIVE_1_BODY]
        <english email body>
        [ALTERNATIVE_2_TITLE]
        <short Chinese label>
        [ALTERNATIVE_2_SUBJECT]
        <english subject line>
        [ALTERNATIVE_2_BODY]
        <english email body>

        Current context:
        \(context.serializedSummary)
        """
    }

    private func parseStructuredOutput(from rawText: String) throws -> EmailAssistantStructuredOutput {
        let sections = parseSections(from: rawText)

        let primarySubject = normalizedSection(sections["PRIMARY_SUBJECT"])
        let primaryBody = normalizedSection(sections["PRIMARY_BODY"])
        let explanation = normalizedSection(sections["EXPLANATION"])

        if primarySubject.isEmpty && primaryBody.isEmpty {
            let fallback = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !fallback.isEmpty else {
                throw EmailAssistantError.emptyResponse
            }

            return EmailAssistantStructuredOutput(
                subject: inferredSubject(from: fallback),
                body: fallback,
                explanation: "模型没有完全按约定格式返回，这里保留了原始结果供你继续修改。",
                alternatives: []
            )
        }

        let alternatives = [
            makeAlternative(
                title: normalizedSection(sections["ALTERNATIVE_1_TITLE"]),
                subject: normalizedSection(sections["ALTERNATIVE_1_SUBJECT"]),
                body: normalizedSection(sections["ALTERNATIVE_1_BODY"]),
                fallbackTitle: "更正式"
            ),
            makeAlternative(
                title: normalizedSection(sections["ALTERNATIVE_2_TITLE"]),
                subject: normalizedSection(sections["ALTERNATIVE_2_SUBJECT"]),
                body: normalizedSection(sections["ALTERNATIVE_2_BODY"]),
                fallbackTitle: "更直接"
            )
        ]
        .compactMap { $0 }

        return EmailAssistantStructuredOutput(
            subject: primarySubject.isEmpty ? inferredSubject(from: primaryBody) : primarySubject,
            body: primaryBody,
            explanation: explanation,
            alternatives: alternatives
        )
    }

    private func parseSections(from rawText: String) -> [String: String] {
        let markers = [
            "PRIMARY_SUBJECT",
            "PRIMARY_BODY",
            "EXPLANATION",
            "ALTERNATIVE_1_TITLE",
            "ALTERNATIVE_1_SUBJECT",
            "ALTERNATIVE_1_BODY",
            "ALTERNATIVE_2_TITLE",
            "ALTERNATIVE_2_SUBJECT",
            "ALTERNATIVE_2_BODY"
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

    private func normalizedSection(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func inferredSubject(from text: String) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = cleaned
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        return firstLine ?? ""
    }

    private func makeAlternative(
        title: String,
        subject: String,
        body: String,
        fallbackTitle: String
    ) -> EmailAssistantDraftVariant? {
        guard !subject.isEmpty || !body.isEmpty else { return nil }
        return EmailAssistantDraftVariant(
            title: title.isEmpty ? fallbackTitle : title,
            subject: subject.isEmpty ? inferredSubject(from: body) : subject,
            body: body
        )
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
