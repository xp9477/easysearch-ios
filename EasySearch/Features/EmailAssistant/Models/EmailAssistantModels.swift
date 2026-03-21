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

    var iconName: String {
        switch self {
        case .polish:
            return "wand.and.stars"
        case .reply:
            return "arrowshape.turn.up.left"
        case .discuss:
            return "bubble.left.and.text.bubble.right"
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
            return "请先给我一版可直接发送的简洁英文邮件。"
        case .reply:
            return "请基于当前上下文生成一版英文回复邮件。"
        case .discuss:
            return "请先给出一版最稳妥的英文邮件，并保留后续继续优化的空间。"
        }
    }
}

enum EmailAssistantTone: String, CaseIterable, Identifiable, Codable {
    case concise
    case friendly
    case formal
    case firm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .concise:
            return "简洁"
        case .friendly:
            return "友好"
        case .formal:
            return "正式"
        case .firm:
            return "坚定"
        }
    }

    var promptDescription: String {
        switch self {
        case .concise:
            return "direct and concise"
        case .friendly:
            return "warm and friendly"
        case .formal:
            return "formal and professional"
        case .firm:
            return "clear, firm, and respectful"
        }
    }
}

enum EmailAssistantLength: String, CaseIterable, Identifiable, Codable {
    case short
    case medium
    case detailed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .short:
            return "短"
        case .medium:
            return "中"
        case .detailed:
            return "长"
        }
    }

    var promptDescription: String {
        switch self {
        case .short:
            return "keep it short, usually within 4 to 6 sentences"
        case .medium:
            return "keep it moderate, usually within 1 to 2 short paragraphs"
        case .detailed:
            return "allow a fuller version, but still practical and not bloated"
        }
    }
}

enum EmailAssistantScenario: String, CaseIterable, Identifiable, Codable {
    case general
    case firstContact
    case followUp
    case reminder
    case thankYou
    case decline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "通用"
        case .firstContact:
            return "首次联系"
        case .followUp:
            return "跟进"
        case .reminder:
            return "催办提醒"
        case .thankYou:
            return "感谢"
        case .decline:
            return "婉拒"
        }
    }

    var promptDescription: String {
        switch self {
        case .general:
            return "general business email"
        case .firstContact:
            return "first contact or introduction email"
        case .followUp:
            return "follow-up email"
        case .reminder:
            return "reminder or gentle nudge"
        case .thankYou:
            return "thank-you email"
        case .decline:
            return "polite decline"
        }
    }
}

struct EmailAssistantDraftVariant: Identifiable, Hashable, Codable {
    let id: UUID
    let title: String
    let subject: String
    let body: String

    init(
        id: UUID = UUID(),
        title: String,
        subject: String,
        body: String
    ) {
        self.id = id
        self.title = title
        self.subject = subject
        self.body = body
    }

    var formattedText: String {
        "Subject: \(subject)\n\n\(body)"
    }
}

struct EmailAssistantStructuredOutput: Hashable, Codable {
    let subject: String
    let body: String
    let explanation: String
    let alternatives: [EmailAssistantDraftVariant]

    var primaryFormattedText: String {
        "Subject: \(subject)\n\n\(body)"
    }

    var transcriptText: String {
        primaryFormattedText
    }
}

enum EmailAssistantMessageRole: String, Codable {
    case user
    case assistant
}

struct EmailAssistantThreadMessage: Identifiable, Hashable, Codable {
    let id: UUID
    let role: EmailAssistantMessageRole
    var content: String
    let createdAt: Date
    var structuredOutput: EmailAssistantStructuredOutput?
    var isPartial: Bool

    init(
        id: UUID = UUID(),
        role: EmailAssistantMessageRole,
        content: String,
        createdAt: Date = Date(),
        structuredOutput: EmailAssistantStructuredOutput? = nil,
        isPartial: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.structuredOutput = structuredOutput
        self.isPartial = isPartial
    }

    var transcriptContent: String {
        structuredOutput?.transcriptText ?? content
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
    let tone: EmailAssistantTone
    let length: EmailAssistantLength
    let scenario: EmailAssistantScenario
    let originalDraft: String
    let receivedEmailText: String
    let additionalRequirements: String

    var hasUsableContent: Bool {
        [
            originalDraft,
            receivedEmailText,
            additionalRequirements
        ].contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var serializedSummary: String {
        [
            "当前任务模式：\(mode.title)",
            "邮件场景：\(scenario.title)",
            "语气偏好：\(tone.title)",
            "长度偏好：\(length.title)",
            contextLine(label: "原始草稿", value: originalDraft),
            contextLine(label: "收到的邮件内容", value: receivedEmailText),
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
    var tone: EmailAssistantTone
    var length: EmailAssistantLength
    var scenario: EmailAssistantScenario
    var originalDraft: String
    var receivedEmailText: String
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
    private let stateKey = "email-assistant.persisted-state.v2"

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
