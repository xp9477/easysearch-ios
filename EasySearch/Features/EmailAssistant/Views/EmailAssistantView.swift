import PhotosUI
import SwiftUI
import UIKit

public struct EmailAssistantView: View {
    @StateObject private var viewModel = EmailAssistantViewModel()
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var cropSource: EmailAssistantCropSource?

    private let accentColor = Color.blue

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                contextCard
                conversationCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("邮件助手")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .task {
            await viewModel.prepare()
        }
        .sheet(item: $cropSource) { source in
            EmailAssistantCropImageEditor(image: source.image) { normalizedRect in
                Task {
                    await applyCrop(normalizedRect, to: source.image)
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

    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("写邮件")
            modeSelector
            preferenceStrip

            VStack(spacing: 14) {
                if viewModel.mode == .reply {
                    TextEditorCard(
                        title: "来信",
                        placeholder: "粘贴收到的邮件",
                        text: $viewModel.receivedEmailText,
                        minHeight: 156,
                        accessory: AnyView(ocrInlineButton)
                    )
                }

                TextEditorCard(
                    title: "草稿",
                    placeholder: viewModel.mode == .reply ? "写回复要点或现有草稿" : "写邮件目标、关键信息或现有草稿",
                    text: $viewModel.originalDraft,
                    minHeight: viewModel.mode == .reply ? 112 : 148
                )
            }
        }
        .padding(20)
        .cardStyle()
    }

    private var modeSelector: some View {
        HStack(spacing: 10) {
            ForEach(EmailAssistantMode.allCases) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        viewModel.mode = mode
                    }
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: mode.iconName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(viewModel.mode == mode ? accentColor : .secondary)

                        Text(mode.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(viewModel.mode == mode ? .primary : .secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity, minHeight: 72)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(viewModel.mode == mode ? accentColor.opacity(0.14) : Color(.tertiarySystemFill))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(viewModel.mode == mode ? accentColor.opacity(0.45) : Color.primary.opacity(0.06), lineWidth: viewModel.mode == mode ? 1.5 : 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var preferenceStrip: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
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
            controlPill(title: "长度", value: viewModel.length.title, systemImage: "ruler")
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
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(accentColor.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isRecognizingScreenshot)
    }

    private var conversationCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                sectionTitle("对话")

                Spacer(minLength: 12)

                if viewModel.hasConversation {
                    Button(role: .destructive) {
                        viewModel.clearConversation()
                    } label: {
                        Label("清空对话", systemImage: "trash")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red.opacity(0.82))
                }
            }

            if viewModel.completedConversation.isEmpty {
                emptyConversationState
            } else {
                VStack(spacing: 12) {
                    ForEach(viewModel.completedConversation) { message in
                        messageRow(message)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                TextField("输入要求或继续修改", text: $viewModel.messageDraft, axis: .vertical)
                    .lineLimit(2 ... 5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(.tertiarySystemFill))
                    )

                HStack(spacing: 12) {
                    Button("重置全部") {
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
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accentColor)
                    .disabled(!viewModel.canSend)
                }

                if let message = cautionNoticeMessage {
                    inlineErrorMessage(message)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.tertiarySystemFill).opacity(0.72))
            )
        }
        .padding(20)
        .cardStyle()
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

    private func applyCrop(_ normalizedRect: CGRect, to image: UIImage) async {
        guard let croppedImage = ImageOCRService.cropImage(image, normalizedRect: normalizedRect),
              let croppedData = ImageOCRService.storedImageData(from: croppedImage) else {
            viewModel.presentNotice(tone: .caution, message: EmailAssistantError.cropFailed.localizedDescription)
            return
        }

        await viewModel.importScreenshotText(from: croppedData)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func controlPill(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.tertiarySystemFill))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    private var emptyConversationState: some View {
        HStack(spacing: 12) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accentColor)

            Text("生成后会显示在这里")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.tertiarySystemFill))
        )
    }

    private var cautionNoticeMessage: String? {
        guard let notice = viewModel.notice,
              notice.tone == .caution else {
            return nil
        }
        return notice.message
    }

    private func inlineErrorMessage(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.orange)

            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 2)
    }

    private func assistantBubble(_ message: EmailAssistantThreadMessage) -> some View {
        let text = message.structuredOutput?.formattedText ?? message.content

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Label("邮件", systemImage: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accentColor)

                Spacer(minLength: 8)

                Text(message.createdAt.formatted(.dateTime.hour().minute()))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Button("复制") {
                    UIPasteboard.general.string = text
                    viewModel.presentNotice(tone: .success, message: "已复制。")
                }
                .font(.system(size: 12, weight: .semibold))
                .buttonStyle(.bordered)
            }

            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .padding(16)
        .frame(maxWidth: 460, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.tertiarySystemFill))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func userBubble(_ message: EmailAssistantThreadMessage) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            Text(message.createdAt.formatted(.dateTime.hour().minute()))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(message.content)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(accentColor.opacity(0.14))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(accentColor.opacity(0.2), lineWidth: 1)
                )
        }
        .frame(maxWidth: 320, alignment: .trailing)
    }

}

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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                if let accessory {
                    accessory
                }
            }

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                    )

                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(placeholder)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }

                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(minHeight: minHeight)
                    .background(Color.clear)
            }
        }
    }
}

