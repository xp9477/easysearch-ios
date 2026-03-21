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
                if let notice = viewModel.notice {
                    noticeBanner(notice, onDarkBackground: false)
                }
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
            sectionTitle("输入")

            VStack(spacing: 12) {
                modeSelector

                HStack(spacing: 12) {
                    Picker("语气", selection: $viewModel.tone) {
                        ForEach(EmailAssistantTone.allCases) { tone in
                            Text(tone.title).tag(tone)
                        }
                    }

                    Picker("长度", selection: $viewModel.length) {
                        ForEach(EmailAssistantLength.allCases) { length in
                            Text(length.title).tag(length)
                        }
                    }
                }

                Picker("场景", selection: $viewModel.scenario) {
                    ForEach(EmailAssistantScenario.allCases) { scenario in
                        Text(scenario.title).tag(scenario)
                    }
                }
                .pickerStyle(.menu)
            }

            VStack(spacing: 14) {
                if viewModel.mode == .reply {
                    TextEditorCard(
                        title: "来信",
                        placeholder: "粘贴收到的邮件",
                        text: $viewModel.receivedEmailText,
                        minHeight: 150
                    )

                    ocrCard
                }

                TextEditorCard(
                    title: "草稿",
                    placeholder: viewModel.mode == .reply ? "写回复要点或现有草稿" : "写邮件目标、关键信息或现有草稿",
                    text: $viewModel.originalDraft,
                    minHeight: 112
                )
            }
        }
        .padding(24)
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
                    .frame(maxWidth: .infinity, minHeight: 78)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(viewModel.mode == mode ? accentColor.opacity(0.12) : Color(.tertiarySystemFill))
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

    private var ocrCard: some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Label("导入截图", systemImage: "photo.on.rectangle")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Capsule(style: .continuous)
                            .fill(accentColor.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)

            if viewModel.isRecognizingScreenshot {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("识别中")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var conversationCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                sectionTitle("结果")

                Spacer(minLength: 12)

                if viewModel.hasConversation {
                    Button(role: .destructive) {
                        viewModel.clearConversation()
                    } label: {
                        Label("清空对话", systemImage: "trash")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                }
            }

            if !viewModel.completedConversation.isEmpty {
                VStack(spacing: 14) {
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

                    Button("重置全部") {
                        viewModel.resetAll()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(24)
        .cardStyle()
    }

    private func messageRow(_ message: EmailAssistantThreadMessage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(message.role == .assistant ? "结果" : "要求")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(message.createdAt.formatted(.dateTime.hour().minute()))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if let output = message.structuredOutput {
                VStack(alignment: .leading, spacing: 10) {
                    Text(output.formattedText)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)

                    HStack(spacing: 12) {
                        Button("复制") {
                            UIPasteboard.general.string = output.formattedText
                            viewModel.presentNotice(tone: .success, message: "已复制。")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } else {
                Text(message.content)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func loadPhotoItem(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                viewModel.presentNotice(tone: .caution, message: EmailAssistantError.imageLoadFailed.localizedDescription)
                return
            }

            await MainActor.run {
                cropSource = EmailAssistantCropSource(image: image)
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
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func noticeBanner(_ notice: EmailAssistantNotice, onDarkBackground: Bool) -> some View {
        let tint: Color = {
            switch notice.tone {
            case .neutral:
                return onDarkBackground ? .white.opacity(0.82) : .secondary
            case .success:
                return .green
            case .caution:
                return .orange
            }
        }()

        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: notice.tone == .caution ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tint)

            Text(notice.message)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(onDarkBackground ? .white : .primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(onDarkBackground ? Color.white.opacity(0.08) : Color(.tertiarySystemFill))
        )
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.tertiarySystemFill))

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
