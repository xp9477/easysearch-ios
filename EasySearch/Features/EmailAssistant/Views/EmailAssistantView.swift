import PhotosUI
import SwiftUI
import UIKit

public struct EmailAssistantView: View {
    @StateObject private var viewModel = EmailAssistantViewModel()
    @State private var selectedPhotoItem: PhotosPickerItem?

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heroCard

                if !viewModel.configurationState.hasAPIKey {
                    configurationCard
                }

                contextCard
                conversationCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("邮件助手")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .task {
            await viewModel.prepare()
        }
        .onReceive(NotificationCenter.default.publisher(for: .imageTranslateConfigurationDidChange)) { _ in
            Task {
                await viewModel.refreshConfiguration()
            }
        }
        .onChange(of: selectedPhotoItem) { newValue in
            guard let newValue else { return }
            Task {
                await loadPhotoItem(newValue)
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("DeepSeek Mail")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.74))

                    Text("英文邮件生成与讨论")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)

                    Text("贴草稿、贴来信或上传截图后，先出一版可直接发送的英文邮件，再继续对话细修。")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.82))
                }

                Spacer(minLength: 12)

                statusChip(
                    title: viewModel.configurationState.hasAPIKey ? "DeepSeek 已连接" : "等待配置 API Key",
                    color: viewModel.configurationState.hasAPIKey ? accentColor : .orange,
                    prominent: true
                )
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                heroMetric(title: "当前模式", value: viewModel.mode.title)
                heroMetric(title: "上下文", value: viewModel.currentContext.hasUsableContent ? "已填写" : "待输入")
                heroMetric(title: "对话轮次", value: "\(assistantReplyCount)")
                heroMetric(title: "截图 OCR", value: viewModel.screenshotOCRText.isEmpty ? "未导入" : "已识别")
            }

            if let notice = viewModel.notice {
                noticeBanner(notice, onDarkBackground: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.10, green: 0.18, blue: 0.33),
                            Color(red: 0.04, green: 0.09, blue: 0.17)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var configurationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                eyebrow: "Configuration",
                title: "先配好 DeepSeek",
                description: "API Key 只保存在本机 Keychain。配置一次后，模块和设置页都会共用。"
            )

            SecureField("输入 DeepSeek API Key", text: $viewModel.apiKeyDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.systemBackground))
                )

            Button {
                Task {
                    await viewModel.saveAPIKey()
                }
            } label: {
                HStack {
                    Label("保存 API Key", systemImage: "key.fill")
                    Spacer()
                    if viewModel.isSavingAPIKey {
                        ProgressView()
                    }
                }
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(accentColor)
            .disabled(viewModel.apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSavingAPIKey)
        }
        .padding(24)
        .cardStyle()
    }

    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(
                eyebrow: "Context",
                title: "上下文输入",
                description: "邮件助手会始终带着这些固定信息进入多轮对话，所以第一次尽量把背景交代清楚。"
            )

            Picker("模式", selection: $viewModel.mode) {
                ForEach(EmailAssistantMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            infoStrip(
                icon: "wand.and.stars",
                text: viewModel.mode.shortDescription,
                foreground: .secondary,
                background: Color(.tertiarySystemFill)
            )

            VStack(spacing: 14) {
                TextEditorCard(
                    title: "你的草稿或想表达的内容",
                    subtitle: "支持中文或英文，哪怕只有要点也可以。",
                    placeholder: "例如：想感谢对方的更新，并说明我们会在下周三前确认时间。",
                    text: $viewModel.originalDraft,
                    minHeight: 140
                )

                TextEditorCard(
                    title: "收到的邮件内容",
                    subtitle: "适合直接粘贴对方邮件，或者让 OCR 自动带入。",
                    placeholder: "把对方发来的邮件粘贴在这里。",
                    text: $viewModel.receivedEmailText,
                    minHeight: 180
                )

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Label("导入邮件截图", systemImage: "photo.on.rectangle")
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
                        } else if !viewModel.screenshotOCRText.isEmpty {
                            Button {
                                viewModel.clearScreenshotText()
                            } label: {
                                Label("清除 OCR", systemImage: "trash")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    if !viewModel.screenshotOCRText.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("截图识别结果")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)

                            Text(viewModel.screenshotOCRText)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(Color(.tertiarySystemFill))
                                )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                TextEditorCard(
                    title: "补充要求",
                    subtitle: "例如：更礼貌、简洁一些、强调截止时间、不要太强硬。",
                    placeholder: "补充风格、立场、长度或行动项要求。",
                    text: $viewModel.additionalRequirements,
                    minHeight: 110
                )
            }
        }
        .padding(24)
        .cardStyle()
    }

    private var conversationCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                sectionHeader(
                    eyebrow: "Conversation",
                    title: "多轮讨论",
                    description: "先生成第一版，再继续说“更简洁一点”“别太生硬”“加入下周二截止”等修改要求。"
                )

                Spacer(minLength: 12)

                if viewModel.hasConversation {
                    Button(role: .destructive) {
                        viewModel.clearConversation()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .bold))
                            .padding(10)
                    }
                    .buttonStyle(.bordered)
                }
            }

            quickPromptBar

            if viewModel.conversation.isEmpty {
                emptyConversationState
            } else {
                conversationList
            }

            composerCard
        }
        .padding(24)
        .cardStyle()
    }

    private var emptyConversationState: some View {
        VStack(spacing: 14) {
            Image(systemName: "envelope.open.badge.clock")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(accentColor)

            Text("还没有开始生成")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.primary)

            Text("填好上下文后，直接点下面的发送按钮，或者先点一条快捷指令。")
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

    private var conversationList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.conversation) { message in
                        MessageBubble(
                            message: message,
                            accentColor: accentColor,
                            copyAction: {
                                UIPasteboard.general.string = message.content
                            },
                            useAsDraftAction: {
                                viewModel.useAssistantDraft(message)
                            }
                        )
                        .id(message.id)
                    }
                }
            }
            .frame(minHeight: 160, maxHeight: 420)
            .onChange(of: viewModel.conversation.count) { _ in
                guard let lastID = viewModel.conversation.last?.id else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
    }

    private var composerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("继续提要求")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $viewModel.messageDraft)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 108)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(.systemBackground))
                    )

                if viewModel.messageDraft.isEmpty {
                    Text("例如：再简洁一点，保留礼貌；或者：加一句请对方在周五前确认。")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                }
            }

            HStack(spacing: 10) {
                Button(role: .destructive) {
                    viewModel.resetAll()
                } label: {
                    Label("清空全部", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)

                Button {
                    Task {
                        await viewModel.sendCurrentMessage()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isGenerating {
                            ProgressView()
                        } else {
                            Image(systemName: "paperplane.fill")
                        }

                        Text(viewModel.hasConversation ? "发送修改要求" : "生成首版邮件")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(accentColor)
                .disabled(!viewModel.canSend)
            }
        }
    }

    private var quickPromptBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(quickPrompts, id: \.self) { prompt in
                    Button {
                        Task {
                            await viewModel.sendQuickPrompt(prompt)
                        }
                    } label: {
                        Text(prompt)
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color(.tertiarySystemFill))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isGenerating)
                }
            }
        }
    }

    private var quickPrompts: [String] {
        switch viewModel.mode {
        case .polish:
            return [
                "请直接润色成简洁英文邮件。",
                "更礼貌一些，但不要太冗长。",
                "压缩到 5 句以内。",
                "保留重点，语气更坚定。"
            ]
        case .reply:
            return [
                "请直接生成英文回复。",
                "语气更友好一些。",
                "强调下一步行动和时间点。",
                "回复更简短直接。"
            ]
        case .discuss:
            return [
                "先给我一版最稳妥的回复。",
                "给我两个不同语气版本。",
                "更正式一些。",
                "更自然口语一点。"
            ]
        }
    }

    private var assistantReplyCount: Int {
        viewModel.conversation.filter { $0.role == .assistant }.count
    }

    private var accentColor: Color {
        Color(red: 0.15, green: 0.54, blue: 0.96)
    }

    @MainActor
    private func loadPhotoItem(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw EmailAssistantError.imageLoadFailed
            }
            await viewModel.importScreenshotText(from: data)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            viewModel.presentNotice(tone: .caution, message: message)
        }
        selectedPhotoItem = nil
    }

    private func heroMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.66))

            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
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
        }
    }

    private func statusChip(title: String, color: Color, prominent: Bool = false) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(prominent ? Color.white : color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(prominent ? color.opacity(0.96) : color.opacity(0.12))
            )
    }

    private func noticeBanner(_ notice: EmailAssistantNotice, onDarkBackground: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: notice.iconName)
                .font(.system(size: 14, weight: .bold))

            Text(notice.message)
                .font(.system(size: 13, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .foregroundStyle(onDarkBackground ? Color.white : notice.color)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(onDarkBackground ? Color.white.opacity(0.08) : notice.color.opacity(0.12))
        )
    }

    private func infoStrip(icon: String, text: String, foreground: Color, background: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .padding(.top, 1)

            Text(text)
                .font(.system(size: 13, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(background)
        )
    }
}

