import Foundation

struct DeepSeekClientConfiguration: Equatable {
    let apiKey: String
    let model: String

    var hasAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var resolvedModel: String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "deepseek-chat" : trimmed
    }
}

enum DeepSeekClientError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case emptyResponse
    case serverError(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "请先配置 DeepSeek API Key。"
        case .invalidResponse:
            return "DeepSeek 返回了无法识别的结果。"
        case .emptyResponse:
            return "DeepSeek 没有返回有效内容，请稍后再试。"
        case let .serverError(message):
            return message
        case let .networkError(message):
            return message
        }
    }
}

struct DeepSeekChatMessage: Encodable {
    let role: String
    let content: String
}

struct DeepSeekResponseFormat: Encodable {
    let type: String

    static let text = DeepSeekResponseFormat(type: "text")
    static let jsonObject = DeepSeekResponseFormat(type: "json_object")
}

private struct DeepSeekStreamOptions: Encodable {
    let includeUsage: Bool
}

private struct DeepSeekChatCompletionRequest: Encodable {
    let model: String
    let messages: [DeepSeekChatMessage]
    let responseFormat: DeepSeekResponseFormat?
    let temperature: Double?
    let maxTokens: Int?
    let stream: Bool
    let streamOptions: DeepSeekStreamOptions?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case responseFormat = "response_format"
        case temperature
        case maxTokens = "max_tokens"
        case stream
        case streamOptions = "stream_options"
    }
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

private struct DeepSeekStreamingResponse: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
        }

        let delta: Delta?
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    let choices: [Choice]
}

private struct DeepSeekErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String?
    }

    let error: APIError?
    let message: String?
}

