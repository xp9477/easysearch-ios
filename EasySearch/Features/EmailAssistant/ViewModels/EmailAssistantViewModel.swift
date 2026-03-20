import Foundation

@MainActor
final class EmailAssistantViewModel: ObservableObject {
    @Published var mode: EmailAssistantMode = .reply { didSet { persistStateIfNeeded() } }
    @Published var tone: EmailAssistantTone = .concise { didSet { persistStateIfNeeded() } }
    @Published var length: EmailAssistantLength = .short { didSet { persistStateIfNeeded() } }
    @Published var scenario: EmailAssistantScenario = .general { didSet { persistStateIfNeeded() } }
    @Published var originalDraft = "" { didSet { persistStateIfNeeded() } }
    @Published var receivedEmailText = "" { didSet { persistStateIfNeeded() } }
    @Published var screenshotOCRText = "" { didSet { persistStateIfNeeded() } }
    @Published var additionalRequirements = "" { didSet { persistStateIfNeeded() } }
    @Published var senderName = "" { didSet { persistStateIfNeeded() } }
    @Published var senderRoleOrTeam = "" { didSet { persistStateIfNeeded() } }
    @Published var senderCompany = "" { didSet { persistStateIfNeeded() } }
    @Published var preferredClosing = "Best regards," { didSet { persistStateIfNeeded() } }
    @Published var signature = "" { didSet { persistStateIfNeeded() } }
    @Published private(set) var ocrSegments: [EmailAssistantOCRSegment] = [] { didSet { persistStateIfNeeded() } }
    @Published var messageDraft = ""
    @Published var apiKeyDraft = ""
    @Published private(set) var conversation: [EmailAssistantThreadMessage] = [] { didSet { persistStateIfNeeded() } }
    @Published private(set) var configurationState = EmailAssistantConfigurationState(hasAPIKey: false, keySummary: nil)
    @Published private(set) var isGenerating = false
    @Published private(set) var isRecognizingScreenshot = false
    @Published private(set) var isSavingAPIKey = false
    @Published private(set) var notice: EmailAssistantNotice?

    private let store: any EmailAssistantSessionStore
    private var hasPrepared = false
    private var isRestoringState = false
    private var generationTask: Task<Void, Never>?
    private var streamingMessageID: UUID?

    init(store: any EmailAssistantSessionStore = EmailAssistantUserDefaultsStore()) {
        self.store = store
    }

    deinit {
        generationTask?.cancel()
    }

