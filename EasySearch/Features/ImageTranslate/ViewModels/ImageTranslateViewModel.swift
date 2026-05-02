import Foundation
import UIKit

@MainActor
final class ImageTranslateViewModel: ObservableObject {
    @Published private(set) var selectedImage: UIImage?
    @Published private(set) var imageSource: ImageTranslateInputSource? {
        didSet { persistCurrentStateIfNeeded() }
    }
    @Published var extractedText = "" {
        didSet { persistCurrentStateIfNeeded() }
    }
    @Published private(set) var latestTranslation = "" {
        didSet { persistCurrentStateIfNeeded() }
    }
    @Published private(set) var translationNotes = "" {
        didSet { persistCurrentStateIfNeeded() }
    }
    @Published private(set) var meanings: [ImageTranslateMeaning] = [] {
        didSet { persistCurrentStateIfNeeded() }
    }
    @Published private(set) var examples: [ImageTranslateExample] = [] {
        didSet { persistCurrentStateIfNeeded() }
    }
    @Published private(set) var collocations: [ImageTranslateCollocation] = [] {
        didSet { persistCurrentStateIfNeeded() }
    }
    @Published private(set) var detectedSourceLanguage: String? {
        didSet { persistCurrentStateIfNeeded() }
    }
    @Published private(set) var conversation: [ImageTranslateConversationMessage] = [] {
        didSet { persistCurrentStateIfNeeded() }
    }
    @Published private(set) var suggestedReplies: [String] = [] {
        didSet { persistCurrentStateIfNeeded() }
    }
    @Published private(set) var history: [ImageTranslateHistoryRecord] = []
    @Published private(set) var notice: ImageTranslateNotice?
    @Published var composerText = "" {
        didSet { persistCurrentStateIfNeeded() }
    }
    @Published var targetLanguage: ImageTranslateTargetLanguage = .simplifiedChinese {
        didSet { persistCurrentStateIfNeeded() }
    }
    @Published private(set) var hasConfiguredAPIKey = false
    @Published private(set) var isRecognizingText = false
    @Published private(set) var isTranslating = false

    private let service: ImageTranslateService
    private let store: any ImageTranslateSessionStore
    private let notificationCenter: NotificationCenter
    private var configurationObserver: NSObjectProtocol?
    private var noticeDismissTask: Task<Void, Never>?
    private var hasPrepared = false
    private var isRestoringState = false
    private var currentSessionID = UUID()
    private var configuredTargetLanguage: ImageTranslateTargetLanguage = .simplifiedChinese
    private var currentImageData: Data?
    private var currentPreviewImageData: Data?
    private var lastTranslatedSourceText = "" {
        didSet { persistCurrentStateIfNeeded() }
    }

    init(
        service: ImageTranslateService = .shared,
        store: any ImageTranslateSessionStore = ImageTranslateFileStore(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.service = service
        self.store = store
        self.notificationCenter = notificationCenter
        configurationObserver = notificationCenter.addObserver(
            forName: .imageTranslateConfigurationDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.reloadConfiguration(applyDefaultTargetLanguage: false)
            }
        }
    }

    deinit {
        noticeDismissTask?.cancel()
        if let configurationObserver {
            notificationCenter.removeObserver(configurationObserver)
        }
    }

    var canTranslate: Bool {
        !extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && hasConfiguredAPIKey
            && !isRecognizingText
            && !isTranslating
    }

    var canRecognizeSelectedImage: Bool {
        selectedImage != nil
            && !isRecognizingText
            && !isTranslating
    }

    var canSendFollowUp: Bool {
        !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !latestTranslation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isTranslating
            && !isRecognizingText
    }

    var needsRetranslation: Bool {
        let current = extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = lastTranslatedSourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !latestTranslation.isEmpty && !current.isEmpty && current != last
    }

