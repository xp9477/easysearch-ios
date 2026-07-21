import PhotosUI
import SwiftUI
import UIKit

public struct EmailAssistantView: View {
    @EnvironmentObject private var navigationState: AppNavigationState
    @StateObject private var viewModel = EmailAssistantViewModel()
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var cropSource: EmailAssistantCropSource?
    @State private var screenshotPreviewImage: UIImage?

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ESUI.sectionSpacing) {
                contextCard
                conversationCard
            }
            .padding(.horizontal, ESUI.screenHorizontalPadding)
            .padding(.top, ESUI.Space.md)
            .padding(.bottom, ESUI.Space.xxxl)
        }
        .esScreenBackground()
        .navigationTitle("邮件助手")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .task {
            await viewModel.prepare()
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

    // MARK: - Context

    private var contextCard: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.md) {
            ESSectionHeader(title: "写邮件")
            modeSelector
            preferenceStrip

            VStack(spacing: ESUI.Space.sm) {
                if viewModel.mode == .reply {
                    TextEditorCard(
                        title: "来信",
                        placeholder: "粘贴收到的邮件",
                        text: $viewModel.receivedEmailText,
                        minHeight: 156,
                        accessory: AnyView(ocrInlineButton)
                    )

                    if let screenshotPreviewImage {
                        cropPreviewCard(screenshotPreviewImage)
                    }
                }

                TextEditorCard(
                    title: "草稿",
                    placeholder: viewModel.mode == .reply ? "写回复要点或现有草稿" : "写邮件目标、关键信息或现有草稿",
                    text: $viewModel.originalDraft,
                    minHeight: viewModel.mode == .reply ? 112 : 148
                )
            }

            Button {
                navigationState.openSettings(.emailAssistant)
            } label: {
                Label("AI 配置", systemImage: "slider.horizontal.3")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
        .esCard()
    }

    private var modeSelector: some View {
        HStack(spacing: ESUI.Space.sm) {
            ForEach(EmailAssistantMode.allCases) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        viewModel.mode = mode
                    }
                } label: {
                    VStack(spacing: ESUI.Space.xs) {
                        Image(systemName: mode.iconName)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(viewModel.mode == mode ? Color.accentColor : .secondary)

                        Text(mode.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(viewModel.mode == mode ? .primary : .secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity, minHeight: 72)
                    .padding(.horizontal, ESUI.Space.sm)
                    .background(
                        RoundedRectangle(cornerRadius: ESUI.cardCornerRadius, style: .continuous)
                            .fill(viewModel.mode == mode ? Color.accentColor.opacity(0.12) : ESUI.fill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: ESUI.cardCornerRadius, style: .continuous)
                            .stroke(
                                viewModel.mode == mode ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.06),
                                lineWidth: viewModel.mode == mode ? 1.5 : 1
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var preferenceStrip: some View {
        VStack(spacing: ESUI.Space.sm) {
            HStack(spacing: ESUI.Space.sm) {
                toneMenu
                lengthMenu
            }
            scenarioMenu
        }
    }

    private var toneMenu: some View {
        Menu {
            ForEach(EmailAssistantTone.allCases) { tone in
                Button(tone.title) {
                    viewModel.tone = tone
                }
            }
        } label: {
            controlPill(title: "语气", value: viewModel.tone.title, systemImage: "quote.bubble")
        }
        .buttonStyle(.plain)
    }

    private var lengthMenu: some View {
        Menu {
            ForEach(EmailAssistantLength.allCases) { length in
                Button(length.title) {
                    viewModel.length = length
                }
            }
        } label: {
            controlPill(title: "长度", value: viewModel.length.title, systemImage: "text.alignleft")
        }
        .buttonStyle(.plain)
    }

    private var scenarioMenu: some View {
        Menu {
            ForEach(EmailAssistantScenario.allCases) { scenario in
                Button(scenario.title) {
                    viewModel.scenario = scenario
                }
            }
        } label: {
            controlPill(title: "场景", value: viewModel.scenario.title, systemImage: "tag")
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private var ocrInlineButton: some View {
        let isRecognizing = viewModel.isRecognizingScreenshot

        return PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            HStack(spacing: 6) {
                if isRecognizing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "photo.badge.plus")
                }

                Text(isRecognizing ? "识别中" : "截图")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, ESUI.Space.sm)
            .padding(.vertical, ESUI.Space.xs)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isRecognizingScreenshot)
    }

    // MARK: - Conversation

    private var conversationCard: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.md) {
            HStack(alignment: .center, spacing: ESUI.Space.sm) {
                Text("对话")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer(minLength: ESUI.Space.sm)

                if viewModel.hasConversation {
                    Button(role: .destructive) {
                        viewModel.clearConversation()
                    } label: {
                        Label("清空对话", systemImage: "trash")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }

            if viewModel.completedConversation.isEmpty {
                emptyConversationState
            } else {
                VStack(spacing: ESUI.Space.sm) {
                    ForEach(viewModel.completedConversation) { message in
                        messageRow(message)
                    }
                }
            }

            VStack(alignment: .leading, spacing: ESUI.Space.sm) {
                TextField("输入要求或继续修改", text: $viewModel.messageDraft, axis: .vertical)
                    .lineLimit(2 ... 5)
                    .padding(.horizontal, ESUI.Space.sm)
                    .padding(.vertical, ESUI.Space.sm)
                    .background(
                        RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                            .fill(ESUI.fill)
                    )

                HStack(spacing: ESUI.Space.sm) {
                    Button("重置全部") {
                        screenshotPreviewImage = nil
                        viewModel.resetAll()
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task {
                            await viewModel.sendCurrentMessage()
                        }
                    } label: {
                        HStack {
                            Label(viewModel.isGenerating ? "生成中" : "生成邮件", systemImage: "sparkles")
                            Spacer()
                            if viewModel.isGenerating {
                                ProgressView()
                            }
                        }
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, ESUI.Space.xs)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canSend)
                }

                if let message = cautionNoticeMessage {
                    ESStatusBanner(
                        title: message,
                        systemImage: "exclamationmark.triangle.fill",
                        tone: .warning
                    )
                }
            }
            .padding(ESUI.Space.sm)
            .background(
                RoundedRectangle(cornerRadius: ESUI.cardCornerRadius, style: .continuous)
                    .fill(ESUI.fill.opacity(0.72))
            )
        }
        .esCard()
    }

    private func messageRow(_ message: EmailAssistantThreadMessage) -> some View {
        HStack {
            if message.role == .assistant {
                assistantBubble(message)
                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40)
                userBubble(message)
            }
        }
    }

    private func loadPhotoItem(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                viewModel.presentNotice(tone: .caution, message: EmailAssistantError.imageLoadFailed.localizedDescription)
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
            viewModel.presentNotice(tone: .caution, message: EmailAssistantError.cropFailed.localizedDescription)
            return
        }

        screenshotPreviewImage = croppedImage
        await viewModel.importScreenshotText(from: croppedData)
    }

    private func controlPill(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: ESUI.Space.sm) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Spacer(minLength: ESUI.Space.xs)

            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, ESUI.Space.sm)
        .padding(.vertical, ESUI.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                .fill(ESUI.fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    private func cropPreviewCard(_ image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            Text("OCR 预览")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(maxHeight: 170)
                .clipShape(RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        }
    }

    private var emptyConversationState: some View {
        ESEmptyState(
            title: "还没有生成内容",
            message: "填写上下文后点「生成邮件」，结果会显示在这里。",
            systemImage: "bubble.left.and.text.bubble.right"
        )
    }

    private var cautionNoticeMessage: String? {
        guard let notice = viewModel.notice,
              notice.tone == .caution else {
            return nil
        }
        return notice.message
    }

    private func assistantBubble(_ message: EmailAssistantThreadMessage) -> some View {
        let text = message.structuredOutput?.formattedText ?? message.content

        return VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            HStack(alignment: .center, spacing: ESUI.Space.sm) {
                Label("邮件", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)

                Spacer(minLength: ESUI.Space.xs)

                Text(message.createdAt.formatted(.dateTime.hour().minute()))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Button("复制") {
                    UIPasteboard.general.string = text
                    viewModel.presentNotice(tone: .success, message: "已复制。")
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
            }

            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .padding(ESUI.Space.md)
        .frame(maxWidth: 460, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ESUI.cardCornerRadius, style: .continuous)
                .fill(ESUI.fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ESUI.cardCornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func userBubble(_ message: EmailAssistantThreadMessage) -> some View {
        VStack(alignment: .trailing, spacing: ESUI.Space.xs) {
            Text(message.createdAt.formatted(.dateTime.hour().minute()))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(message.content)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .padding(.horizontal, ESUI.Space.sm)
                .padding(.vertical, ESUI.Space.sm)
                .background(
                    RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                )
        }
        .frame(maxWidth: 320, alignment: .trailing)
    }
}

// MARK: - Supporting

private struct EmailAssistantCropSource: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct TextEditorCard: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let minHeight: CGFloat
    let accessory: AnyView?

    init(
        title: String,
        placeholder: String,
        text: Binding<String>,
        minHeight: CGFloat,
        accessory: AnyView? = nil
    ) {
        self.title = title
        self.placeholder = placeholder
        _text = text
        self.minHeight = minHeight
        self.accessory = accessory
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.xs) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if let accessory {
                    accessory
                }
            }

            ZStack(alignment: .topLeading) {
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                }

                TextEditor(text: $text)
                    .font(.body)
                    .frame(minHeight: minHeight)
                    .scrollContentBackground(.hidden)
            }
            .padding(ESUI.Space.xs)
            .background(
                RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                    .fill(ESUI.fill)
            )
        }
    }
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