    var canSend: Bool {
        !isGenerating && (
            currentContext.hasUsableContent ||
            !completedConversation.isEmpty ||
            !messageDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }

    var hasConversation: Bool {
        !conversation.isEmpty
    }

    var hasOCRSegments: Bool {
        !ocrSegments.isEmpty
    }

    var selectedOCRSegmentCount: Int {
        ocrSegments.filter(\.isSelected).count
    }

    var canApplySelectedOCR: Bool {
        selectedOCRSegmentCount > 0
    }

    var currentContext: EmailAssistantContext {
        EmailAssistantContext(
            mode: mode,
            tone: tone,
            length: length,
            scenario: scenario,
            originalDraft: originalDraft,
            receivedEmailText: receivedEmailText,
            screenshotOCRText: screenshotOCRText,
            additionalRequirements: additionalRequirements,
            senderProfile: currentSenderProfile
        )
    }

    var currentSenderProfile: EmailAssistantSenderProfile {
        EmailAssistantSenderProfile(
            name: senderName,
            roleOrTeam: senderRoleOrTeam,
            company: senderCompany,
            preferredClosing: preferredClosing,
            signature: signature
        )
    }

    var completedConversation: [EmailAssistantThreadMessage] {
        conversation.filter { !$0.isPartial }
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
                message: "先贴草稿、来信或截图，再生成第一版；后面可以继续让它更简洁、更正式或更直接。"
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
        guard !isGenerating else { return }

        let trimmedDraft = messageDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let instruction = trimmedDraft.isEmpty ? mode.defaultInstruction : trimmedDraft

        guard currentContext.hasUsableContent || !completedConversation.isEmpty else {
            notice = EmailAssistantNotice(tone: .caution, message: EmailAssistantError.emptyContext.localizedDescription)
            return
        }

        let previousConversation = completedConversation
        let userMessage = EmailAssistantThreadMessage(role: .user, content: instruction)
        let assistantID = UUID()
        let assistantPlaceholder = EmailAssistantThreadMessage(
            id: assistantID,
            role: .assistant,
            content: "",
            structuredOutput: nil,
            isPartial: false
        )

        conversation.append(userMessage)
        conversation.append(assistantPlaceholder)
        messageDraft = ""
        streamingMessageID = assistantID
        isGenerating = true
        notice = EmailAssistantNotice(tone: .neutral, message: "正在流式生成邮件内容...")

        generationTask?.cancel()
        generationTask = Task { [weak self] in
            guard let self else { return }

            do {
                let output = try await EmailAssistantService.shared.generateReplyStream(
                    context: self.currentContext,
                    conversationHistory: previousConversation,
                    latestUserMessage: instruction,
                    onDelta: { delta in
                        Task { @MainActor [weak self] in
                            self?.appendStreamingDelta(delta, to: assistantID)
                        }
                    }
                )

                await MainActor.run {
                    self.finishStreamingMessage(
                        id: assistantID,
                        output: output
                    )
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.markStreamingMessageAsPartial(id: assistantID)
                    self.notice = EmailAssistantNotice(
                        tone: .neutral,
                        message: "已停止生成，当前结果可能不完整。"
                    )
                }
            } catch {
                await MainActor.run {
                    self.handleGenerationFailure(for: assistantID, message: error.localizedDescription)
                }
            }
        }
    }

    func stopGenerating() {
        generationTask?.cancel()
    }

    func sendQuickPrompt(_ prompt: String) async {
        messageDraft = prompt
        await sendCurrentMessage()
    }

    func importScreenshotText(from imageData: Data) async {
        isRecognizingScreenshot = true
        defer { isRecognizingScreenshot = false }

        do {
            let result = try await EmailAssistantOCRService.extractText(from: imageData)
            ocrSegments = result.segments
            screenshotOCRText = result.fullText

            if receivedEmailText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                receivedEmailText = result.fullText
            }

            notice = EmailAssistantNotice(
                tone: .success,
                message: "截图文字已识别。可以先勾选正文段落，再替换或追加到来信区。"
            )
        } catch {
            notice = EmailAssistantNotice(tone: .caution, message: error.localizedDescription)
        }
    }

    func toggleOCRSegment(_ segmentID: UUID) {
        guard let index = ocrSegments.firstIndex(where: { $0.id == segmentID }) else { return }
        ocrSegments[index].isSelected.toggle()
        rebuildScreenshotTextFromSegments()
    }

    func selectAllOCRSegments() {
        guard !ocrSegments.isEmpty else { return }
        ocrSegments = ocrSegments.map { segment in
            var updated = segment
            updated.isSelected = true
            return updated
        }
        rebuildScreenshotTextFromSegments()
    }

    func clearOCRSelection() {
        guard !ocrSegments.isEmpty else { return }
        ocrSegments = ocrSegments.map { segment in
            var updated = segment
            updated.isSelected = false
            return updated
        }
        rebuildScreenshotTextFromSegments()
    }

    func applySelectedOCRToReceivedEmail(replace: Bool) {
        let selectedText = selectedOCRText
        guard !selectedText.isEmpty else {
            notice = EmailAssistantNotice(tone: .caution, message: "还没有选中可用的 OCR 段落。")
            return
        }

        if replace || receivedEmailText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            receivedEmailText = selectedText
        } else {
            let suffix = receivedEmailText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"
            receivedEmailText += suffix + selectedText
        }