private struct EmailAssistantCropImageEditor: View {
    @Environment(\.dismiss) private var dismiss

    let image: UIImage
    let onConfirm: (CGRect) -> Void

    @State private var selectionRect: CGRect?
    @State private var imageFrame: CGRect = .zero
    private let cropCoordinateSpace = "EmailAssistantCropCanvas"

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let containerFrame = CGRect(origin: .zero, size: proxy.size)
                let resolvedImageFrame = aspectFitRect(
                    for: image.size,
                    in: containerFrame.insetBy(dx: 20, dy: 20)
                )

                ZStack {
                    Color(.systemGroupedBackground)
                        .ignoresSafeArea()

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: resolvedImageFrame.width, height: resolvedImageFrame.height)
                        .position(x: resolvedImageFrame.midX, y: resolvedImageFrame.midY)

                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .frame(width: resolvedImageFrame.width, height: resolvedImageFrame.height)
                        .position(x: resolvedImageFrame.midX, y: resolvedImageFrame.midY)
                        .gesture(selectionGesture(in: resolvedImageFrame))

                    if let selectionRect {
                        Rectangle()
                            .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                            .frame(width: selectionRect.width, height: selectionRect.height)
                            .position(x: selectionRect.midX, y: selectionRect.midY)
                    }

                    VStack {
                        Spacer()

                        Text("拖动调整区域")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color(.secondarySystemGroupedBackground))
                            )
                            .padding(.bottom, 20)
                    }
                }
                .coordinateSpace(name: cropCoordinateSpace)
                .onAppear {
                    imageFrame = resolvedImageFrame
                    if selectionRect == nil {
                        selectionRect = resolvedImageFrame.insetBy(dx: 6, dy: 6)
                    }
                }
                .onChange(of: proxy.size) { _ in
                    imageFrame = resolvedImageFrame
                    if selectionRect == nil {
                        selectionRect = resolvedImageFrame.insetBy(dx: 6, dy: 6)
                    }
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
                        guard let normalizedRect = normalizedSelectionRect else { return }
                        onConfirm(normalizedRect)
                        dismiss()
                    }
                    .disabled(normalizedSelectionRect == nil)
                }
            }
        }
    }

    private var normalizedSelectionRect: CGRect? {
        guard let selectionRect else { return nil }
        let frame = imageFrame
        guard frame.width > 0, frame.height > 0 else { return nil }

        let normalizedRect = CGRect(
            x: (selectionRect.minX - frame.minX) / frame.width,
            y: (selectionRect.minY - frame.minY) / frame.height,
            width: selectionRect.width / frame.width,
            height: selectionRect.height / frame.height
        )

        guard normalizedRect.width > 0.02, normalizedRect.height > 0.02 else {
            return nil
        }

        return normalizedRect
    }

    private func selectionGesture(in imageFrame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(cropCoordinateSpace))
            .onChanged { value in
                let start = clamped(value.startLocation, to: imageFrame)
                let current = clamped(value.location, to: imageFrame)
                selectionRect = CGRect(
                    x: min(start.x, current.x),
                    y: min(start.y, current.y),
                    width: abs(current.x - start.x),
                    height: abs(current.y - start.y)
                )
            }
    }

    private func clamped(_ point: CGPoint, to frame: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, frame.minX), frame.maxX),
            y: min(max(point.y, frame.minY), frame.maxY)
        )
    }

    private func aspectFitRect(for imageSize: CGSize, in containerRect: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return containerRect }

        let scale = min(containerRect.width / imageSize.width, containerRect.height / imageSize.height)
        let fittedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)

        return CGRect(
            x: containerRect.midX - fittedSize.width / 2,
            y: containerRect.midY - fittedSize.height / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }
}

#Preview {
    NavigationStack {
        EmailAssistantView()
            .environmentObject(AppNavigationState())
    }
}
