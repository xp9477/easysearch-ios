import PhotosUI
import SwiftUI
import UIKit

public struct ImageTranslateView: View {
    @StateObject private var viewModel = ImageTranslateViewModel()
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var cameraImage: UIImage?
    @State private var isPhotoPickerPresented = false
    @State private var isCameraPresented = false
    @State private var isCropSheetPresented = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heroCard

                if let notice = viewModel.notice {
                    noticeBanner(notice)
                }

                historyCard
                imageCard
                editorCard

                if viewModel.hasTranslation {
                    translationCard
                }

                if viewModel.shouldShowConversation {
                    conversationCard
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("截图翻译")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .task {
            await viewModel.prepare()
        }
        .photosPicker(
            isPresented: $isPhotoPickerPresented,
            selection: $selectedPhotoItem,
            matching: .images
        )
        .onChange(of: selectedPhotoItem) { item in
            guard let item else { return }
            Task {
                await loadPhoto(from: item)
                selectedPhotoItem = nil
            }
        }
        .onChange(of: cameraImage) { image in
            guard let image else { return }
            Task {
                await viewModel.importImage(image, from: .camera)
                cameraImage = nil
            }
        }
        .sheet(isPresented: $isCameraPresented) {
            CameraImagePicker(image: $cameraImage)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $isCropSheetPresented) {
            if let selectedImage = viewModel.selectedImage {
                CropImageEditor(image: selectedImage) { rect in
                    Task {
                        await viewModel.cropCurrentImage(to: rect)
                    }
                }
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("DeepSeek OCR")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.74))

                    Text("截图 / 拍照翻译")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)