actor DeepSeekClient {
    static let shared = DeepSeekClient()

    private let urlSession: URLSession
    private let decoder = JSONDecoder()
    private let endpoint = URL(string: "https://api.deepseek.com/chat/completions")!

    private init(urlSession: URLSession? = nil) {
        if let urlSession {
            self.urlSession = urlSession
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 120
            configuration.urlCache = nil
            self.urlSession = URLSession(configuration: configuration)
        }
    }

    func completeText(
        configuration: DeepSeekClientConfiguration,
        messages: [DeepSeekChatMessage],
        responseFormat: DeepSeekResponseFormat? = nil,
        temperature: Double? = nil,
        maxTokens: Int? = nil
    ) async throws -> String {
        let request = try makeRequest(
            configuration: configuration,
            messages: messages,
            responseFormat: responseFormat,
            temperature: temperature,
            maxTokens: maxTokens,
            stream: false
        )

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw DeepSeekClientError.networkError(error.localizedDescription)
        }

        try validate(response: response, data: data)

        let payload: DeepSeekChatCompletionResponse
        do {
            payload = try decoder.decode(DeepSeekChatCompletionResponse.self, from: data)
        } catch {
            throw mapDecodingError(error, payload: data)
        }

        guard let content = payload.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw DeepSeekClientError.emptyResponse
        }

        return content
    }

    func streamText(
        configuration: DeepSeekClientConfiguration,
        messages: [DeepSeekChatMessage],
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        let request = try makeRequest(
            configuration: configuration,
            messages: messages,
            responseFormat: nil,
            temperature: temperature,
            maxTokens: maxTokens,
            stream: true
        )

        let bytes: URLSession.AsyncBytes
        let response: URLResponse

        do {
            (bytes, response) = try await urlSession.bytes(for: request)
        } catch {
            throw DeepSeekClientError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeepSeekClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
            }
            throw serverError(from: data, statusCode: httpResponse.statusCode)
        }

        var collectedText = ""
        var eventDataLines: [String] = []

        for try await line in bytes.lines {
            try Task.checkCancellation()

            let trimmedLine = line.trimmingCharacters(in: .newlines)

            if trimmedLine.isEmpty {
                try processStreamEvent(
                    dataLines: &eventDataLines,
                    collectedText: &collectedText,
                    onDelta: onDelta
                )
                continue
            }

            if trimmedLine.hasPrefix(":") {
                continue
            }

            if trimmedLine.hasPrefix("data:") {
                let content = String(trimmedLine.dropFirst("data:".count))
                    .trimmingCharacters(in: .whitespaces)
                eventDataLines.append(content)
            }
        }

        if !eventDataLines.isEmpty {
            try processStreamEvent(
                dataLines: &eventDataLines,
                collectedText: &collectedText,
                onDelta: onDelta
            )
        }

        let trimmed = collectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DeepSeekClientError.emptyResponse
        }

        return trimmed
    }

    private func makeRequest(
        configuration: DeepSeekClientConfiguration,
        messages: [DeepSeekChatMessage],
        responseFormat: DeepSeekResponseFormat?,
        temperature: Double?,
        maxTokens: Int?,
        stream: Bool
    ) throws -> URLRequest {
        let apiKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw DeepSeekClientError.missingAPIKey
        }

        let payload = DeepSeekChatCompletionRequest(
            model: configuration.resolvedModel,
            messages: messages,
            responseFormat: responseFormat,
            temperature: temperature,
            maxTokens: maxTokens,
            stream: stream,
            streamOptions: stream ? DeepSeekStreamOptions(includeUsage: false) : nil
        )

        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeepSeekClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw serverError(from: data, statusCode: httpResponse.statusCode)
        }
    }

    private func processStreamEvent(
        dataLines: inout [String],
        collectedText: inout String,
        onDelta: @escaping @Sendable (String) -> Void
    ) throws {
        guard !dataLines.isEmpty else { return }
        defer { dataLines.removeAll(keepingCapacity: true) }

        let payload = dataLines.joined(separator: "\n")
        guard payload != "[DONE]" else { return }

        guard let data = payload.data(using: .utf8) else {
            throw DeepSeekClientError.invalidResponse
        }

        let chunk: DeepSeekStreamingResponse
        do {
            chunk = try decoder.decode(DeepSeekStreamingResponse.self, from: data)
        } catch {
            throw mapDecodingError(error, payload: data)
        }

        for choice in chunk.choices {
            if let content = choice.delta?.content, !content.isEmpty {
                collectedText += content
                onDelta(content)
            }
        }
    }

    private func mapDecodingError(_ error: Error, payload: Data) -> DeepSeekClientError {
        if error is DecodingError {
            return invalidResponse(from: payload)
        }

        return .invalidResponse
    }

    private func invalidResponse(from data: Data) -> DeepSeekClientError {
        if let payload = try? decoder.decode(DeepSeekErrorEnvelope.self, from: data) {
            if let message = payload.error?.message?.trimmingCharacters(in: .whitespacesAndNewlines),
               !message.isEmpty {
                return .serverError(message)
            }

            if let message = payload.message?.trimmingCharacters(in: .whitespacesAndNewlines),
               !message.isEmpty {
                return .serverError(message)
            }
        }

        let preview = responsePreview(from: data)
        guard !preview.isEmpty else {
            return .invalidResponse
        }

        return .serverError("DeepSeek 返回了无法识别的结果：\(preview)")
    }

    private func serverError(from data: Data, statusCode: Int) -> DeepSeekClientError {
        if let payload = try? decoder.decode(DeepSeekErrorEnvelope.self, from: data) {
            if let message = payload.error?.message?.trimmingCharacters(in: .whitespacesAndNewlines),
               !message.isEmpty {
                return .serverError(message)
            }

            if let message = payload.message?.trimmingCharacters(in: .whitespacesAndNewlines),
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

    private func responsePreview(from data: Data?) -> String {
        guard let data,
              let rawText = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !rawText.isEmpty else {
            return ""
        }

        let singleLine = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: " ")

        return String(singleLine.prefix(180))
    }
}
