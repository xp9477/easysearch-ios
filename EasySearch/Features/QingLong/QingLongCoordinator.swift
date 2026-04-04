import Foundation
import Security

struct QingLongStoredConfiguration {
    let profile: QingLongPanelProfile?
    let clientID: String
    let clientSecret: String
}

struct QingLongDiagnosticStep: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let url: String
    let httpStatus: Int?
    let isSuccess: Bool
    let summary: String
    let preview: String
}

struct QingLongDiagnosticReport: Identifiable, Hashable {
    let id = UUID()
    let baseURL: String
    let generatedAt: Date
    let steps: [QingLongDiagnosticStep]
}

struct QingLongScriptFile: Hashable {
    let path: String?
    let fileName: String
    let content: String
}

enum QingLongError: LocalizedError {
    case emptyBaseURL
    case invalidBaseURL
    case missingCredentials
    case missingConfiguration
    case missingScriptReference
    case invalidResponse
    case keychainFailure(OSStatus)
    case serverError(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .emptyBaseURL:
            return "请先填写青龙面板地址。"
        case .invalidBaseURL:
            return "青龙面板地址格式不正确，请使用域名或 IP。"
        case .missingCredentials:
            return "请填写 client_id 和 client_secret。"
        case .missingConfiguration:
            return "还没有保存青龙面板配置。"
        case .missingScriptReference:
            return "当前任务未识别到脚本文件。"
        case .invalidResponse:
            return "青龙面板返回了无法识别的结果。"
        case let .keychainFailure(status):
            return "保存密钥失败，Keychain 状态码 \(status)。"
        case let .serverError(message):
            return message
        case let .networkError(message):
            return message
        }
    }
}

private struct QingLongCredentials: Codable, Hashable {
    let clientID: String
    let clientSecret: String
}

private struct QingLongEnvironmentPayload: Encodable {
    let id: Int?
    let name: String
    let value: String
    let remarks: String
}

private struct QingLongCronPayload: Encodable {
    let id: Int
    let command: String
    let schedule: String
    let name: String?
    let labels: [String]?
    let extraSchedules: [QingLongCron.ExtraSchedule]?

    enum CodingKeys: String, CodingKey {
        case id
        case command
        case schedule
        case name
        case labels
        case extraSchedules = "extra_schedules"
    }
}

private struct QingLongSession: Hashable {
    let token: String
    let expiration: Date
    let baseURL: URL
    let clientID: String
}

private struct QingLongAPIEnvelope<T: Decodable>: Decodable {
    let code: Int?
    let data: T?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case code
        case data
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decodeLossyIntIfPresent(forKey: .code)
        data = try container.decodeIfPresent(T.self, forKey: .data)
        message = try container.decodeIfPresent(String.self, forKey: .message)
    }
}

private struct QingLongAPIStatusEnvelope: Decodable {
    let code: Int?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case code
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decodeLossyIntIfPresent(forKey: .code)
        message = try container.decodeIfPresent(String.self, forKey: .message)
    }
}

private struct QingLongListPayload<T: Decodable>: Decodable {
    let items: [T]

    enum CodingKeys: String, CodingKey {
        case data
        case items
        case list
        case records
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let items = try container.decodeIfPresent([T].self, forKey: .data) {
            self.items = items
            return
        }

        if let items = try container.decodeIfPresent([T].self, forKey: .items) {
            self.items = items
            return
        }

        if let items = try container.decodeIfPresent([T].self, forKey: .list) {
            self.items = items
            return
        }

        if let items = try container.decodeIfPresent([T].self, forKey: .records) {
            self.items = items
            return
        }

        throw DecodingError.dataCorruptedError(forKey: .data, in: container, debugDescription: "Expected list payload.")
    }
}

private struct QingLongTokenPayload: Decodable {
    let token: String
    let tokenType: String?
    let expiration: Int64?

    enum CodingKeys: String, CodingKey {
        case token
        case tokenType = "token_type"
        case expiration
    }
}

private struct QingLongKeychainStore {
    private let service = "com.easysearch.qinglong"
    private let account = "panel.credentials.v1"

    func loadCredentials() throws -> QingLongCredentials? {
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
              let credentials = try? JSONDecoder().decode(QingLongCredentials.self, from: data) else {
            throw QingLongError.keychainFailure(status)
        }

        return credentials
    }

    func saveCredentials(_ credentials: QingLongCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
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
            throw QingLongError.keychainFailure(status)
        }
    }

    func deleteCredentials() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

