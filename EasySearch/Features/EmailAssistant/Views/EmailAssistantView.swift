import PhotosUI
import SwiftUI
import UIKit

public struct EmailAssistantView: View {
    @StateObject private var viewModel = EmailAssistantViewModel()
    @State private var selectedPhotoItem: PhotosPickerItem?

    private let accentColor = Color.blue

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
                selectedPhotoItem = nil
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
                        .fixedSize(horizontal: false, vertical: true)
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
                heroMetric(title: "模式", value: viewModel.mode.title)
                heroMetric(title: "语气", value: viewModel.tone.title)
                heroMetric(title: "长度", value: viewModel.length.title)
                heroMetric(title: "对话轮次", value: "\(viewModel.completedConversation.filter { $0.role == .assistant }.count)")
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
                description: "API Key 只保存在本机 Keychain。配置一次后，邮件助手和截图翻译都会共用。"
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
                description: "这些信息会一起带入多轮生成，所以第一次尽量把背景交代清楚。"
            )

            VStack(spacing: 12) {
                Picker("模式", selection: $viewModel.mode) {
                    ForEach(EmailAssistantMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

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

            infoStrip(
                icon: "wand.and.stars",
                text: "\(viewModel.mode.shortDescription)。当前会按 \(viewModel.tone.title) / \(viewModel.length.title) / \(viewModel.scenario.title) 生成。",
                foreground: .secondary,
                background: Color(.tertiarySystemFill)
            )

            VStack(spacing: 14) {
                TextEditorCard(
                    title: "你的草稿或想表达的内容",
                    subtitle: "支持中文或英文，哪怕只有要点也可以。",
                    placeholder: "例如：想感谢对方的更新，并说明我们会在下周三前确认时间。",
                    text: $viewModel.originalDraft,
                    minHeight: 130
                )

                TextEditorCard(
                    title: "收到的邮件内容",
                    subtitle: "适合直接粘贴对方邮件，或者让 OCR 自动带入。",
                    placeholder: "把对方发来的邮件粘贴在这里。",
                    text: $viewModel.receivedEmailText,
                    minHeight: 170
                )

                ocrCard

                TextEditorCard(
                    title: "补充要求",
                    subtitle: "例如：更礼貌、简洁一些、强调截止时间、不要太强硬。",
                    placeholder: "补充风格、立场、长度或行动项要求。",
                    text: $viewModel.additionalRequirements,
                    minHeight: 100
                )

                senderProfileCard
            }
        }
        .padding(24)
        .cardStyle()
    }

    private var ocrCard: some View {
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
                } else if viewModel.hasOCRSegments {
                    Button("全选") {
                        viewModel.selectAllOCRSegments()
                    }
                    .buttonStyle(.bordered)

                    Button("清空勾选") {
                        viewModel.clearOCRSelection()
                    }
                    .buttonStyle(.bordered)
                }
            }

            if viewModel.hasOCRSegments {
                VStack(alignment: .leading, spacing: 10) {
                    Text("OCR 段落（已选 \(viewModel.selectedOCRSegmentCount) 条）")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)

                    ForEach(viewModel.ocrSegments) { segment in
                        Button {
                            viewModel.toggleOCRSegment(segment.id)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: segment.isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(segment.isSelected ? accentColor : .secondary)

                                Text(segment.text)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)

                                Spacer(minLength: 0)
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color(.tertiarySystemFill))
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 12) {
                        Button("替换来信内容") {
                            viewModel.applySelectedOCRToReceivedEmail(replace: true)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accentColor)
                        .disabled(!viewModel.canApplySelectedOCR)

                        Button("追加到来信内容") {
                            viewModel.applySelectedOCRToReceivedEmail(replace: false)
                        }
                        .buttonStyle(.bordered)
                        .tint(accentColor)
                        .disabled(!viewModel.canApplySelectedOCR)

                        Button(role: .destructive) {
                            viewModel.clearScreenshotText()
                        } label: {
                            Text("清除 OCR")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var senderProfileCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("发件偏好")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)

            TextField("姓名（可选）", text: $viewModel.senderName)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                TextField("职位或团队", text: $viewModel.senderRoleOrTeam)
                    .textFieldStyle(.roundedBorder)

                TextField("公司", text: $viewModel.senderCompany)
                    .textFieldStyle(.roundedBorder)
            }

            TextField("偏好结尾", text: $viewModel.preferredClosing)
                .textFieldStyle(.roundedBorder)

            TextEditorCard(
                title: "签名",
                subtitle: "如果希望固定签名，可以写在这里。",
                placeholder: "例如：Dapeng\nProduct Engineer",
                text: $viewModel.signature,
                minHeight: 90
            )
        }
    }

    private var conversationCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                sectionHeader(
                    eyebrow: "Conversation",
                    title: "生成结果",
                    description: viewModel.hasConversation
                        ? "主版本和替代版本都保留在这里，可以继续追问或者把某一版放回草稿区。"
                        : "上下文准备好后，点一次生成即可。"
                )

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

            if viewModel.completedConversation.isEmpty {
                emptyState(
                    icon: "envelope.badge",
                    title: "还没有生成结果",
                    description: "先把草稿、来信或截图内容填进去，再生成第一版英文邮件。"
                )
            } else {
                VStack(spacing: 14) {
                    ForEach(viewModel.completedConversation) { message in
                        messageRow(message)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                TextField("继续说：例如“更正式一点”或“把截止时间说得更明确”", text: $viewModel.messageDraft, axis: .vertical)
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

                    if viewModel.isGenerating {
                        Button("停止生成") {
                            viewModel.stopGenerating()
                        }
                        .buttonStyle(.bordered)
                    }

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
                Text(message.role == .assistant ? "AI 结果" : "你的要求")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(message.createdAt.formatted(.dateTime.hour().minute()))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if let output = message.structuredOutput {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("主版本")
                            .font(.system(size: 14, weight: .semibold))
                        Text(output.primaryFormattedText)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    }

                    if !output.explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        infoStrip(
                            icon: "text.bubble",
                            text: output.explanation,
                            foreground: .secondary,
                            background: Color(.tertiarySystemFill)
                        )
                    }

                    HStack(spacing: 12) {
                        Button("放入草稿区") {
                            viewModel.useAssistantMessageAsDraft(message)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accentColor)

                        Button("复制主版本") {
                            UIPasteboard.general.string = output.primaryFormattedText
                            viewModel.presentNotice(tone: .success, message: "已复制主版本。")
                        }
                        .buttonStyle(.bordered)
                    }

                    if !output.alternatives.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("替代版本")
                                .font(.system(size: 14, weight: .semibold))

                            ForEach(output.alternatives) { variant in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(variant.title)
                                        .font(.system(size: 14, weight: .semibold))
                                    Text(variant.formattedText)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .textSelection(.enabled)

                                    HStack(spacing: 12) {
                                        Button("放入草稿区") {
                                            viewModel.useDraftVariant(variant)
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(accentColor)

                                        Button("复制") {
                                            UIPasteboard.general.string = variant.formattedText
                                            viewModel.presentNotice(tone: .success, message: "已复制 \(variant.title)。")
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(Color(.tertiarySystemFill))
                                )
                            }
                        }
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
            guard let data = try await item.loadTransferable(type: Data.self) else {
                viewModel.presentNotice(tone: .caution, message: EmailAssistantError.imageLoadFailed.localizedDescription)
                return
            }

            await viewModel.importScreenshotText(from: data)
        } catch {
            viewModel.presentNotice(tone: .caution, message: error.localizedDescription)
        }
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

    private func heroMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.72))

            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }

    private func statusChip(title: String, color: Color, prominent: Bool = false) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(prominent ? color : color.opacity(0.18))
            )
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

    private func infoStrip(
        icon: String,
        text: String,
        foreground: Color,
        background: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(foreground)

            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(foreground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(background)
        )
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
}

private struct TextEditorCard: View {
    let title: String
    let subtitle: String
    let placeholder: String
    @Binding var text: String
    let minHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

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

#Preview {
    NavigationStack {
        EmailAssistantView()
    }
}
