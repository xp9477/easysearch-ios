import PhotosUI
import SwiftUI
import UIKit

public struct EmailAssistantView: View {
    @EnvironmentObject private var navigationState: AppNavigationState
    @StateObject private var viewModel = EmailAssistantViewModel()
    @FocusState private var isComposerFocused: Bool
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var cropSource: EmailAssistantCropSource?
    @State private var screenshotPreviewImage: UIImage?
    @State private var hasConfiguredAPIKey = true
    @State private var isContextExpanded = false
    @State private var isClearConfirmPresented = false

    public init() {}

    private var trimmedReceived: String {
        viewModel.receivedEmailText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedDraft: String {
        viewModel.originalDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var contextSummary: String {
        var parts: [String] = []

        if viewModel.mode == .reply {
            parts.append(trimmedReceived.isEmpty ? "未填来信" : "已填来信 · \(trimmedReceived.count) 字")
        }

        if !trimmedDraft.isEmpty {
            parts.append("要点 \(trimmedDraft.count) 字")
        }

        parts.append("场景 \(viewModel.scenario.title)")
        return parts.joined(separator: " · ")
    }

    public var body: some View {
        Group {
            if hasConfiguredAPIKey {
                chatLayout
            } else {
                ESNeedsSetupState(
                    title: "尚未配置 AI",
                    message: "邮件助手需要 AI API Key 才能生成内容。",
                    actionTitle: "去配置"
                ) {
                    navigationState.openSettings(.emailAssistant)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .esScreenBackground()
        .navigationTitle("邮件")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("模式", selection: $viewModel.mode) {
                        ForEach(EmailAssistantMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.iconName).tag(mode)
                        }
                    }

                    Divider()

                    Button(role: .destructive) {
                        isClearConfirmPresented = true
                    } label: {
                        Label("清空对话", systemImage: "trash")
                    }
                    .disabled(!viewModel.hasConversation)

                    Button {
                        navigationState.openSettings(.emailAssistant)
                    } label: {
                        Label("AI 配置", systemImage: "slider.horizontal.3")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("清空当前对话？", isPresented: $isClearConfirmPresented, titleVisibility: .visible) {
            Button("清空对话", role: .destructive) {
                viewModel.clearConversation()
            }
            Button("重置全部内容", role: .destructive) {
                screenshotPreviewImage = nil
                viewModel.resetAll()
            }
            Button("取消", role: .cancel) {}
        }
        .task {
            await viewModel.prepare()
            hasConfiguredAPIKey = AIConfigurationStore.shared.loadConfiguration().hasAPIKey
            isContextExpanded = !viewModel.hasConversation && trimmedReceived.isEmpty && trimmedDraft.isEmpty
        }
        .onAppear {
            hasConfiguredAPIKey = AIConfigurationStore.shared.loadConfiguration().hasAPIKey
        }
        .sheet(item: $cropSource) { source in
            EmailAssistantCropImageEditor(image: source.image) { selection in
                Task {
                    await applyCrop(selection, to: source.image)
                }
            }
        }
        .onChange(of: selectedPhotoItem) { newValue in
            guard let newValue else { return }
            Task {
                await loadPhotoItem(newValue)
                selectedPhotoItem = nil
            }
        }
    }

    // MARK: - Layout

    private var chatLayout: some View {
        VStack(spacing: 0) {
            contextHeader
                .padding(.horizontal, ESUI.screenHorizontalPadding)
                .padding(.top, ESUI.Space.xs)
                .padding(.bottom, ESUI.Space.sm)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: ESUI.Space.md) {
                        if viewModel.completedConversation.isEmpty {
                            emptyConversationState
                                .padding(.top, ESUI.Space.xxl)
                        } else {
                            ForEach(viewModel.completedConversation) { message in
                                messageRow(message)
                                    .id(message.id)
                            }
                        }

                        if viewModel.isGenerating {
                            generatingBubble
                                .id(generatingAnchorID)
                        }
                    }
                    .padding(.horizontal, ESUI.screenHorizontalPadding)
                    .padding(.bottom, ESUI.Space.md)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: viewModel.completedConversation.count) { _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: viewModel.isGenerating) { _ in
                    scrollToBottom(proxy)
                }
            }

            composer
        }
    }

    private var generatingAnchorID: String { "generating-anchor" }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) {
            if viewModel.isGenerating {
                proxy.scrollTo(generatingAnchorID, anchor: .bottom)
            } else if let last = viewModel.completedConversation.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    // MARK: - Context header

    private var contextHeader: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    isContextExpanded.toggle()
                }
            } label: {
                HStack(spacing: ESUI.Space.sm) {
                    Image(systemName: viewModel.mode.iconName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.accentColor.opacity(0.14))
                        )

                    VStack(alignment: .leading, spacing: 1) {
                        Text(viewModel.mode.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text(contextSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isContextExpanded ? 180 : 0))
                }
                .padding(ESUI.Space.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isContextExpanded {
                VStack(spacing: ESUI.Space.sm) {
                    Divider()

                    Picker("模式", selection: $viewModel.mode) {
                        ForEach(EmailAssistantMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if viewModel.mode == .reply {
                        contextEditor(
                            title: "来信",
                            placeholder: "粘贴收到的邮件",
                            text: $viewModel.receivedEmailText,
                            minHeight: 108,
                            showsOCR: true
                        )

                        if let screenshotPreviewImage {
                            Image(uiImage: screenshotPreviewImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 120)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }

                    contextEditor(
                        title: viewModel.mode == .reply ? "回复要点" : "邮件目标",
                        placeholder: viewModel.mode == .reply ? "想表达什么" : "写邮件目标或关键信息",
                        text: $viewModel.originalDraft,
                        minHeight: 88,
                        showsOCR: false
                    )
                }
                .padding(.horizontal, ESUI.Space.sm)
                .padding(.bottom, ESUI.Space.sm)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func contextEditor(
        title: String,
        placeholder: String,
        text: Binding<String>,
        minHeight: CGFloat,
        showsOCR: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: ESUI.Space.xxs) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if showsOCR {
                    ocrButton
                }
            }

            ZStack(alignment: .topLeading) {
                if text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(placeholder)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }

                TextEditor(text: text)
                    .font(.subheadline)
                    .frame(minHeight: minHeight)
                    .scrollContentBackground(.hidden)
            }
            .padding(ESUI.Space.xs)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
            )
        }
    }

    private var ocrButton: some View {
        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            HStack(spacing: 4) {
                if viewModel.isRecognizingScreenshot {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "text.viewfinder")
                }
                Text(viewModel.isRecognizingScreenshot ? "识别中" : "截图识别")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isRecognizingScreenshot)
    }

