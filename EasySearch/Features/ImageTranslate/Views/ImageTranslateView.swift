import PhotosUI
import SwiftUI
import UIKit

public struct ImageTranslateView: View {
    @EnvironmentObject private var navigationState: AppNavigationState
    @StateObject private var viewModel = ImageTranslateViewModel()
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var cameraImage: UIImage?
    @State private var cropSource: ImageTranslateCropSource?
    @State private var isPhotoPickerPresented = false
    @State private var isCameraPresented = false
    @State private var activeContentTab: ImageTranslateContentTab = .workspace

    public init() {}

    private var hasActiveSession: Bool {
        viewModel.selectedImage != nil
            || !viewModel.extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || viewModel.hasTranslation
    }

    private var hasRecognizedText: Bool {
        !viewModel.extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var primaryActionTitle: String {
        if hasRecognizedText {
            return viewModel.hasTranslation ? "重新翻译" : "AI 翻译"
        }

        return viewModel.hasConfiguredAPIKey ? "识别并翻译" : "识别文字"
    }

    private var primaryActionIcon: String {
        hasRecognizedText ? "sparkles" : "text.viewfinder"
    }

    private var canRunPrimaryAction: Bool {
        hasRecognizedText ? viewModel.canTranslate : viewModel.canRecognizeSelectedImage
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ESUI.sectionSpacing) {
                ESModuleHero(
                    title: "翻译",
                    subtitle: "文本 · 图片 · 即用",
                    featureID: "image-translate",
                    systemImage: "globe"
                )
                if !viewModel.hasConfiguredAPIKey {
                    setupGuidance
                }

                captureDeck

                if availableContentTabs.count > 1 {
                    contentTabStrip
                }

                currentContentCard

                if viewModel.hasHistory {
                    historySection
                }
            }
            .padding(.horizontal, ESUI.screenHorizontalPadding)
            .padding(.top, ESUI.Space.md)
            .padding(.bottom, ESUI.Space.xxxl)
        }
        .esScreenBackground()
        .navigationTitle("翻译")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .overlay(alignment: .top) {
            if let notice = viewModel.notice {
                noticeToast(notice)
                    .padding(.horizontal, ESUI.screenHorizontalPadding)
                    .padding(.top, ESUI.Space.sm)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: viewModel.notice)
        .task {
            await viewModel.prepare()
        }
        .onChange(of: viewModel.latestTranslation) { newValue in
            let hasTranslation = !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                activeContentTab = hasTranslation ? .translation : .workspace
            }
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
        .sheet(item: $cropSource) { source in
            CropImageEditor(image: source.image) { selection in
                Task {
                    await applyCrop(selection, to: source)
                }
            }
        }
    }

    // MARK: - Setup