actor QingLongService {
    static let shared = QingLongService()

    private let store: any QingLongPanelStore
    private let keychainStore: QingLongKeychainStore
    private let urlSession: URLSession
    private let decoder = JSONDecoder()
    private var cachedSession: QingLongSession?

    private init(
        store: any QingLongPanelStore = QingLongPanelLocalStore(),
        keychainStore: QingLongKeychainStore = QingLongKeychainStore(),
        urlSession: URLSession? = nil
    ) {
        self.store = store
        self.keychainStore = keychainStore

        if let urlSession {
            self.urlSession = urlSession
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 30
            self.urlSession = URLSession(configuration: configuration)
        }
    }

    func loadStoredConfiguration() -> QingLongStoredConfiguration {
        let profile = store.loadProfile()
        let credentials = try? keychainStore.loadCredentials()
        return QingLongStoredConfiguration(
            profile: profile,
            clientID: credentials?.clientID ?? "",
            clientSecret: credentials?.clientSecret ?? ""
        )
    }

    func connect(baseURLString: String, clientID: String, clientSecret: String) async throws -> QingLongDashboardSnapshot {
        let normalizedBaseURL = try Self.normalizedBaseURL(from: baseURLString)
        let trimmedClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedClientSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedClientID.isEmpty, !trimmedClientSecret.isEmpty else {
            throw QingLongError.missingCredentials
        }

        let credentials = QingLongCredentials(clientID: trimmedClientID, clientSecret: trimmedClientSecret)
        let session = try await authorize(baseURL: normalizedBaseURL, credentials: credentials, forceRefresh: true)
        let fetchedAt = Date()
        async let environments = fetchEnvironments(baseURL: normalizedBaseURL, session: session)
        async let crons = fetchCrons(baseURL: normalizedBaseURL, session: session)
        async let subscriptions = fetchSubscriptions(baseURL: normalizedBaseURL, session: session)

        let profile = QingLongPanelProfile(
            baseURL: normalizedBaseURL,
            displayName: Self.displayName(for: normalizedBaseURL),
            savedAt: fetchedAt,
            lastConnectedAt: fetchedAt
        )

        let snapshot = QingLongDashboardSnapshot(
            profile: profile,
            environments: try await environments,
            crons: try await crons,
            subscriptions: try await subscriptions,
            fetchedAt: fetchedAt
        )

        try keychainStore.saveCredentials(credentials)
        store.saveProfile(profile, postsNotification: true)
        cachedSession = session
        return snapshot
    }

    func diagnoseConnection(baseURLString: String, clientID: String, clientSecret: String) async throws -> QingLongDiagnosticReport {
        let normalizedBaseURL = try Self.normalizedBaseURL(from: baseURLString)
        let trimmedClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedClientSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedClientID.isEmpty, !trimmedClientSecret.isEmpty else {
            throw QingLongError.missingCredentials
        }

        let credentials = QingLongCredentials(clientID: trimmedClientID, clientSecret: trimmedClientSecret)
        var steps: [QingLongDiagnosticStep] = []

        var components = URLComponents(url: openBaseURL(for: normalizedBaseURL).appendingPathComponent("auth/token"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: credentials.clientID),
            URLQueryItem(name: "client_secret", value: credentials.clientSecret)
        ]

        guard let tokenURL = components?.url else {
            throw QingLongError.invalidBaseURL
        }

        var tokenRequest = URLRequest(url: tokenURL)
        tokenRequest.httpMethod = "GET"
        tokenRequest.timeoutInterval = 20

        let tokenProbe = await probeRequest(tokenRequest)
        let tokenStep = makeDiagnosticStep(title: "获取 Token", url: tokenURL, probe: tokenProbe)
        steps.append(tokenStep)

        guard let tokenData = tokenProbe.data,
              tokenProbe.statusCode.map({ (200..<300).contains($0) }) == true else {
            return QingLongDiagnosticReport(baseURL: normalizedBaseURL.absoluteString, generatedAt: Date(), steps: steps)
        }

        let tokenPayload: QingLongTokenPayload
        do {
            tokenPayload = try decodeEnvelopeData(tokenData, as: QingLongTokenPayload.self)
        } catch {
            steps.append(
                QingLongDiagnosticStep(
                    title: "Token 解析",
                    url: tokenURL.absoluteString,
                    httpStatus: tokenProbe.statusCode,
                    isSuccess: false,
                    summary: error.localizedDescription,
                    preview: responsePreview(from: tokenData)
                )
            )
            return QingLongDiagnosticReport(baseURL: normalizedBaseURL.absoluteString, generatedAt: Date(), steps: steps)
        }

        let token = tokenPayload.token
        let envRequest = try makeRequest(
            baseURL: normalizedBaseURL,
            token: token,
            path: ["envs"],
            method: "GET"
        )
        let envProbe = await probeRequest(envRequest)
        steps.append(makeDiagnosticStep(title: "读取环境变量", url: envRequest.url, probe: envProbe))

        let cronRequest = try makeRequest(
            baseURL: normalizedBaseURL,
            token: token,
            path: ["crons"],
            method: "GET"
        )
        let cronProbe = await probeRequest(cronRequest)
        steps.append(makeDiagnosticStep(title: "读取定时任务", url: cronRequest.url, probe: cronProbe))

        let subscriptionRequest = try makeRequest(
            baseURL: normalizedBaseURL,
            token: token,
            path: ["subscriptions"],
            method: "GET"
        )
        let subscriptionProbe = await probeRequest(subscriptionRequest)
        steps.append(makeDiagnosticStep(title: "读取订阅", url: subscriptionRequest.url, probe: subscriptionProbe))

        return QingLongDiagnosticReport(baseURL: normalizedBaseURL.absoluteString, generatedAt: Date(), steps: steps)
    }

    func refreshDashboard() async throws -> QingLongDashboardSnapshot {
        guard let profile = store.loadProfile() else {
            throw QingLongError.missingConfiguration
        }

        guard let credentials = try keychainStore.loadCredentials() else {
            throw QingLongError.missingConfiguration
        }

        let session = try await authorize(baseURL: profile.baseURL, credentials: credentials)
        let fetchedAt = Date()
        async let environments = fetchEnvironments(baseURL: profile.baseURL, session: session)
        async let crons = fetchCrons(baseURL: profile.baseURL, session: session)
        async let subscriptions = fetchSubscriptions(baseURL: profile.baseURL, session: session)

        let updatedProfile = profile.updatingConnection(at: fetchedAt)
        let snapshot = QingLongDashboardSnapshot(
            profile: updatedProfile,
            environments: try await environments,
            crons: try await crons,
            subscriptions: try await subscriptions,
            fetchedAt: fetchedAt
        )

        store.saveProfile(updatedProfile, postsNotification: false)
        return snapshot
    }

    func disconnect() {
        keychainStore.deleteCredentials()
        store.deleteProfile()
        cachedSession = nil
    }

    func setEnvironmentEnabled(id: Int, enabled: Bool) async throws {
        try await performEnvironmentAction(path: enabled ? "enable" : "disable", ids: [id])
    }

    func createEnvironment(name: String, value: String, remarks: String) async throws -> QingLongEnvironment {
        let context = try await authenticatedContext()
        let payload = [QingLongEnvironmentPayload(id: nil, name: name, value: value, remarks: remarks)]
        let request = try makeRequest(
            baseURL: context.profile.baseURL,
            token: context.session.token,
            path: ["envs"],
            method: "POST",
            body: payload
        )
        return try await sendEnvironmentMutationRequest(request)
    }

    func updateEnvironment(id: Int, name: String, value: String, remarks: String) async throws -> QingLongEnvironment {
        let context = try await authenticatedContext()
        let payload = QingLongEnvironmentPayload(id: id, name: name, value: value, remarks: remarks)
        let request = try makeRequest(
            baseURL: context.profile.baseURL,
            token: context.session.token,
            path: ["envs"],
            method: "PUT",
            body: payload
        )
        return try await sendEnvironmentMutationRequest(request)
    }

    func runCron(id: Int) async throws {
        try await performCronAction(path: "run", ids: [id])
    }

    func stopCron(id: Int) async throws {
        try await performCronAction(path: "stop", ids: [id])
    }

    func setCronEnabled(id: Int, enabled: Bool) async throws {
        try await performCronAction(path: enabled ? "enable" : "disable", ids: [id])
    }

    func runSubscription(id: Int) async throws {
        try await performSubscriptionAction(path: "run", ids: [id])
    }

    func stopSubscription(id: Int) async throws {
        try await performSubscriptionAction(path: "stop", ids: [id])
    }

    func setSubscriptionEnabled(id: Int, enabled: Bool) async throws {
        try await performSubscriptionAction(path: enabled ? "enable" : "disable", ids: [id])
    }

    func updateCron(_ cron: QingLongCron, schedule: String) async throws {
        let context = try await authenticatedContext()
        let payload = QingLongCronPayload(
            id: cron.id,
            command: cron.command,
            schedule: schedule,
            name: cron.name.isEmpty ? nil : cron.name,
            labels: cron.labels.isEmpty ? nil : cron.labels,
            extraSchedules: cron.extraSchedules.isEmpty ? nil : cron.extraSchedules
        )
        let request = try makeRequest(
            baseURL: context.profile.baseURL,
            token: context.session.token,
            path: ["crons"],
            method: "PUT",
            body: payload
        )
        try await sendStatusRequest(request)
    }

    func fetchCronLog(id: Int) async throws -> String {
        let context = try await authenticatedContext()
        let request = try makeRequest(
            baseURL: context.profile.baseURL,
            token: context.session.token,
            path: ["crons", "\(id)", "log"],
            method: "GET"
        )
        let logText = try await sendEnvelopeRequest(request, decodeAs: String.self)
        return logText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }

    func fetchSubscriptionLog(id: Int) async throws -> String {
        let context = try await authenticatedContext()
        let request = try makeRequest(
            baseURL: context.profile.baseURL,
            token: context.session.token,
            path: ["subscriptions", "\(id)", "log"],
            method: "GET"
        )
        let logText = try await sendEnvelopeRequest(request, decodeAs: String.self)
        return logText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }

    func fetchScriptFile(path: String?, fileName: String) async throws -> QingLongScriptFile {
        let context = try await authenticatedContext()
        let request = try makeRequest(
            baseURL: context.profile.baseURL,
            token: context.session.token,
            path: ["scripts", "detail"],
            method: "GET",
            queryItems: [
                URLQueryItem(name: "path", value: path),
                URLQueryItem(name: "file", value: fileName)
            ]
        )
        let content = try await sendEnvelopeRequest(request, decodeAs: String.self)
        return QingLongScriptFile(path: path, fileName: fileName, content: content)
    }

    private func fetchEnvironments(baseURL: URL, session: QingLongSession) async throws -> [QingLongEnvironment] {
        let request = try makeRequest(
            baseURL: baseURL,
            token: session.token,
            path: ["envs"],
            method: "GET"
        )
        let environments = try await sendListEnvelopeRequest(request, decodeAs: QingLongEnvironment.self)
        return environments.sorted(by: QingLongEnvironment.sort(lhs:rhs:))
    }

    private func fetchCrons(baseURL: URL, session: QingLongSession) async throws -> [QingLongCron] {
        let request = try makeRequest(
            baseURL: baseURL,
            token: session.token,
            path: ["crons"],
            method: "GET"
        )
        let crons = try await sendListEnvelopeRequest(request, decodeAs: QingLongCron.self)
        return crons.sorted(by: QingLongCron.sort(lhs:rhs:))
    }

    private func fetchSubscriptions(baseURL: URL, session: QingLongSession) async throws -> [QingLongSubscription] {
        let request = try makeRequest(
            baseURL: baseURL,
            token: session.token,
            path: ["subscriptions"],
            method: "GET"
        )
        let subscriptions = try await sendListEnvelopeRequest(request, decodeAs: QingLongSubscription.self)
        return subscriptions.sorted(by: QingLongSubscription.sort(lhs:rhs:))
    }

    private func performEnvironmentAction(path: String, ids: [Int]) async throws {
        let context = try await authenticatedContext()
        let request = try makeRequest(
            baseURL: context.profile.baseURL,
            token: context.session.token,
            path: ["envs", path],
            method: "PUT",
            body: ids
        )
        try await sendStatusRequest(request)
    }

    private func performCronAction(path: String, ids: [Int]) async throws {
        let context = try await authenticatedContext()
        let request = try makeRequest(
            baseURL: context.profile.baseURL,
            token: context.session.token,
            path: ["crons", path],
            method: "PUT",
            body: ids
        )
        try await sendStatusRequest(request)
    }

    private func performSubscriptionAction(path: String, ids: [Int]) async throws {
        let context = try await authenticatedContext()
        let request = try makeRequest(
            baseURL: context.profile.baseURL,
            token: context.session.token,
            path: ["subscriptions", path],
            method: "PUT",
            body: ids
        )
        try await sendStatusRequest(request)
    }

    private func authenticatedContext() async throws -> (profile: QingLongPanelProfile, session: QingLongSession) {
        guard let profile = store.loadProfile() else {
            throw QingLongError.missingConfiguration
        }

        guard let credentials = try keychainStore.loadCredentials() else {
            throw QingLongError.missingConfiguration
        }

        let session = try await authorize(baseURL: profile.baseURL, credentials: credentials)
        return (profile, session)
    }

    private func authorize(
        baseURL: URL,
        credentials: QingLongCredentials,
        forceRefresh: Bool = false
    ) async throws -> QingLongSession {
        let refreshLeeway: TimeInterval = 60
        if !forceRefresh,
           let cachedSession,
           cachedSession.baseURL == baseURL,
           cachedSession.clientID == credentials.clientID,
           cachedSession.expiration.timeIntervalSinceNow > refreshLeeway {
            return cachedSession
        }

        var components = URLComponents(url: openBaseURL(for: baseURL).appendingPathComponent("auth/token"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: credentials.clientID),
            URLQueryItem(name: "client_secret", value: credentials.clientSecret)
        ]

        guard let tokenURL = components?.url else {
            throw QingLongError.invalidBaseURL
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 20

        let payload = try await sendEnvelopeRequest(request, decodeAs: QingLongTokenPayload.self)
        let expiration = payload.expiration.flatMap(Self.dateFromUnixLikeValue(_:)) ?? Date().addingTimeInterval(29 * 24 * 60 * 60)

        let session = QingLongSession(
            token: payload.token,
            expiration: expiration,
            baseURL: baseURL,
            clientID: credentials.clientID
        )
        cachedSession = session
        return session
    }

    private func makeRequest(
        baseURL: URL,
        token: String,
        path: [String],
        method: String,
        queryItems: [URLQueryItem]? = nil
    ) throws -> URLRequest {
        let url = path.reduce(openBaseURL(for: baseURL)) { partialURL, component in
            partialURL.appendingPathComponent(component)
        }

        let resolvedURL: URL
        if let queryItems, !queryItems.isEmpty {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                throw QingLongError.invalidBaseURL
            }
            components.queryItems = queryItems.filter { $0.value != nil }
            guard let urlWithQuery = components.url else {
                throw QingLongError.invalidBaseURL
            }
            resolvedURL = urlWithQuery
        } else {
            resolvedURL = url
        }

        var request = URLRequest(url: resolvedURL)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func makeRequest<T: Encodable>(
        baseURL: URL,
        token: String,
        path: [String],
        method: String,
        body: T
    ) throws -> URLRequest {
        var request = try makeRequest(baseURL: baseURL, token: token, path: path, method: method)
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func sendStatusRequest(_ request: URLRequest) async throws {
        let statusEnvelope = try await sendRequest(request, decodeAs: QingLongAPIStatusEnvelope.self)
        guard statusEnvelope.code == 200 else {
            throw QingLongError.serverError(statusEnvelope.message ?? "青龙面板请求失败。")
        }
    }

    private func sendEnvironmentMutationRequest(_ request: URLRequest) async throws -> QingLongEnvironment {
        let data = try await sendResponseData(for: request)

        if let environment = try? decodeEnvelopeData(data, as: QingLongEnvironment.self) {
            return environment
        }

        if let environments = try? decodeEnvelopeData(data, as: [QingLongEnvironment].self),
           let environment = environments.first {
            return environment
        }

        throw decodeBodyAsInvalidResponse(data)
    }

    private func sendEnvelopeRequest<T: Decodable>(_ request: URLRequest, decodeAs type: T.Type) async throws -> T {
        let data = try await sendResponseData(for: request)
        return try decodeEnvelopeData(data, as: type)
    }

    private func sendListEnvelopeRequest<T: Decodable>(_ request: URLRequest, decodeAs itemType: T.Type) async throws -> [T] {
        let data = try await sendResponseData(for: request)

        if let directItems = try? decodeEnvelopeData(data, as: [T].self) {
            return directItems
        }

        if let pagedItems = try? decodeEnvelopeData(data, as: QingLongListPayload<T>.self) {
            return pagedItems.items
        }

        throw decodeBodyAsInvalidResponse(data)
    }

    private func sendRequest<T: Decodable>(_ request: URLRequest, decodeAs type: T.Type) async throws -> T {
        let data = try await sendResponseData(for: request)

        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw decodeBodyAsInvalidResponse(data)
        }
    }

    private func sendResponseData(for request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw normalizeNetworkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw QingLongError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw decodeHTTPError(data: data, statusCode: httpResponse.statusCode)
        }

        return data
    }

    private func decodeEnvelopeData<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
        let envelope: QingLongAPIEnvelope<T>

        do {
            envelope = try decoder.decode(QingLongAPIEnvelope<T>.self, from: data)
        } catch {
            throw decodeBodyAsInvalidResponse(data)
        }

        guard envelope.code == 200 else {
            throw QingLongError.serverError(envelope.message ?? "青龙面板请求失败。")
        }
        guard let value = envelope.data else {
            throw decodeBodyAsInvalidResponse(data)
        }
        return value
    }

    private func decodeHTTPError(data: Data, statusCode: Int) -> QingLongError {
        if let envelope = try? decoder.decode(QingLongAPIStatusEnvelope.self, from: data),
           let message = envelope.message,
           !message.isEmpty {
            return .serverError(message)
        }

        if let rawText = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !rawText.isEmpty {
            return .serverError(rawText)
        }

        return .serverError("青龙面板请求失败，HTTP \(statusCode)。")
    }

    private func probeRequest(_ request: URLRequest) async -> (statusCode: Int?, data: Data?, error: QingLongError?) {
        do {
            let (data, response) = try await urlSession.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            return (statusCode, data, nil)
        } catch {
            return (nil, nil, normalizeNetworkError(error))
        }
    }

    private func makeDiagnosticStep(
        title: String,
        url: URL?,
        probe: (statusCode: Int?, data: Data?, error: QingLongError?)
    ) -> QingLongDiagnosticStep {
        if let error = probe.error {
            return QingLongDiagnosticStep(
                title: title,
                url: url?.absoluteString ?? "N/A",
                httpStatus: nil,
                isSuccess: false,
                summary: error.localizedDescription,
                preview: ""
            )
        }

        let statusCode = probe.statusCode
        let isSuccess = statusCode.map { (200..<300).contains($0) } ?? false
        let preview = responsePreview(from: probe.data)
        return QingLongDiagnosticStep(
            title: title,
            url: url?.absoluteString ?? "N/A",
            httpStatus: statusCode,
            isSuccess: isSuccess,
            summary: statusCode.map { "HTTP \($0)" } ?? "没有拿到 HTTP 状态",
            preview: preview
        )
    }

    private func decodeBodyAsInvalidResponse(_ data: Data) -> QingLongError {
        let preview = responsePreview(from: data)
        guard !preview.isEmpty else {
            return .invalidResponse
        }
        return .serverError("青龙面板返回了无法识别的结果：\(preview)")
    }

    private func responsePreview(from data: Data?) -> String {
        guard let data,
              let rawText = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !rawText.isEmpty else {
            return ""
        }

        let normalizedText = rawText
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return String(normalizedText.prefix(220))
    }

    private func normalizeNetworkError(_ error: Error) -> QingLongError {
        let nsError = error as NSError

        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut:
                return .networkError("连接青龙面板超时，请检查地址和网络。")
            case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted:
                return .networkError("青龙面板 HTTPS 证书校验失败。")
            case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
                return .networkError("无法连接到青龙面板，请确认域名、IP 和端口。")
            case NSURLErrorAppTransportSecurityRequiresSecureConnection:
                return .networkError("当前地址被 iOS 网络安全策略拦截，公网面板请使用 HTTPS。")
            default:
                break
            }
        }

        return .networkError(nsError.localizedDescription)
    }

    private func openBaseURL(for baseURL: URL) -> URL {
        baseURL.appendingPathComponent("open")
    }

    private static func normalizedBaseURL(from rawValue: String) throws -> URL {
        var trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw QingLongError.emptyBaseURL
        }

        if !trimmed.contains("://") {
            trimmed = "https://" + trimmed
        }

        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            throw QingLongError.invalidBaseURL
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw QingLongError.invalidBaseURL
        }

        var path = components.percentEncodedPath
        while path.hasSuffix("/") {
            path.removeLast()
        }
        if path.lowercased().hasSuffix("/open") {
            path.removeLast("/open".count)
            while path.hasSuffix("/") {
                path.removeLast()
            }
        }
        components.percentEncodedPath = path
        components.query = nil
        components.fragment = nil

        guard let normalizedURL = components.url else {
            throw QingLongError.invalidBaseURL
        }

        return normalizedURL
    }

    private static func displayName(for url: URL) -> String {
        if let host = url.host {
            if let port = url.port {
                return "\(host):\(port)"
            }
            return host
        }
        return url.absoluteString
    }

    private static func dateFromUnixLikeValue(_ rawValue: Int64) -> Date? {
        guard rawValue > 0 else { return nil }
        if rawValue > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: TimeInterval(rawValue) / 1000)
        }
        return Date(timeIntervalSince1970: TimeInterval(rawValue))
    }
}