private struct TextEditorCard: View {
    let title: String
    let subtitle: String
    let placeholder: String
    @Binding var text: String
    let minHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: minHeight)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(.systemBackground))
                    )

                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MessageBubble: View {
    let message: EmailAssistantThreadMessage
    let accentColor: Color
    let copyAction: () -> Void
    let useAsDraftAction: () -> Void

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
            Text(message.role == .user ? "你的要求" : "AI 回复")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)

            VStack(alignment: .leading, spacing: 10) {
                Text(message.content)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(message.role == .user ? .white : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if message.role == .assistant {
                    HStack(spacing: 10) {
                        Button(action: copyAction) {
                            Label("复制", systemImage: "doc.on.doc")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(.bordered)

                        Button(action: useAsDraftAction) {
                            Label("放入草稿", systemImage: "arrow.down.doc")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                        .tint(accentColor)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(message.role == .user ? accentColor : Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(message.role == .user ? Color.clear : Color.primary.opacity(0.08), lineWidth: 1)
            )
            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        }
    }
}

private extension View {
    func cardStyle() -> some View {
        background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private extension EmailAssistantNotice {
    var color: Color {
        switch tone {
        case .neutral:
            return .secondary
        case .success:
            return Color(red: 0.14, green: 0.67, blue: 0.48)
        case .caution:
            return .orange
        }
    }

    var iconName: String {
        switch tone {
        case .neutral:
            return "info.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .caution:
            return "exclamationmark.triangle.fill"
        }
    }
}

#Preview {
    NavigationStack {
        EmailAssistantView()
    }
}