    // MARK: - Conversation

    private func messageRow(_ message: EmailAssistantThreadMessage) -> some View {
        HStack(spacing: 0) {
            if message.role == .assistant {
                assistantBubble(message)
                Spacer(minLength: 32)
            } else {
                Spacer(minLength: 48)
                userBubble(message)
            }
        }
    }

    private func assistantBubble(_ message: EmailAssistantThreadMessage) -> some View {
        let text = message.structuredOutput?.formattedText ?? message.content

        return VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            if let subject = message.structuredOutput?.subject, !subject.isEmpty {
                Text(subject.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }

            Text(message.structuredOutput?.body ?? text)
                .font(.callout)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack(spacing: ESUI.Space.xs) {
                bubbleAction(title: "复制", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = text
                    viewModel.presentNotice(tone: .success, message: "已复制。")
                }

                bubbleAction(title: "再改改", systemImage: "pencil") {
                    isComposerFocused = true
                }
            }
        }
        .padding(ESUI.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 18,
                bottomLeadingRadius: 6,
                bottomTrailingRadius: 18,
                topTrailingRadius: 18,
                style: .continuous
            )
            .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func bubbleAction(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, ESUI.Space.sm)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
    }

    private func userBubble(_ message: EmailAssistantThreadMessage) -> some View {
        Text(message.content)
            .font(.callout)
            .foregroundStyle(.white)
            .textSelection(.enabled)
            .padding(.horizontal, ESUI.Space.sm)
            .padding(.vertical, 10)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 18,
                    bottomLeadingRadius: 18,
                    bottomTrailingRadius: 6,
                    topTrailingRadius: 18,
                    style: .continuous
                )
                .fill(Color.accentColor)
            )
    }

    private var generatingBubble: some View {
        HStack(spacing: ESUI.Space.xs) {
            ProgressView().controlSize(.small)
            Text("正在生成…")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 32)
        }
        .padding(ESUI.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var emptyConversationState: some View {
        VStack(spacing: ESUI.Space.md) {
            ESEmptyState(
                title: "开始写一封邮件",
                message: viewModel.mode == .reply
                    ? "粘贴来信、写下回复要点，或直接在下方说明需求。"
                    : "直接在下方说明这封邮件要表达什么。",
                systemImage: "envelope.badge"
            )

            HStack(spacing: ESUI.Space.xs) {
                ForEach(quickPrompts, id: \.self) { prompt in
                    Button {
                        viewModel.messageDraft = prompt
                        Task { await viewModel.sendCurrentMessage() }
                    } label: {
                        Text(prompt)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, ESUI.Space.sm)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
            }
        }
    }

    private var quickPrompts: [String] {
        viewModel.mode == .reply
            ? ["礼貌确认收到", "婉拒并给替代方案", "确认时间并跟进"]
            : ["先给一版可直接发送的", "催一下进度", "感谢并总结要点"]
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: ESUI.Space.xs) {
            if let message = cautionNoticeMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(ESUI.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            GlassEffectContainer(spacing: ESUI.Space.xs) {
                HStack(spacing: ESUI.Space.xs) {
                    optionChip(title: "语气", value: viewModel.tone.title) {
                        ForEach(EmailAssistantTone.allCases) { tone in
                            Button(tone.title) { viewModel.tone = tone }
                        }
                    }

                    optionChip(title: "长度", value: viewModel.length.title) {
                        ForEach(EmailAssistantLength.allCases) { length in
                            Button(length.title) { viewModel.length = length }
                        }
                    }

                    optionChip(title: "场景", value: viewModel.scenario.title) {
                        ForEach(EmailAssistantScenario.allCases) { scenario in
                            Button(scenario.title) { viewModel.scenario = scenario }
                        }
                    }

                    Spacer(minLength: 0)
                }
            }

            HStack(alignment: .bottom, spacing: ESUI.Space.xs) {
                TextField(
                    viewModel.hasConversation ? "继续修改，如「语气再正式一点」" : "说明需求，或直接点发送",
                    text: $viewModel.messageDraft,
                    axis: .vertical
                )
                .font(.callout)
                .lineLimit(1 ... 4)
                .focused($isComposerFocused)
                .padding(.horizontal, ESUI.Space.md)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: .capsule)

                Button {
                    isComposerFocused = false
                    Task { await viewModel.sendCurrentMessage() }
                } label: {
                    Group {
                        if viewModel.isGenerating {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle().fill(viewModel.canSend ? Color.accentColor : Color(.tertiaryLabel))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canSend)
                .padding(.bottom, 3)
            }
        }
        .padding(.horizontal, ESUI.screenHorizontalPadding)
        .padding(.top, ESUI.Space.xs)
        .padding(.bottom, ESUI.Space.xs)
    }

    private func optionChip<Content: View>(
        title: String,
        value: String,
        @ViewBuilder menu: () -> Content
    ) -> some View {
        Menu {
            menu()
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, ESUI.Space.sm)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private var cautionNoticeMessage: String? {
        guard let notice = viewModel.notice, notice.tone == .caution else { return nil }
        return notice.message
    }

    // MARK: - Actions

    private func loadPhotoItem(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                viewModel.presentNotice(
                    tone: .caution,
                    message: EmailAssistantError.imageLoadFailed.localizedDescription
                )
                return
            }

            let normalizedImage = ImageOCRService.normalizedDisplayImage(image)

            await MainActor.run {
                cropSource = EmailAssistantCropSource(image: normalizedImage)
            }
        } catch {
            viewModel.presentNotice(tone: .caution, message: error.localizedDescription)
        }
    }

    @MainActor
    private func applyCrop(_ selection: ImageCropSelection, to image: UIImage) async {
        guard let croppedImage = ImageOCRService.cropImage(image, selection: selection),
              let croppedData = ImageOCRService.storedImageData(from: croppedImage) else {
            viewModel.presentNotice(
                tone: .caution,
                message: EmailAssistantError.cropFailed.localizedDescription
            )
            return
        }

        screenshotPreviewImage = croppedImage
        await viewModel.importScreenshotText(from: croppedData)
    }
}

private struct EmailAssistantCropSource: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct EmailAssistantCropImageEditor: View {
    @Environment(\.dismiss) private var dismiss

    let image: UIImage
    let onConfirm: (ImageCropSelection) -> Void

    @State private var selectionRect: CGRect?
    @State private var canvasSize: CGSize = .zero

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let resolvedCanvasSize = aspectFitSize(for: image.size, in: proxy.size)

                ZStack {
                    Color.black.ignoresSafeArea()

                    VStack {
                        Spacer()

                        ZStack(alignment: .topLeading) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: resolvedCanvasSize.width, height: resolvedCanvasSize.height)

                            Rectangle()
                                .fill(Color.clear)
                                .contentShape(Rectangle())
                                .frame(width: resolvedCanvasSize.width, height: resolvedCanvasSize.height)
                                .gesture(selectionGesture(in: resolvedCanvasSize))

                            if let selectionRect {
                                Rectangle()
                                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                                    .frame(width: selectionRect.width, height: selectionRect.height)
                                    .offset(x: selectionRect.minX, y: selectionRect.minY)
                            }
                        }
                        .frame(width: resolvedCanvasSize.width, height: resolvedCanvasSize.height)

                        Spacer()

                        Text("拖动调整区域")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, ESUI.Space.md)
                            .padding(.vertical, ESUI.Space.sm)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(ESUI.surface)
                            )
                            .padding(.bottom, ESUI.Space.lg)
                    }
                }
                .onAppear {
                    updateCanvasSize(resolvedCanvasSize)
                }
                .onChange(of: proxy.size) { _ in
                    updateCanvasSize(resolvedCanvasSize)
                }
            }
            .navigationTitle("裁剪截图")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("继续") {
                        guard let selection = cropSelection else { return }
                        onConfirm(selection)
                        dismiss()
                    }
                    .disabled(cropSelection == nil)
                }
            }
        }
    }

    private var cropSelection: ImageCropSelection? {
        guard let normalizedRect = normalizedSelectionRect else { return nil }
        return ImageCropSelection(
            normalizedRect: normalizedRect,
            displaySize: canvasSize
        )
    }

    private var normalizedSelectionRect: CGRect? {
        guard let selectionRect else { return nil }
        guard canvasSize.width > 0, canvasSize.height > 0 else { return nil }

        let normalizedRect = CGRect(
            x: selectionRect.minX / canvasSize.width,
            y: selectionRect.minY / canvasSize.height,
            width: selectionRect.width / canvasSize.width,
            height: selectionRect.height / canvasSize.height
        )

        guard normalizedRect.width > 0.02, normalizedRect.height > 0.02 else {
            return nil
        }

        return normalizedRect
    }

    private func selectionGesture(in canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = clamped(value.startLocation, to: canvasSize)
                let current = clamped(value.location, to: canvasSize)
                selectionRect = CGRect(
                    x: min(start.x, current.x),
                    y: min(start.y, current.y),
                    width: abs(current.x - start.x),
                    height: abs(current.y - start.y)
                )
            }
    }

    private func clamped(_ point: CGPoint, to canvasSize: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), canvasSize.width),
            y: min(max(point.y, 0), canvasSize.height)
        )
    }

    private func aspectFitSize(for imageSize: CGSize, in containerSize: CGSize) -> CGSize {
        guard imageSize.width > 0,
              imageSize.height > 0,
              containerSize.width > 0,
              containerSize.height > 0 else {
            return containerSize
        }

        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    private func updateCanvasSize(_ newSize: CGSize) {
        guard newSize.width > 0, newSize.height > 0 else { return }
        canvasSize = newSize
        selectionRect = CGRect(origin: .zero, size: newSize).insetBy(dx: 6, dy: 6)
    }
}

#Preview {
    NavigationStack {
        EmailAssistantView()
            .environmentObject(AppNavigationState())
    }
}
