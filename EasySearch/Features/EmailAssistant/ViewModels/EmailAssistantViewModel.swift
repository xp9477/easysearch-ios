import Foundation

@MainActor
final class EmailAssistantViewModel: ObservableObject {
    @Published var mode: EmailAssistantMode = .reply {
        didSet { persistStateIfNeeded() }
    }
    @Published var originalDraft = "" {
        didSet { persistStateIfNeeded() }
    }
    @Published var receivedEmailText = "" {
        didSet { persistStateIfNeeded() }
    }
    @Published var screenshotOCRText = "" {
        didSet { persistStateIfNeeded() }
    }
    @Published var additionalRequirements = "" {
        didSet { persistStateIfNeeded() }
    }
    @Published var messageDraft = ""
    @Published var apiKeyDraft = ""
    @Published private(set) var conversation: [EmailAssistantThreadMessage] = [] {
        didSet { persistStateIfNeeded() }
    }
    @Published private(set) var configurationState = EmailAssistantConfigurationState(hasAPIKey: false, keySummary: nil)
    @Published private(set) var isGenerating = false
    @Published private(set) var isRecognizingScreenshot = false
    @Published private(set) var isSavingAPIKey = false
    @Published private(set) var notice: EmailAssistantNotice?

    private let store: any EmailAssistantSessionStore
    private var hasPrepared = false
    private var isRestoringState = false

    init(store: any EmailAssistantSessionStore = EmailAssistantUserDefaultsStore()) {
        self.store = store
    }

    var canSend: Bool {
        !isGenerating && (
            currentContext.hasUsableContent ||
            !conversation.isEmpty ||
            !messageDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }

    var isBusy: Bool {
        isGenerating || isRecognizingScreenshot || isSavingAPIKey
    }

    var hasConversation: Bool {
        !conversation.isEmpty
    }

    var currentContext: EmailAssistantContext {
        EmailAssistantContext(
            mode: mode,
            originalDraft: originalDraft,
            receivedEmailText: receivedEmailText,
            screenshotOCRText: screenshotOCRText,
            additionalRequirements: additionalRequirements
        )
    }

    func prepare() async {
        guard !hasPrepared else {
            await refreshConfiguration()
            return
        }

        hasPrepared = true
        restorePersistedStateIfNeeded()
        await refreshConfiguration()

        if conversation.isEmpty, notice == nil {
            notice = EmailAssistantNotice(
                tone: .neutral,
                message: "先贴草稿或收到的邮件，再点一次生成；后面可以继续追问让它改得更简洁、更礼貌或更直接。"
            )
        }
    }

    func refreshConfiguration() async {
        configurationState = await EmailAssistantService.shared.loadConfigurationState()
    }

    func saveAPIKey() async {
        let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            notice = EmailAssistantNotice(tone: .caution, message: "请先输入 DeepSeek API Key。")
            return
        }

        isSavingAPIKey = true
        defer { isSavingAPIKey = false }

        do {
            try await EmailAssistantService.shared.saveAPIKey(trimmed)
            apiKeyDraft = ""
            await refreshConfiguration()
            notice = EmailAssistantNotice(tone: .success, message: "DeepSeek API Key 已保存。")
        } catch {
            notice = EmailAssistantNotice(tone: .caution, message: error.localizedDescription)
        }
    }

    func clearAPIKey() async {
        do {
            try await EmailAssistantService.shared.clearAPIKey()
            apiKeyDraft = ""
            await refreshConfiguration()
            notice = EmailAssistantNotice(tone: .neutral, message: "已清除 DeepSeek API Key。")
        } catch {
            notice = EmailAssistantNotice(tone: .caution, message: error.localizedDescription)
        }
    }

    func sendCurrentMessage() async {
        let trimmedDraft = messageDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let instruction = trimmedDraft.isEmpty ? mode.defaultInstruction : trimmedDraft

        guard currentContext.hasUsableContent || !conversation.isEmpty else {
            notice = EmailAssistantNotice(tone: .caution, message: EmailAssistantError.emptyContext.localizedDescription)
            return
        }

        let previousConversation = conversation
        let userMessage = EmailAssistantThreadMessage(role: .user, content: instruction)
        conversation.append(userMessage)
        isGenerating = true
        notice = EmailAssistantNotice(tone: .neutral, message: "正在调用 DeepSeek 生成邮件...")

        defer { isGenerating = false }

        do {
            let reply = try await EmailAssistantService.shared.generateReply(
                context: currentContext,
                conversationHistory: previousConversation,
                latestUserMessage: instruction
            )
            conversation.append(EmailAssistantThreadMessage(role: .assistant, content: reply))
            if !trimmedDraft.isEmpty {
                messageDraft = ""
            }
            notice = EmailAssistantNotice(tone: .success, message: "已生成一版邮件，可继续追问修改。")
        } catch {
            conversation = previousConversation
            notice = EmailAssistantNotice(tone: .caution, message: error.localizedDescription)
        }
    }

    func sendQuickPrompt(_ prompt: String) async {
        messageDraft = prompt
        await sendCurrentMessage()
    }

    func importScreenshotText(from imageData: Data) async {
        isRecognizingScreenshot = true
        defer { isRecognizingScreenshot = false }

        do {
            let recognizedText = try await EmailAssistantOCRService.extractText(from: imageData)
            screenshotOCRText = recognizedText

            if receivedEmailText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                receivedEmailText = recognizedText
            }

            notice = EmailAssistantNotice(tone: .success, message: "截图文字已识别，可直接生成回复或继续补充要求。")
        } catch {
            notice = EmailAssistantNotice(tone: .caution, message: error.localizedDescription)
        }
    }

    func clearScreenshotText() {
        screenshotOCRText = ""
        notice = EmailAssistantNotice(tone: .neutral, message: "已移除截图识别内容。")
    }

    func clearConversation() {
        conversation = []
        notice = EmailAssistantNotice(tone: .neutral, message: "已清空当前对话，保留上下文输入。")
    }

    func resetAll() {
        mode = .reply
        originalDraft = ""
        receivedEmailText = ""
        screenshotOCRText = ""
        additionalRequirements = ""
        messageDraft = ""
        conversation = []
        store.clear()
        notice = EmailAssistantNotice(tone: .neutral, message: "已清空邮件助手内容。")
    }

    func useAssistantDraft(_ message: EmailAssistantThreadMessage) {
        guard message.role == .assistant else { return }
        originalDraft = message.content
        mode = .polish
        notice = EmailAssistantNotice(tone: .success, message: "已把这版结果放入草稿区，可继续润色。")
    }

    func presentNotice(tone: EmailAssistantNoticeTone, message: String) {
        notice = EmailAssistantNotice(tone: tone, message: message)
    }

    private func restorePersistedStateIfNeeded() {
        guard let state = store.loadState() else { return }

        isRestoringState = true
        mode = state.mode
        originalDraft = state.originalDraft
        receivedEmailText = state.receivedEmailText
        screenshotOCRText = state.screenshotOCRText
        additionalRequirements = state.additionalRequirements
        conversation = state.conversation
        isRestoringState = false
    }

    private func persistStateIfNeeded() {
        guard !isRestoringState else { return }

        store.saveState(
            EmailAssistantPersistedState(
                mode: mode,
                originalDraft: originalDraft,
                receivedEmailText: receivedEmailText,
                screenshotOCRText: screenshotOCRText,
                additionalRequirements: additionalRequirements,
                conversation: conversation
            )
        )
    }
}