    var hasTranslation: Bool {
        !latestTranslation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasSupplementaryTranslationDetails: Bool {
        !translationNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !meanings.isEmpty
            || !examples.isEmpty
            || !collocations.isEmpty
    }

    var hasHistory: Bool {
        !history.isEmpty
    }

    var shouldShowConversation: Bool {
        hasTranslation || !conversation.isEmpty
    }

    var alignedSections: [AlignedTextSection] {
        ImageTranslateTextAlignment.sections(
            source: extractedText,
            translation: latestTranslation
        )
    }

    var imageStatusText: String {
        guard let imageSource else {
            return "未选择图片"
        }

        if let detectedSourceLanguage, !detectedSourceLanguage.isEmpty {
            return "\(imageSource.title) · 识别源语种 \(detectedSourceLanguage)"
        }

        return imageSource.title
    }

    func prepare() async {
        guard !hasPrepared else {
            await reloadConfiguration(applyDefaultTargetLanguage: false)
            history = store.loadHistory()
            return
        }

        hasPrepared = true
        await reloadConfiguration(applyDefaultTargetLanguage: true)
        restorePersistedStateIfNeeded()
        history = store.loadHistory()
    }

    func updateTargetLanguage(_ targetLanguage: ImageTranslateTargetLanguage) async {
        self.targetLanguage = targetLanguage
        configuredTargetLanguage = targetLanguage
        await service.updateTargetLanguage(targetLanguage)

        if hasTranslation {
            setNotice(
                tone: .neutral,
                message: "当前输出语言已切到\(targetLanguage.title)，可直接重新翻译当前文本。"
            )
        }
    }

    func startFreshSession() {
        resetSessionState(newSessionID: true)
        targetLanguage = configuredTargetLanguage
        store.clearCurrentState()
        setNotice(tone: .neutral, message: "已开始新会话。")
    }

    func importImage(_ image: UIImage, from source: ImageTranslateInputSource) async {
        applySessionReset(newSessionID: true)
        await assignImage(image, source: source)
        setNotice(tone: .neutral, message: "已载入\(source.title)图片，可先裁剪或直接识别。")
    }

    func importClipboardImage() async {
        guard let image = UIPasteboard.general.image else {
            setNotice(tone: .caution, message: ImageTranslateError.noImageInPasteboard.localizedDescription)
            return
        }

        await importImage(image, from: .clipboard)
    }

    func cropCurrentImage(to selection: ImageCropSelection) async {
        guard let selectedImage else {
            setNotice(tone: .caution, message: "还没有图片可裁剪。")
            return
        }

        do {
            let croppedImage = try await service.cropImage(selectedImage, selection: selection)
            applySessionReset(newSessionID: false)
            await assignImage(croppedImage, source: imageSource)
            setNotice(tone: .neutral, message: "已按选区裁剪，正在重新识别文字。")
            await recognizeSelectedImage(autoTranslate: hasConfiguredAPIKey)
        } catch {
            setNotice(tone: .caution, message: error.localizedDescription)
        }
    }

    func reRecognizeSelectedImage() async {
        guard selectedImage != nil else {
            setNotice(tone: .caution, message: "还没有图片，先从拍照、相册或剪贴板导入。")
            return
        }

        clearTranslationState()
        await recognizeSelectedImage(autoTranslate: hasConfiguredAPIKey)
    }

    func translateCurrentText() async {
        let sourceText = extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceText.isEmpty else {
            setNotice(tone: .caution, message: ImageTranslateError.emptySourceText.localizedDescription)
            return
        }

        guard hasConfiguredAPIKey else {
            setNotice(tone: .caution, message: ImageTranslateError.missingAPIKey.localizedDescription)
            return
        }

        isTranslating = true
        setNotice(tone: .neutral, message: "正在调用 AI 模型生成翻译。")

        do {
            let result = try await service.translate(
                sourceText: sourceText,
                targetLanguage: targetLanguage
            )
            applyTranslationResult(result)
            lastTranslatedSourceText = sourceText
            let message = result.detectedSourceLanguage.map { "已完成 \($0) -> \(targetLanguage.title) 翻译。" }
                ?? "已完成 AI 翻译。"
            setNotice(tone: .success, message: message)
        } catch {
            setNotice(tone: .caution, message: error.localizedDescription)
        }

        isTranslating = false
    }

    func sendFollowUp() async {
        let prompt = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        guard hasTranslation else {
            setNotice(tone: .caution, message: "请先生成第一版翻译。")
            return
        }

        isTranslating = true
        let userMessage = ImageTranslateConversationMessage(role: .user, text: prompt)
        conversation.append(userMessage)
        composerText = ""
        setNotice(tone: .neutral, message: "正在继续生成回复。")

        do {
            let result = try await service.followUp(
                sourceText: extractedText,
                currentTranslation: latestTranslation,
                history: conversation,
                userPrompt: prompt,
                targetLanguage: targetLanguage
            )
            applyTranslationResult(result)
            lastTranslatedSourceText = extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
            setNotice(tone: .success, message: "已更新翻译和讨论结果。")
        } catch {
            if conversation.last?.id == userMessage.id {
                conversation.removeLast()
            }
            composerText = prompt
            setNotice(tone: .caution, message: error.localizedDescription)
        }

        isTranslating = false
    }

    func sendSuggestedReply(_ text: String) async {
        composerText = text
        await sendFollowUp()
    }

    func loadHistorySession(_ record: ImageTranslateHistoryRecord) {
        isRestoringState = true
        currentSessionID = record.id
        let restoredImageData = record.selectedImageData ?? record.previewImageData
        selectedImage = restoredImageData.flatMap(UIImage.init(data:))
        currentImageData = restoredImageData
        currentPreviewImageData = record.previewImageData
        imageSource = record.imageSource
        targetLanguage = record.targetLanguage
        extractedText = record.sourceText
        latestTranslation = record.translation
        translationNotes = record.translationNotes
        meanings = record.meanings
        examples = record.examples
        collocations = record.collocations
        detectedSourceLanguage = record.detectedSourceLanguage
        conversation = record.conversation
        suggestedReplies = record.suggestedReplies
        composerText = ""
        lastTranslatedSourceText = record.sourceText
        isRestoringState = false
        persistCurrentStateIfNeeded()
        setNotice(tone: .success, message: "已恢复一条最近会话。")
    }

    func deleteHistoryRecord(_ record: ImageTranslateHistoryRecord) {
        history = ImageTranslateHistoryReducer.delete(recordID: record.id, from: history)
        store.saveHistory(history)
        setNotice(tone: .neutral, message: "已从最近历史中移除。")
    }

    func copyText(_ text: String, successMessage: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UIPasteboard.general.string = trimmed
        setNotice(tone: .success, message: successMessage)
    }

    func presentNotice(tone: ImageTranslateNoticeTone, message: String) {
        setNotice(tone: tone, message: message)
    }

    private func reloadConfiguration(applyDefaultTargetLanguage: Bool) async {
        let configuration = await service.loadConfiguration()
        hasConfiguredAPIKey = configuration.hasAPIKey
        configuredTargetLanguage = configuration.targetLanguage

        if applyDefaultTargetLanguage || shouldAdoptConfiguredTargetLanguage {
            targetLanguage = configuration.targetLanguage
        }
    }

    private var shouldAdoptConfiguredTargetLanguage: Bool {
        selectedImage == nil
            && extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && latestTranslation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && conversation.isEmpty
    }

    private func restorePersistedStateIfNeeded() {
        guard let state = store.loadCurrentState() else { return }

        isRestoringState = true
        currentSessionID = state.sessionID
        selectedImage = state.selectedImageData.flatMap(UIImage.init(data:))
        currentImageData = state.selectedImageData
        currentPreviewImageData = state.previewImageData
        imageSource = state.imageSource
        targetLanguage = state.targetLanguage
        extractedText = state.extractedText
        latestTranslation = state.latestTranslation
        translationNotes = state.translationNotes
        meanings = state.meanings
        examples = state.examples
        collocations = state.collocations
        detectedSourceLanguage = state.detectedSourceLanguage
        conversation = []
        suggestedReplies = []
        composerText = ""
        lastTranslatedSourceText = state.lastTranslatedSourceText
        isRestoringState = false
    }

    private func assignImage(_ image: UIImage, source: ImageTranslateInputSource?) async {
        let normalizedImage = ImageOCRService.normalizedDisplayImage(image)
        selectedImage = normalizedImage
        imageSource = source
        currentImageData = await service.storedImageData(from: normalizedImage)
        currentPreviewImageData = await service.previewImageData(from: normalizedImage)
        persistCurrentStateIfNeeded()
    }

    private func recognizeSelectedImage(autoTranslate: Bool) async {
        guard let image = selectedImage else { return }

        isRecognizingText = true

        do {
            let recognizedText = try await service.recognizeText(in: image)
            extractedText = recognizedText
            setNotice(
                tone: .success,
                message: autoTranslate
                    ? "识别完成，正在继续生成翻译。"
                    : "识别完成。你可以先校对文字，再发起 AI 翻译。"
            )

            isRecognizingText = false

            if autoTranslate {
                await translateCurrentText()
            }
        } catch {
            isRecognizingText = false
            extractedText = ""
            setNotice(tone: .caution, message: error.localizedDescription)
        }
    }

    private func applyTranslationResult(_ result: ImageTranslateResult) {
        latestTranslation = result.translation
        translationNotes = result.notes
        meanings = result.meanings
        examples = result.examples
        collocations = result.collocations
        suggestedReplies = []

        if let detectedSourceLanguage = result.detectedSourceLanguage,
           !detectedSourceLanguage.isEmpty {
            self.detectedSourceLanguage = detectedSourceLanguage
        }
        conversation = []
        composerText = ""
    }

    private func applySessionReset(newSessionID: Bool) {
        isRestoringState = true
        if newSessionID {
            currentSessionID = UUID()
        }
        clearTranslationState()
        selectedImage = nil
        imageSource = nil
        currentImageData = nil
        currentPreviewImageData = nil
        isRestoringState = false
        persistCurrentStateIfNeeded()
    }

    private func clearTranslationState() {
        extractedText = ""
        latestTranslation = ""
        translationNotes = ""
        meanings = []
        examples = []
        collocations = []
        detectedSourceLanguage = nil
        conversation = []
        suggestedReplies = []
        composerText = ""
        lastTranslatedSourceText = ""
    }

    private func resetSessionState(newSessionID: Bool) {
        applySessionReset(newSessionID: newSessionID)
    }

    private func upsertHistorySnapshot() {
        let trimmedTranslation = latestTranslation.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSource = extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranslation.isEmpty, !trimmedSource.isEmpty else { return }

        let record = ImageTranslateHistoryRecord(
            id: currentSessionID,
            updatedAt: Date(),
            imageSource: imageSource,
            targetLanguage: targetLanguage,
            detectedSourceLanguage: detectedSourceLanguage,
            title: makeHistoryTitle(from: trimmedSource),
            sourceSnippet: makeSnippet(from: trimmedSource),
            translationSnippet: makeSnippet(from: trimmedTranslation),
            sourceText: trimmedSource,
            translation: trimmedTranslation,
            translationNotes: translationNotes,
            meanings: meanings,
            examples: examples,
            collocations: collocations,
            conversation: conversation,
            suggestedReplies: suggestedReplies,
            selectedImageData: currentImageData,
            previewImageData: currentPreviewImageData
        )

        history = ImageTranslateHistoryReducer.upsert(record, into: history)
        store.saveHistory(history)
    }

    private func makeHistoryTitle(from text: String) -> String {
        let firstLine = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "未命名翻译"

        if firstLine.count <= 28 {
            return firstLine
        }

        return String(firstLine.prefix(28)) + "..."
    }

    private func makeSnippet(from text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.count <= 72 {
            return normalized
        }

        return String(normalized.prefix(72)) + "..."
    }

    private var hasSessionContent: Bool {
        selectedImage != nil
            || !extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !latestTranslation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func makePersistedState() -> ImageTranslatePersistedState {
        ImageTranslatePersistedState(
            sessionID: currentSessionID,
            imageSource: imageSource,
            targetLanguage: targetLanguage,
            selectedImageData: currentImageData,
            previewImageData: currentPreviewImageData,
            extractedText: extractedText,
            latestTranslation: latestTranslation,
            translationNotes: translationNotes,
            detectedSourceLanguage: detectedSourceLanguage,
            meanings: meanings,
            examples: examples,
            collocations: collocations,
            conversation: [],
            suggestedReplies: [],
            composerText: "",
            lastTranslatedSourceText: lastTranslatedSourceText
        )
    }

    private func persistCurrentStateIfNeeded() {
        guard !isRestoringState else { return }

        if hasSessionContent {
            store.saveCurrentState(makePersistedState())
        } else {
            store.clearCurrentState()
        }
    }

    private func setNotice(tone: ImageTranslateNoticeTone, message: String?) {
        noticeDismissTask?.cancel()

        guard let message, !message.isEmpty else {
            notice = nil
            return
        }

        let notice = ImageTranslateNotice(tone: tone, message: message)
        self.notice = notice

        let delay: UInt64
        switch tone {
        case .caution:
            delay = 3_200_000_000
        case .neutral, .success:
            delay = 2_000_000_000
        }

        noticeDismissTask = Task { [weak self, notice] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self, self.notice == notice else { return }
                self.notice = nil
            }
        }
    }
}