                    Text("先在本地识别图片文字，再把识别结果交给 DeepSeek 做翻译和多轮优化。识别文本可手动修改，支持最近会话恢复和局部裁剪翻译。")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 8) {
                    heroChip(
                        title: viewModel.hasConfiguredAPIKey ? "DeepSeek 已配置" : "待配置 API Key",
                        color: viewModel.hasConfiguredAPIKey ? .green : .orange
                    )

                    heroChip(title: viewModel.currentModel, color: .white.opacity(0.18))
                }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("翻译到")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.76))

                    Picker(
                        "翻译到",
                        selection: Binding(
                            get: { viewModel.targetLanguage },
                            set: { newValue in
                                Task {
                                    await viewModel.updateTargetLanguage(newValue)
                                }
                            }
                        )
                    ) {
                        ForEach(ImageTranslateTargetLanguage.allCases) { language in
                            Text(language.title).tag(language)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.white)
                }

                Spacer()

                Button {
                    viewModel.startFreshSession()
                } label: {
                    Label("新会话", systemImage: "plus.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.14))
                        )
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                actionButton(
                    title: "粘贴截图",
                    icon: "doc.on.clipboard",
                    fill: .white.opacity(0.14),
                    foreground: .white
                ) {
                    Task {
                        await viewModel.importClipboardImage()
                    }
                }

                actionButton(
                    title: "选图片",
                    icon: "photo.on.rectangle.angled",
                    fill: .white.opacity(0.14),
                    foreground: .white
                ) {
                    isPhotoPickerPresented = true
                }

                actionButton(
                    title: "拍照",
                    icon: "camera.fill",
                    fill: .white.opacity(0.14),
                    foreground: .white,
                    isEnabled: UIImagePickerController.isSourceTypeAvailable(.camera)
                ) {
                    guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                        viewModel.presentNotice(
                            tone: .caution,
                            message: ImageTranslateError.cameraUnavailable.localizedDescription
                        )
                        return
                    }
                    isCameraPresented = true
                }
            }

            infoStrip(
                icon: "lock.shield",
                text: viewModel.hasConfiguredAPIKey
                    ? "图片 OCR 在本地完成，发送给 DeepSeek 的只有识别后的文字内容。"
                    : "本地 OCR 可直接使用。要启用 AI 翻译和多轮讨论，请到“设置”页配置 DeepSeek API Key。"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.10, green: 0.36, blue: 0.48),
                            Color(red: 0.04, green: 0.18, blue: 0.27)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                eyebrow: "History",
                title: "最近会话",
                description: viewModel.hasHistory
                    ? "会自动保存最近 20 条截图翻译记录，点一条即可恢复继续讨论。"
                    : "首个翻译结果生成后，会自动进入最近会话。"
            )

            if viewModel.history.isEmpty {
                emptyState(
                    icon: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    title: "还没有历史记录",
                    description: "先完成一次翻译，这里会保留最近会话，方便继续修改或回看。"
                )
            } else {
                VStack(spacing: 12) {
                    ForEach(viewModel.history) { record in
                        historyRow(record)
                    }
                }
            }
        }
        .padding(24)
        .cardStyle()
    }

    private var imageCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                eyebrow: "Image",
                title: "图片预览",
                description: viewModel.selectedImage == nil
                    ? "支持拍照、相册或剪贴板图片。即使暂时不选图，也可以直接在下面粘贴文本后翻译。"
                    : "当前图片已经载入。需要局部翻译时，直接裁剪目标区域即可。"
            )

            if let image = viewModel.selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )

                HStack(spacing: 10) {
                    statusChip(title: viewModel.imageStatusText, color: .cyan)

                    if viewModel.isRecognizingText {
                        statusChip(title: "识别中", color: .orange)
                    } else if viewModel.isTranslating {
                        statusChip(title: "翻译中", color: .green)
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        isCropSheetPresented = true
                    } label: {
                        Label("局部裁剪翻译", systemImage: "crop")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .tint(.cyan)
                    .disabled(viewModel.isRecognizingText || viewModel.isTranslating)

                    Button {
                        Task {
                            await viewModel.reRecognizeSelectedImage()
                        }
                    } label: {
                        Label("整图重识别", systemImage: "viewfinder")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                    .disabled(viewModel.isRecognizingText || viewModel.isTranslating)
                }
            } else {
                emptyState(
                    icon: "photo.badge.plus",
                    title: "还没有图片",
                    description: "顶部三个快捷入口都能直接开始。截图常用“粘贴截图”，拍纸面内容用“拍照”，历史图片从“选图片”进入。"
                )
            }
        }
        .padding(24)
        .cardStyle()
    }

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                eyebrow: "OCR",
                title: "识别结果",
                description: "识别后的文本可以直接改。适合先修正 OCR 错字，再重新发起翻译。"
            )

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.tertiarySystemFill))

                if viewModel.extractedText.isEmpty {
                    Text("识别结果会显示在这里，也可以手动粘贴文本后直接翻译。")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                }

                TextEditor(text: $viewModel.extractedText)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(minHeight: 180)
                    .background(Color.clear)
            }

            HStack(alignment: .center, spacing: 12) {
                Text("当前 \(viewModel.extractedText.count) 字")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                if viewModel.needsRetranslation {
                    Text("识别文本有改动，建议重新翻译")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.orange)
                }

                Spacer()

                if !viewModel.extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        viewModel.copyText(viewModel.extractedText, successMessage: "已复制识别文本。")
                    } label: {
                        Label("复制文本", systemImage: "doc.on.doc")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                }
            }

            Button {
                Task {
                    await viewModel.translateCurrentText()
                }
            } label: {
                HStack {
                    Label(
                        viewModel.hasTranslation ? "重新翻译" : "AI 翻译",
                        systemImage: "sparkles"
                    )
                    Spacer()
                    if viewModel.isTranslating {
                        ProgressView()
                    }
                }
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
            .disabled(!viewModel.canTranslate)
        }
        .padding(24)
        .cardStyle()
    }

    private var translationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                eyebrow: "Translation",
                title: "翻译结果",
                description: "上面是可直接复制的最终译文，下面保留原文 / 译文对照，方便快速校对。"
            )

            VStack(alignment: .leading, spacing: 14) {
                Text(viewModel.latestTranslation)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)

                HStack(spacing: 8) {
                    if let detectedSourceLanguage = viewModel.detectedSourceLanguage,
                       !detectedSourceLanguage.isEmpty {
                        statusChip(title: "源语言 \(detectedSourceLanguage)", color: .secondary)
                    }

                    statusChip(title: "目标 \(viewModel.targetLanguage.title)", color: .cyan)
                }

                if !viewModel.translationNotes.isEmpty {
                    infoStrip(icon: "text.bubble", text: viewModel.translationNotes)
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
            )

            if !viewModel.alignedSections.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("原文 / 译文对照")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)

                    ForEach(viewModel.alignedSections) { section in
                        comparisonRow(section)
                    }
                }
            }

            Button {
                viewModel.copyText(viewModel.latestTranslation, successMessage: "已复制翻译结果。")
            } label: {
                Label("复制翻译", systemImage: "doc.on.doc.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
        }
        .padding(24)
        .cardStyle()
    }

    private var conversationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                eyebrow: "Conversation",
                title: "继续优化 / 讨论",
                description: "支持多轮对话。你可以让它更自然、解释术语、保留原文，或者讨论上下文含义。"
            )

            VStack(spacing: 12) {
                ForEach(viewModel.conversation) { message in
                    conversationBubble(message)
                }
            }

            if !viewModel.suggestedReplies.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(viewModel.suggestedReplies, id: \.self) { suggestion in
                            Button {
                                Task {
                                    await viewModel.sendSuggestedReply(suggestion)
                                }
                            } label: {
                                Text(suggestion)
                                    .font(.system(size: 14, weight: .semibold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(Color.cyan.opacity(0.10))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 12) {
                TextField("继续说：比如“更自然一点”或“解释这句里的术语”", text: $viewModel.composerText, axis: .vertical)
                    .lineLimit(1 ... 4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(.tertiarySystemFill))
                    )

                Button {
                    Task {
                        await viewModel.sendFollowUp()
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(viewModel.canSendFollowUp ? .cyan : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canSendFollowUp)
            }
        }
        .padding(24)
        .cardStyle()
    }

    private func historyRow(_ record: ImageTranslateHistoryRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let data = record.previewImageData,
                   let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: record.imageSource?.symbolName ?? "text.viewfinder")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.cyan)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.cyan.opacity(0.10))
                }
            }
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(record.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(relativeDateText(record.updatedAt))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    statusChip(title: record.targetLanguage.title, color: .cyan)

                    if let detectedSourceLanguage = record.detectedSourceLanguage,
                       !detectedSourceLanguage.isEmpty {
                        statusChip(title: detectedSourceLanguage, color: .secondary)
                    }
                }

                Text(record.sourceSnippet)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text(record.translationSnippet)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            Button(role: .destructive) {
                viewModel.deleteHistoryRecord(record)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .bold))
                    .padding(8)
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.tertiarySystemFill))
        )
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture {
            viewModel.loadHistorySession(record)
        }
    }

    private func comparisonRow(_ section: AlignedTextSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("原文")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(section.sourceText.isEmpty ? " " : section.sourceText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("译文")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(section.translatedText.isEmpty ? " " : section.translatedText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.tertiarySystemFill))
        )
    }

    private func loadPhoto(from item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                viewModel.presentNotice(tone: .caution, message: "图片读取失败，请重新选择。")
                return
            }

            await viewModel.importImage(image, from: .photoLibrary)
        } catch {
            viewModel.presentNotice(tone: .caution, message: error.localizedDescription)
        }
    }

    private func relativeDateText(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_Hans")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func sectionHeader(eyebrow: String, title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.primary)

            Text(description)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func emptyState(icon: String, title: String, description: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)

            Text(description)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.tertiarySystemFill))
        )
    }

    private func infoStrip(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)

            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }

    private func heroChip(title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(color)
            )
    }

    private func statusChip(title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.14))
            )
    }

    private func noticeBanner(_ notice: ImageTranslateNotice) -> some View {
        let tint: Color = {
            switch notice.tone {
            case .neutral:
                return .secondary
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
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(tint.opacity(0.20), lineWidth: 1)
        )
    }

    private func actionButton(
        title: String,
        icon: String,
        fill: Color,
        foreground: Color,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(foreground.opacity(isEnabled ? 1 : 0.5))
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(fill.opacity(isEnabled ? 1 : 0.5))
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private func conversationBubble(_ message: ImageTranslateConversationMessage) -> some View {
        HStack {
            if message.role == .assistant {
                bubble(message.text, fill: Color.cyan.opacity(0.10), foreground: .primary)
                Spacer(minLength: 42)
            } else {
                Spacer(minLength: 42)
                bubble(message.text, fill: Color(.tertiarySystemFill), foreground: .primary)
            }
        }
    }

    private func bubble(_ text: String, fill: Color, foreground: Color) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(fill)
            )
            .textSelection(.enabled)
    }
}

private struct CropImageEditor: View {
    @Environment(\.dismiss) private var dismiss

    let image: UIImage
    let onConfirm: (CGRect) -> Void

    @State private var selectionRect: CGRect?
    @State private var imageFrame: CGRect = .zero

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
                            .stroke(Color.cyan, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                            .frame(width: selectionRect.width, height: selectionRect.height)
                            .position(x: selectionRect.midX, y: selectionRect.midY)
                    }

                    VStack {
                        Spacer()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("在图片上拖出要翻译的区域")
                                .font(.system(size: 15, weight: .semibold))
                            Text("重新拖动即可改选。适合长截图、菜单局部或只想翻一块界面文案。")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                }
                .onAppear {
                    imageFrame = resolvedImageFrame
                }
                .onChange(of: proxy.size) { _ in
                    imageFrame = resolvedImageFrame
                }
            }
            .navigationTitle("裁剪区域")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("使用选区") {
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
        DragGesture(minimumDistance: 0)
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

private struct CameraImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: CameraImagePicker

        init(parent: CameraImagePicker) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }
    }
}

#Preview {
    NavigationStack {
        ImageTranslateView()
    }
}
