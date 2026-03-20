import Foundation

enum EmailAssistantMode: String, CaseIterable, Identifiable, Codable {
    case polish
    case reply
    case discuss

    var id: String { rawValue }

    var title: String {
        switch self {
        case .polish:
            return "润色草稿"
        case .reply:
            return "回复来信"
        case .discuss:
            return "讨论优化"
        }
    }

    var shortDescription: String {
        switch self {
        case .polish:
            return "把现有内容整理成简洁英文邮件"
        case .reply:
            return "基于收到的邮件建议英文回复"
        case .discuss:
            return "围绕邮件目标多轮讨论再迭代"
        }
    }

    var defaultInstruction: String {
        switch self {
        case .polish:
            return "请把当前内容整理成一封简洁、自然、专业的英文邮件，直接给出可发送版本。"
        case .reply:
            return "请基于当前上下文给出一封简洁、专业、自然的英文回复邮件，直接给出可发送版本。"
        case .discuss:
            return "请结合当前上下文先给出一版最稳妥的简洁英文邮件，并保留后续继续优化的空间。"
        }
    }
}

enum EmailAssistantMessageRole: String, Codable {
    case user
    case assistant
}

struct EmailAssistantThreadMessage: Identifiable, Hashable, Codable {
    let id: UUID
    let role: EmailAssistantMessageRole
    let content: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        role: EmailAssistantMessageRole,
        content: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

enum EmailAssistantNoticeTone: Equatable {
    case neutral
    case success
    case caution
}

struct EmailAssistantNotice: Equatable {
    let tone: EmailAssistantNoticeTone
    let message: String
}

struct EmailAssistantContext: Hashable {
    let mode: EmailAssistantMode
    let originalDraft: String
    let receivedEmailText: String
    let screenshotOCRText: String
    let additionalRequirements: String

    var hasUsableContent: Bool {
        [
            originalDraft,
            receivedEmailText,
            screenshotOCRText,
            additionalRequirements
        ].contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var serializedSummary: String {
        [
            "当前任务模式：\(mode.title)",
            contextLine(label: "原始草稿", value: originalDraft),
            contextLine(label: "收到的邮件内容", value: receivedEmailText),
            contextLine(label: "截图 OCR 文本", value: screenshotOCRText),
            contextLine(label: "补充要求", value: additionalRequirements)
        ]
        .joined(separator: "\n\n")
    }

    private func contextLine(label: String, value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(label)：\n" + (trimmed.isEmpty ? "无" : trimmed)
    }
}

struct EmailAssistantPersistedState: Codable {
    var mode: EmailAssistantMode
    var originalDraft: String
    var receivedEmailText: String
    var screenshotOCRText: String
    var additionalRequirements: String
    var conversation: [EmailAssistantThreadMessage]
}

protocol EmailAssistantSessionStore {
    func loadState() -> EmailAssistantPersistedState?
    func saveState(_ state: EmailAssistantPersistedState)
    func clear()
}

struct EmailAssistantUserDefaultsStore: EmailAssistantSessionStore {
    private let userDefaults: UserDefaults
    private let stateKey = "email-assistant.persisted-state.v1"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadState() -> EmailAssistantPersistedState? {
        guard let data = userDefaults.data(forKey: stateKey) else {
            return nil
        }

        return try? JSONDecoder().decode(EmailAssistantPersistedState.self, from: data)
    }

    func saveState(_ state: EmailAssistantPersistedState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        userDefaults.set(data, forKey: stateKey)
    }

    func clear() {
        userDefaults.removeObject(forKey: stateKey)
    }
}