        notice = EmailAssistantNotice(
            tone: .success,
            message: replace ? "已用选中 OCR 段落替换来信内容。" : "已把选中 OCR 段落追加到来信内容。"
        )
    }

    func clearScreenshotText() {
        screenshotOCRText = ""
        ocrSegments = []
        notice = EmailAssistantNotice(tone: .neutral, message: "已移除截图识别内容。")
    }

    func clearConversation() {
        generationTask?.cancel()
        generationTask = nil
        streamingMessageID = nil
        isGenerating = false
        conversation = []
        notice = EmailAssistantNotice(tone: .neutral, message: "已清空当前对话，保留上下文输入。")
    }

    func resetAll() {
        generationTask?.cancel()
        generationTask = nil
        streamingMessageID = nil
        isGenerating = false
        mode = .reply
        tone = .concise
        length = .short
        scenario = .general
        originalDraft = ""
        receivedEmailText = ""
        screenshotOCRText = ""
        additionalRequirements = ""
        senderName = ""
        senderRoleOrTeam = ""
        senderCompany = ""
        preferredClosing = "Best regards,"
        signature = ""
        ocrSegments = []
        messageDraft = ""
        conversation = []
        store.clear()
        notice = EmailAssistantNotice(tone: .neutral, message: "已清空邮件助手内容。")
    }

    func useAssistantMessageAsDraft(_ message: EmailAssistantThreadMessage) {
        guard let output = message.structuredOutput else {
            guard message.role == .assistant else { return }
            originalDraft = message.content
            mode = .polish
            notice = EmailAssistantNotice(tone: .success, message: "已把当前结果放入草稿区，可继续润色。")
            return
        }

        originalDraft = output.primaryFormattedText
        mode = .polish
        notice = EmailAssistantNotice(tone: .success, message: "已把主版本放入草稿区，可继续润色。")
    }

    func useDraftVariant(_ variant: EmailAssistantDraftVariant) {
        originalDraft = variant.formattedText
        mode = .polish
        notice = EmailAssistantNotice(tone: .success, message: "已把所选版本放入草稿区。")
    }

    func presentNotice(tone: EmailAssistantNoticeTone, message: String) {
        notice = EmailAssistantNotice(tone: tone, message: message)
    }

    private var selectedOCRText: String {
        ocrSegments
            .filter(\.isSelected)
            .map(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func rebuildScreenshotTextFromSegments() {
        screenshotOCRText = selectedOCRText
    }

    private func appendStreamingDelta(_ delta: String, to messageID: UUID) {
        guard let index = conversation.firstIndex(where: { $0.id == messageID }) else { return }
        conversation[index].content += delta
    }

    private func finishStreamingMessage(
        id: UUID,
        output: EmailAssistantStructuredOutput
    ) {
        guard let index = conversation.firstIndex(where: { $0.id == id }) else { return }
        conversation[index].content = output.primaryFormattedText
        conversation[index].structuredOutput = output
        conversation[index].isPartial = false
        generationTask = nil
        streamingMessageID = nil
        isGenerating = false
        notice = EmailAssistantNotice(tone: .success, message: "邮件已生成，可继续选择版本或追加修改要求。")
    }

    private func markStreamingMessageAsPartial(id: UUID) {
        if let index = conversation.firstIndex(where: { $0.id == id }) {
            conversation[index].isPartial = true
        }
        generationTask = nil
        streamingMessageID = nil
        isGenerating = false
    }

    private func handleGenerationFailure(for messageID: UUID, message: String) {
        if let index = conversation.firstIndex(where: { $0.id == messageID }) {
            if conversation[index].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                conversation.remove(at: index)
            } else {
                conversation[index].isPartial = true
            }
        }

        generationTask = nil
        streamingMessageID = nil
        isGenerating = false
        notice = EmailAssistantNotice(tone: .caution, message: message)
    }

    private func restorePersistedStateIfNeeded() {
        guard let state = store.loadState() else { return }

        isRestoringState = true
        mode = state.mode
        tone = state.tone
        length = state.length
        scenario = state.scenario
        originalDraft = state.originalDraft
        receivedEmailText = state.receivedEmailText
        screenshotOCRText = state.screenshotOCRText
        additionalRequirements = state.additionalRequirements
        senderName = state.senderProfile.name
        senderRoleOrTeam = state.senderProfile.roleOrTeam
        senderCompany = state.senderProfile.company
        preferredClosing = state.senderProfile.preferredClosing
        signature = state.senderProfile.signature
        ocrSegments = state.ocrSegments
        conversation = state.conversation
        isRestoringState = false
    }

    private func persistStateIfNeeded() {
        guard !isRestoringState else { return }

        store.saveState(
            EmailAssistantPersistedState(
                mode: mode,
                tone: tone,
                length: length,
                scenario: scenario,
                originalDraft: originalDraft,
                receivedEmailText: receivedEmailText,
                screenshotOCRText: screenshotOCRText,
                additionalRequirements: additionalRequirements,
                senderProfile: currentSenderProfile,
                ocrSegments: ocrSegments,
                conversation: conversation
            )
        )
    }
}