    private var setupGuidance: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            ESNeedsSetupState(
                title: "尚未配置 AI",
                message: "可先识别图片文字；翻译与进阶能力需要配置 API Key。",
                actionTitle: "去配置"
            ) {
                navigationState.openSettings(.imageTranslate)
            }
        }
        .esCard()
    }

    // MARK: - Capture

    private var captureDeck: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.md) {
            HStack(alignment: .top, spacing: ESUI.Space.sm) {
                ESFeatureIcon(systemName: "text.viewfinder", color: .accentColor, size: 44)

                VStack(alignment: .leading, spacing: ESUI.Space.xxs) {
                    Text("翻译工作区")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text("支持文本、截图和拍照翻译")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: ESUI.Space.xs)

                Button {
                    viewModel.startFreshSession()
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(ESUI.fill))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("新建会话")
            }

            HStack(spacing: ESUI.Space.xs) {
                ESStatusBadge(text: viewModel.targetLanguage.title, tone: .accent)

                if viewModel.isRecognizingText {
                    ESStatusBadge(text: "识别中", tone: .warning)
                } else if viewModel.isTranslating {
                    ESStatusBadge(text: "翻译中", tone: .accent)
                }

                if hasActiveSession {
                    ESStatusBadge(
                        text: viewModel.hasTranslation
                            ? "已生成结果"
                            : (viewModel.selectedImage != nil
                               ? (hasRecognizedText ? "可继续处理" : "待识别")
                               : "可直接开始"),
                        tone: viewModel.hasTranslation ? .success : .neutral
                    )
                }
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: ESUI.Space.sm), count: 3),
                spacing: ESUI.Space.sm
            ) {
                deckActionButton(title: "粘贴截图", icon: "doc.on.clipboard") {
                    Task {
                        await viewModel.importClipboardImage()
                    }
                }

                deckActionButton(title: "选图片", icon: "photo.on.rectangle.angled") {
                    isPhotoPickerPresented = true
                }

                deckActionButton(
                    title: "拍照",
                    icon: "camera.fill",
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

            HStack(spacing: ESUI.Space.sm) {
                Menu {
                    ForEach(ImageTranslateTargetLanguage.allCases) { language in
                        Button(language.title) {
                            viewModel.targetLanguage = language
                        }
                    }
                } label: {
                    controlPill(
                        systemImage: "globe.asia.australia.fill",
                        title: "输出",
                        value: viewModel.targetLanguage.title
                    )
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }

            HStack(spacing: ESUI.Space.sm) {
                quickDirectionButton(title: "中译英", targetLanguage: .english)
                quickDirectionButton(title: "英译中", targetLanguage: .simplifiedChinese)
            }
        }
        .esCard()
    }

    // MARK: - Tabs

    private var availableContentTabs: [ImageTranslateContentTab] {
        var tabs: [ImageTranslateContentTab] = [.workspace]

        if viewModel.hasTranslation {
            tabs.append(.translation)

            if !viewModel.alignedSections.isEmpty {
                tabs.append(.comparison)
            }
        }

        return tabs
    }

    private var resolvedContentTab: ImageTranslateContentTab {
        availableContentTabs.contains(activeContentTab) ? activeContentTab : .workspace
    }

    @ViewBuilder
    private var currentContentCard: some View {
        switch resolvedContentTab {
        case .workspace:
            workspaceCard
        case .translation:
            translationCard
        case .comparison:
            comparisonCard
        }
    }

    private var contentTabStrip: some View {
        HStack(spacing: ESUI.Space.xs) {
            ForEach(availableContentTabs) { tab in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                        activeContentTab = tab
                    }
                } label: {
                    HStack(spacing: ESUI.Space.xs) {
                        Image(systemName: tab.symbolName)
                            .font(.caption.weight(.semibold))
                        Text(tab.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, ESUI.Space.sm)
                    .foregroundStyle(resolvedContentTab == tab ? Color.white : Color.primary)
                    .background {
                        RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                            .fill(resolvedContentTab == tab ? Color.accentColor : ESUI.fill)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(ESUI.Space.xs)
        .esSurface(cornerRadius: ESUI.cardCornerRadius)
    }

    // MARK: - Workspace

    private var workspaceCard: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.md) {
            HStack(alignment: .center, spacing: ESUI.Space.sm) {
                Text("工作区")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer(minLength: ESUI.Space.xs)

                if !viewModel.extractedText.isEmpty {
                    ESStatusBadge(text: "\(viewModel.extractedText.count) 字", tone: .neutral)
                }

                if viewModel.needsRetranslation {
                    ESStatusBadge(text: "待重翻", tone: .warning)
                }
            }

            if let image = viewModel.selectedImage {
                imageWorkbench(image)
            } else {
                emptyWorkbench
            }

            textWorkbench

            Button {
                Task {
                    if hasRecognizedText {
                        await viewModel.translateCurrentText()
                    } else {
                        await viewModel.reRecognizeSelectedImage()
                    }
                }
            } label: {
                HStack(spacing: ESUI.Space.sm) {
                    Image(systemName: primaryActionIcon)
                    Text(primaryActionTitle)
                    Spacer()
                    if viewModel.isRecognizingText || viewModel.isTranslating {
                        ProgressView().tint(.white)
                    }
                }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, ESUI.Space.xs)
            }
            .buttonStyle(.glassProminent)
            .disabled(!canRunPrimaryAction)
        }
        .esCard()
    }

    private func imageWorkbench(_ image: UIImage) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: ESUI.Space.sm) {
                VStack(alignment: .leading, spacing: ESUI.Space.xs) {
                    ESStatusBadge(text: viewModel.imageStatusText, tone: .accent)

                    if viewModel.isRecognizingText {
                        ESStatusBadge(text: "识别中", tone: .warning)
                    } else if viewModel.isTranslating {
                        ESStatusBadge(text: "翻译中", tone: .success)
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: ESUI.Space.xs) {
                    imageToolButton(title: "裁剪", systemImage: "crop") {
                        cropSource = ImageTranslateCropSource(
                            image: image,
                            mode: .recropCurrentImage
                        )
                    }
                    .disabled(viewModel.isRecognizingText || viewModel.isTranslating)

                    imageToolButton(
                        title: hasRecognizedText ? "重识别" : "识别全文",
                        systemImage: "viewfinder"
                    ) {
                        Task {
                            await viewModel.reRecognizeSelectedImage()
                        }
                    }
                    .disabled(viewModel.isRecognizingText || viewModel.isTranslating)
                }
            }
            .padding(ESUI.Space.sm)

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 280)
                .padding(.horizontal, ESUI.Space.sm)
                .padding(.bottom, ESUI.Space.sm)
        }
        .background(
            RoundedRectangle(cornerRadius: ESUI.cardCornerRadius, style: .continuous)
                .fill(ESUI.fill)
        )
    }

    private var emptyWorkbench: some View {
        HStack(spacing: ESUI.Space.sm) {
            ESFeatureIcon(systemName: "photo.badge.plus", color: .accentColor, size: 48)

            VStack(alignment: .leading, spacing: ESUI.Space.xxs) {
                Text("直接输入文本，或导入图片")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("支持文本翻译和图片翻译")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(ESUI.Space.md)
        .background(
            RoundedRectangle(cornerRadius: ESUI.cardCornerRadius, style: .continuous)
                .fill(ESUI.fill)
        )
    }

    private var textWorkbench: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            HStack(alignment: .center, spacing: ESUI.Space.sm) {
                Text("待翻译文本")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()

                if !viewModel.extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        viewModel.copyText(viewModel.extractedText, successMessage: "已复制识别文本。")
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(ESUI.fill))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("复制识别文本")
                }
            }

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                    .fill(ESUI.fill)

                if viewModel.extractedText.isEmpty {
                    Text("可直接输入或粘贴文本")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, ESUI.Space.md)
                        .padding(.vertical, ESUI.Space.md)
                }

                TextEditor(text: $viewModel.extractedText)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, ESUI.Space.sm)
                    .padding(.vertical, ESUI.Space.sm)
                    .frame(minHeight: 168)
                    .background(Color.clear)
            }
        }
    }

    // MARK: - Translation

    private var translationCard: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.md) {
            HStack(alignment: .center, spacing: ESUI.Space.sm) {
                Text("译文")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    viewModel.copyText(viewModel.latestTranslation, successMessage: "已复制翻译结果。")
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.glass)
            }

            VStack(alignment: .leading, spacing: ESUI.Space.sm) {
                Text(viewModel.latestTranslation)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)

                HStack(spacing: ESUI.Space.xs) {
                    if let detectedSourceLanguage = viewModel.detectedSourceLanguage,
                       !detectedSourceLanguage.isEmpty {
                        ESStatusBadge(text: "源 \(detectedSourceLanguage)", tone: .neutral)
                    }

                    ESStatusBadge(text: "目标 \(viewModel.targetLanguage.title)", tone: .accent)
                }
            }
            .padding(ESUI.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                    .fill(ESUI.fill)
            )

            if !viewModel.translationNotes.isEmpty {
                translationDetailSection(title: "补充说明", systemImage: "text.quote") {
                    Text(viewModel.translationNotes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !viewModel.meanings.isEmpty {
                translationDetailSection(title: "详细释义", systemImage: "text.book.closed") {
                    VStack(alignment: .leading, spacing: ESUI.Space.sm) {
                        ForEach(Array(viewModel.meanings.enumerated()), id: \.offset) { _, item in
                            translationMeaningRow(item)
                        }
                    }
                }
            }

            if !viewModel.examples.isEmpty {
                translationDetailSection(title: "例句", systemImage: "quote.bubble") {
                    VStack(alignment: .leading, spacing: ESUI.Space.sm) {
                        ForEach(Array(viewModel.examples.enumerated()), id: \.offset) { _, item in
                            translationExampleRow(item)
                        }
                    }
                }
            }

            if !viewModel.collocations.isEmpty {
                translationDetailSection(title: "常用搭配", systemImage: "text.append") {
                    VStack(alignment: .leading, spacing: ESUI.Space.sm) {
                        ForEach(Array(viewModel.collocations.enumerated()), id: \.offset) { _, item in
                            translationCollocationRow(item)
                        }
                    }
                }
            }

            if !viewModel.alignedSections.isEmpty {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                        activeContentTab = .comparison
                    }
                } label: {
                    HStack(spacing: ESUI.Space.xs) {
                        Label("查看对照", systemImage: "square.split.2x1")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Spacer()

                        Text("\(viewModel.alignedSections.count) 段")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(ESUI.Space.md)
                    .background(
                        RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                            .fill(ESUI.fill)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .esCard()
    }

    private func translationDetailSection<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            content()
        }
        .padding(ESUI.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                .fill(ESUI.fill)
        )
    }

    private func translationMeaningRow(_ item: ImageTranslateMeaning) -> some View {
        HStack(alignment: .top, spacing: ESUI.Space.sm) {
            if !item.partOfSpeech.isEmpty {
                ESStatusBadge(text: item.partOfSpeech, tone: .accent)
            }

            Text(item.meaning)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private func translationExampleRow(_ item: ImageTranslateExample) -> some View {
        VStack(alignment: .leading, spacing: ESUI.Space.xxs) {
            Text(item.source)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .textSelection(.enabled)

            Text(item.translation)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func translationCollocationRow(_ item: ImageTranslateCollocation) -> some View {
        VStack(alignment: .leading, spacing: ESUI.Space.xxs) {
            Text(item.phrase)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .textSelection(.enabled)

            Text(item.translation)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if !item.note.isEmpty {
                Text(item.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Comparison

    private var comparisonCard: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.md) {
            ESSectionHeader(
                title: "对照",
                trailing: "\(viewModel.alignedSections.count) 段"
            )

            ForEach(viewModel.alignedSections) { section in
                comparisonRow(section)
            }
        }
        .esCard()
    }

    private func comparisonRow(_ section: AlignedTextSection) -> some View {
        HStack(alignment: .top, spacing: ESUI.Space.sm) {
            VStack(alignment: .leading, spacing: ESUI.Space.xs) {
                ESStatusBadge(text: "原文", tone: .neutral)

                Text(section.sourceText.isEmpty ? " " : section.sourceText)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            VStack(alignment: .leading, spacing: ESUI.Space.xs) {
                ESStatusBadge(text: "译文", tone: .accent)

                Text(section.translatedText.isEmpty ? " " : section.translatedText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(ESUI.Space.md)
        .background(
            RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                .fill(ESUI.fill)
        )
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            ESSectionHeader(title: "历史", trailing: "\(viewModel.history.count)")

            ForEach(viewModel.history.prefix(8)) { record in
                Button {
                    viewModel.loadHistorySession(record)
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                        activeContentTab = viewModel.hasTranslation ? .translation : .workspace
                    }
                } label: {
                    VStack(alignment: .leading, spacing: ESUI.Space.xxs) {
                        Text(record.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if !record.translationSnippet.isEmpty {
                            Text(record.translationSnippet)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Text(record.updatedAt.formatted(.relative(presentation: .named)))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(ESUI.Space.md)
                    .background(
                        RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                            .fill(ESUI.fill)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .esCard()
    }

    // MARK: - Actions

    private func loadPhoto(from item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                viewModel.presentNotice(tone: .caution, message: "图片读取失败，请重新选择。")
                return
            }

            let normalizedImage = ImageOCRService.normalizedDisplayImage(image)

            await MainActor.run {
                cropSource = ImageTranslateCropSource(
                    image: normalizedImage,
                    mode: .importAfterCrop(.photoLibrary)
                )
            }
        } catch {
            viewModel.presentNotice(tone: .caution, message: error.localizedDescription)
        }
    }

    @MainActor
    private func applyCrop(_ selection: ImageCropSelection, to source: ImageTranslateCropSource) async {
        switch source.mode {
        case let .importAfterCrop(inputSource):
            guard let croppedImage = ImageOCRService.cropImage(source.image, selection: selection) else {
                viewModel.presentNotice(
                    tone: .caution,
                    message: ImageTranslateError.invalidCropArea.localizedDescription
                )
                return
            }

            await viewModel.importImage(croppedImage, from: inputSource)
            await viewModel.reRecognizeSelectedImage()

        case .recropCurrentImage:
            await viewModel.cropCurrentImage(to: selection)
        }
    }

    // MARK: - Chrome Helpers

    private func noticeToast(_ notice: ImageTranslateNotice) -> some View {
        let tone: ESStatusBadge.Tone = {
            switch notice.tone {
            case .neutral: return .neutral
            case .success: return .success
            case .caution: return .warning
            }
        }()

        return ESStatusBanner(
            title: notice.message,
            systemImage: notice.tone == .caution ? "exclamationmark.triangle.fill" : "info.circle.fill",
            tone: tone
        )
        .background(
            RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    private func deckActionButton(
        title: String,
        icon: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: ESUI.Space.sm) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .padding(ESUI.Space.sm)
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            .background(
                RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                    .fill(ESUI.fill)
            )
            .opacity(isEnabled ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private func controlPill(systemImage: String, title: String, value: String) -> some View {
        HStack(spacing: ESUI.Space.xs) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, ESUI.Space.sm)
        .padding(.vertical, ESUI.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                .fill(ESUI.fill)
        )
    }

    private func quickDirectionButton(
        title: String,
        targetLanguage: ImageTranslateTargetLanguage
    ) -> some View {
        let isActive = viewModel.targetLanguage == targetLanguage

        return Button {
            viewModel.targetLanguage = targetLanguage

            guard hasRecognizedText,
                  viewModel.hasConfiguredAPIKey,
                  !viewModel.isRecognizingText,
                  !viewModel.isTranslating else {
                return
            }

            Task {
                await viewModel.translateCurrentText()
            }
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isActive ? Color.white : Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, ESUI.Space.sm)
                .background(
                    RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                        .fill(isActive ? Color.accentColor : ESUI.fill)
                )
        }
        .buttonStyle(.plain)
    }

    private func imageToolButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, ESUI.Space.sm)
                .padding(.vertical, ESUI.Space.xs)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
        }
        .buttonStyle(.plain)
    }
}

private enum ImageTranslateContentTab: String, Identifiable {
    case workspace
    case translation
    case comparison

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workspace: return "工作区"
        case .translation: return "译文"
        case .comparison: return "对照"
        }
    }

    var symbolName: String {
        switch self {
        case .workspace: return "square.and.pencil"
        case .translation: return "text.quote"
        case .comparison: return "square.split.2x1"
        }
    }
}

private struct ImageTranslateCropSource: Identifiable {
    enum Mode {
        case importAfterCrop(ImageTranslateInputSource)
        case recropCurrentImage
    }

    let id = UUID()
    let image: UIImage
    let mode: Mode
}

private struct CropImageEditor: View {
    @Environment(\.dismiss) private var dismiss

    let image: UIImage
    let onConfirm: (ImageCropSelection) -> Void

    @State private var selectionRect: CGRect?
    @State private var canvasSize: CGSize = .zero

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let resolvedCanvasSize = aspectFitSize(
                    for: image.size,
                    in: CGSize(
                        width: max(proxy.size.width - 40, 0),
                        height: max(proxy.size.height - 40, 0)
                    )
                )

                ZStack {
                    ESUI.appBackground.ignoresSafeArea()

                    VStack {
                        Spacer(minLength: ESUI.Space.lg)

                        ZStack(alignment: .topLeading) {
                            Image(uiImage: image)
                                .resizable()
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

                        Text("拖动选择区域")
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
            .environmentObject(AppNavigationState())
    }
}
