import Foundation

@MainActor
final class EmailAssistantViewModel: ObservableObject {
    @Published var mode: EmailAssistantMode = .reply { didSet { persistStateIfNeeded() } }
    @Published var tone: EmailAssistantTone = .concise { didSet { persistStateIfNeeded() } }
    @Published var length: EmailAssistantLength = .short { didSet { persistStateIfNeeded() } }
    @Published var scenario: EmailAssistantScenario = .general { didSet { persistStateIfNeeded() } }
    @Published var originalDraft = "" { didSet { persistStateIfNeeded() } }
    @Published var receivedEmailText = "" { didSet { persistStateIfNeeded() } }
    @Published var additionalRequirements = "" { didSet { persistStateIfNeeded() } }
    @Published var messageDraft = ""
    @Published private(set) var conversation: [EmailAssistantThreadMessage] = [] { didSet { persistStateIfNeeded() } }
    @Published private(set) var isGenerating = false
    @Published private(set) var isRecognizingScreenshot = false
    @Published private(set) var notice: EmailAssistantNotice?

    private let store: any EmailAssistantSessionStore
    private var hasPrepared = false
    private var isRestoringState = false
    private var generationTask: Task<Void, Never>?
    private var activeRequestID: UUID?

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

    var currentContext: EmailAssistantContext {
        EmailAssistantContext(
            mode: mode,
            tone: tone,
            length: length,
            scenario: scenario,
            originalDraft: originalDraft,
            receivedEmailText: receivedEmailText,
            additionalRequirements: additionalRequirements
        )
    }

    var completedConversation: [EmailAssistantThreadMessage] {
        conversation.filter { !$0.isPartial }
    }

    func prepare() async {
        guard !hasPrepared else { return }

        hasPrepared = true
        restorePersistedStateIfNeeded()
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
        let requestID = UUID()

        conversation.append(userMessage)
        messageDraft = ""
        activeRequestID = requestID
        isGenerating = true
        notice = EmailAssistantNotice(tone: .neutral, message: "生成中...")

        generationTask?.cancel()
        generationTask = Task { [weak self] in
            guard let self else { return }

            do {
                let output = try await EmailAssistantService.shared.generateReply(
                    context: self.currentContext,
                    conversationHistory: previousConversation,
                    latestUserMessage: instruction
                )

                await MainActor.run {
                    self.finishGeneration(id: requestID, output: output)
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.handleGenerationCancellation(id: requestID)
                }
            } catch {
                await MainActor.run {
                    self.handleGenerationFailure(id: requestID, message: error.localizedDescription)
                }
            }
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
            let result = try await EmailAssistantOCRService.extractText(from: imageData)
            receivedEmailText = result

            notice = EmailAssistantNotice(
                tone: .success,
                message: "已填入来信。"
            )
        } catch {
            notice = EmailAssistantNotice(tone: .caution, message: error.localizedDescription)
        }
    }

    func clearConversation() {
        generationTask?.cancel()
        generationTask = nil
        activeRequestID = nil
        isGenerating = false
        conversation = []
        notice = EmailAssistantNotice(tone: .neutral, message: "已清空对话。")
    }

    func resetAll() {
        generationTask?.cancel()
        generationTask = nil
        activeRequestID = nil
        isGenerating = false
        mode = .reply
        tone = .concise
        length = .short
        scenario = .general
        originalDraft = ""
        receivedEmailText = ""
        additionalRequirements = ""
        messageDraft = ""
        conversation = []
        store.clear()
        notice = EmailAssistantNotice(tone: .neutral, message: "已重置。")
    }

    func useAssistantMessageAsDraft(_ message: EmailAssistantThreadMessage) {
        guard let output = message.structuredOutput else {
            guard message.role == .assistant else { return }
            originalDraft = message.content
            mode = .polish
            notice = EmailAssistantNotice(tone: .success, message: "已放入草稿。")
            return
        }

        originalDraft = output.primaryFormattedText
        mode = .polish
        notice = EmailAssistantNotice(tone: .success, message: "已放入草稿。")
    }

    func useDraftVariant(_ variant: EmailAssistantDraftVariant) {
        originalDraft = variant.formattedText
        mode = .polish
        notice = EmailAssistantNotice(tone: .success, message: "已放入草稿。")
    }

    func presentNotice(tone: EmailAssistantNoticeTone, message: String) {
        notice = EmailAssistantNotice(tone: tone, message: message)
    }

    private func finishGeneration(id: UUID, output: EmailAssistantStructuredOutput) {
        guard activeRequestID == id else { return }

        conversation.append(
            EmailAssistantThreadMessage(
                role: .assistant,
                content: output.primaryFormattedText,
                structuredOutput: output
            )
        )
        generationTask = nil
        activeRequestID = nil
        isGenerating = false
        notice = EmailAssistantNotice(tone: .success, message: "已生成。")
    }

    private func handleGenerationCancellation(id: UUID) {
        guard activeRequestID == id else { return }

        generationTask = nil
        activeRequestID = nil
        isGenerating = false
    }

    private func handleGenerationFailure(id: UUID, message: String) {
        guard activeRequestID == id else { return }

        generationTask = nil
        activeRequestID = nil
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
        additionalRequirements = state.additionalRequirements
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
                additionalRequirements: additionalRequirements,
                conversation: conversation
            )
        )
    }
}
