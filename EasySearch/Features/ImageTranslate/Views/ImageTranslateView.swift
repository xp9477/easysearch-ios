import PhotosUI
import SwiftUI
import UIKit

public struct ImageTranslateView: View {
    @EnvironmentObject private var navigationState: AppNavigationState
    @StateObject private var viewModel = ImageTranslateViewModel()
    @FocusState private var isInputFocused: Bool
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var cameraImage: UIImage?
    @State private var cropSource: ImageTranslateCropSource?
    @State private var isPhotoPickerPresented = false
    @State private var isCameraPresented = false
    @State private var detailSheet: ImageTranslateDetailSheet?
    @State private var isHistoryPresented = false

    public init() {}

    private var trimmedInput: String {
        viewModel.extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasInputText: Bool {
        !trimmedInput.isEmpty
    }

    private var isBusy: Bool {
        viewModel.isRecognizingText || viewModel.isTranslating
    }

    private var canSubmit: Bool {
        hasInputText ? viewModel.canTranslate : viewModel.canRecognizeSelectedImage
    }

    private var sourceLanguageTitle: String {
        if let detected = viewModel.detectedSourceLanguage, !detected.isEmpty {
            return detected
        }
        return "自动检测"
    }

    private var detailCount: Int {
        viewModel.meanings.count + viewModel.examples.count + viewModel.collocations.count
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: ESUI.Space.md) {
                    languageBar

                    if !viewModel.hasConfiguredAPIKey {
                        setupBanner
                    }

                    inputCard

                    if viewModel.hasTranslation {
                        translationCard
                    }
                }
                .padding(.horizontal, ESUI.screenHorizontalPadding)
                .padding(.top, ESUI.Space.sm)
                .padding(.bottom, 104)
            }
            .scrollDismissesKeyboard(.interactively)

            toolbarDock
        }
        .esScreenBackground()
        .navigationTitle("翻译")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        viewModel.startFreshSession()
                        isInputFocused = true
                    } label: {
                        Label("新建翻译", systemImage: "square.and.pencil")
                    }

                    Picker("输出语言", selection: targetLanguageBinding) {
                        ForEach(ImageTranslateTargetLanguage.allCases) { language in
                            Text(language.title).tag(language)
                        }
                    }

                    Divider()

                    Button {
                        navigationState.openSettings(.imageTranslate)
                    } label: {
                        Label("AI 配置", systemImage: "slider.horizontal.3")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .overlay(alignment: .top) {
            if let notice = viewModel.notice, notice.tone != .neutral {
                noticeToast(notice)
                    .padding(.horizontal, ESUI.screenHorizontalPadding)
                    .padding(.top, ESUI.Space.xs)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: viewModel.notice)
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: viewModel.latestTranslation)
        .task {
            await viewModel.prepare()
            if !viewModel.hasTranslation && !hasInputText && viewModel.selectedImage == nil {
                isInputFocused = true
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
        .sheet(item: $detailSheet) { sheet in
            ImageTranslateDetailSheetView(sheet: sheet, viewModel: viewModel)
        }
        .sheet(isPresented: $isHistoryPresented) {
            ImageTranslateHistorySheet(viewModel: viewModel)
        }
    }

    private var targetLanguageBinding: Binding<ImageTranslateTargetLanguage> {
        Binding(
            get: { viewModel.targetLanguage },
            set: { newValue in
                Task { await switchTargetLanguage(to: newValue) }
            }
        )
    }

    // MARK: - Language bar

    private var languageBar: some View {
        HStack(spacing: 0) {
            languageSegment(title: sourceLanguageTitle, isActive: false)

            Button {
                Task { await swapLanguages() }
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("切换语言方向")

            Menu {
                ForEach(ImageTranslateTargetLanguage.allCases) { language in
                    Button(language.title) {
                        Task { await switchTargetLanguage(to: language) }
                    }
                }
            } label: {
                languageSegment(title: viewModel.targetLanguage.title, isActive: true)
            }
            .buttonStyle(.plain)
        }
        .padding(4)
        .background(
            Capsule(style: .continuous)
                .fill(Color(.tertiarySystemFill))
        )
    }

    private func languageSegment(title: String, isActive: Bool) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isActive ? Color.primary : Color.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background {
                if isActive {
                    Capsule(style: .continuous)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                }
            }
    }

    private var setupBanner: some View {
        Button {
            navigationState.openSettings(.imageTranslate)
        } label: {
            HStack(spacing: ESUI.Space.sm) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(ESUI.warning)

                Text("未配置 AI，仅能识别图片文字")
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                Text("去配置")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, ESUI.Space.md)
            .padding(.vertical, ESUI.Space.sm)
            .background(
                RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Input

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            if let image = viewModel.selectedImage {
                imageStrip(image)
            }

            ZStack(alignment: .topLeading) {
                if viewModel.extractedText.isEmpty {
                    Text("输入文本")
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $viewModel.extractedText)
                    .font(.system(size: 26, weight: .regular))
                    .scrollContentBackground(.hidden)
                    .focused($isInputFocused)
                    .frame(minHeight: viewModel.selectedImage == nil ? 150 : 92)
            }

            HStack(alignment: .bottom, spacing: ESUI.Space.sm) {
                Text(inputHintText)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                submitButton
            }
        }
        .padding(ESUI.Space.md)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var inputHintText: String {
        if viewModel.isRecognizingText { return "正在识别图片文字…" }
        if viewModel.isTranslating { return "正在翻译…" }
        if viewModel.needsRetranslation { return "文本已修改，可重新翻译" }
        if hasInputText { return "\(trimmedInput.count) 字" }
        return "粘贴文本或从下方导入图片"
    }

    private var submitButton: some View {
        Button {
            isInputFocused = false
            Task {
                if hasInputText {
                    await viewModel.translateCurrentText()
                } else {
                    await viewModel.reRecognizeSelectedImage()
                }
            }
        } label: {
            Group {
                if isBusy {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: hasInputText ? "arrow.right" : "text.viewfinder")
                        .font(.system(size: 19, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(width: 46, height: 46)
            .background(
                Circle().fill(canSubmit ? Color.accentColor : Color(.tertiaryLabel))
            )
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
        .accessibilityLabel(hasInputText ? "翻译" : "识别文字")
    }

    private func imageStrip(_ image: UIImage) -> some View {
        HStack(spacing: ESUI.Space.sm) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.imageStatusText)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(hasInputText ? "已识别 \(trimmedInput.count) 字" : "尚未识别文字")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                cropSource = ImageTranslateCropSource(image: image, mode: .recropCurrentImage)
            } label: {
                Image(systemName: "crop")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .disabled(isBusy)

            Button {
                Task { await viewModel.reRecognizeSelectedImage() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .disabled(isBusy)
        }
        .padding(ESUI.Space.xs)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.tertiarySystemFill))
        )
    }

    // MARK: - Translation

    private var translationCard: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            HStack(spacing: ESUI.Space.sm) {
                Text(viewModel.targetLanguage.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Button {
                    viewModel.copyText(viewModel.latestTranslation, successMessage: "已复制译文。")
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 17, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel("复制译文")
            }

            if !trimmedInput.isEmpty {
                Text(trimmedInput)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(viewModel.latestTranslation)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Color.accentColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !viewModel.translationNotes.isEmpty {
                Text(viewModel.translationNotes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if detailCount > 0 || !viewModel.alignedSections.isEmpty {
                Divider()
                    .padding(.vertical, ESUI.Space.xxs)

                VStack(spacing: ESUI.Space.xs) {
                    if detailCount > 0 {
                        detailRow(
                            title: "详细释义",
                            systemImage: "text.book.closed.fill",
                            color: .blue,
                            trailing: "\(detailCount) 条"
                        ) {
                            detailSheet = .details
                        }
                    }

                    if !viewModel.alignedSections.isEmpty {
                        detailRow(
                            title: "原文对照",
                            systemImage: "arrow.left.arrow.right",
                            color: .indigo,
                            trailing: "\(viewModel.alignedSections.count) 段"
                        ) {
                            detailSheet = .comparison
                        }
                    }
                }
            }
        }
        .padding(ESUI.Space.md)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func detailRow(
        title: String,
        systemImage: String,
        color: Color,
        trailing: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: ESUI.Space.sm) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(color.opacity(0.14))
                    )

                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                Text(trailing)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Dock

    private var toolbarDock: some View {
        GlassEffectContainer(spacing: ESUI.Space.xs) {
            HStack(spacing: ESUI.Space.xs) {
                dockButton(title: "粘贴截图", systemImage: "doc.on.clipboard") {
                    Task { await viewModel.importClipboardImage() }
                }

                dockButton(title: "选图片", systemImage: "photo") {
                    isPhotoPickerPresented = true
                }

                dockButton(title: "拍照", systemImage: "camera") {
                    guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                        viewModel.presentNotice(
                            tone: .caution,
                            message: ImageTranslateError.cameraUnavailable.localizedDescription
                        )
                        return
                    }
                    isCameraPresented = true
                }

                dockButton(title: "历史", systemImage: "clock") {
                    isHistoryPresented = true
                }
            }
        }
        .padding(.horizontal, ESUI.screenHorizontalPadding)
        .padding(.bottom, ESUI.Space.xs)
    }

    private func dockButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .medium))
                Text(title)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Actions

    private func swapLanguages() async {
        let next: ImageTranslateTargetLanguage = viewModel.targetLanguage == .simplifiedChinese
            ? .english
            : .simplifiedChinese
        await switchTargetLanguage(to: next)
    }

    private func switchTargetLanguage(to language: ImageTranslateTargetLanguage) async {
        guard language != viewModel.targetLanguage else { return }
        await viewModel.updateTargetLanguage(language)

        guard hasInputText, viewModel.canTranslate else { return }
        await viewModel.translateCurrentText()
    }

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

    private func noticeToast(_ notice: ImageTranslateNotice) -> some View {
        let tone: ESStatusBadge.Tone = notice.tone == .caution ? .warning : .success

        return ESStatusBanner(
            title: notice.message,
            systemImage: notice.tone == .caution ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
            tone: tone
        )
        .background(
            RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Detail sheets

private enum ImageTranslateDetailSheet: String, Identifiable {
    case details
    case comparison

    var id: String { rawValue }

    var title: String {
        switch self {
        case .details: return "详细释义"
        case .comparison: return "原文对照"
        }
    }
}

private struct ImageTranslateDetailSheetView: View {
    let sheet: ImageTranslateDetailSheet
    @ObservedObject var viewModel: ImageTranslateViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                switch sheet {
                case .details:
                    detailSections
                case .comparison:
                    comparisonSection
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(sheet.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var detailSections: some View {
        if !viewModel.meanings.isEmpty {
            Section("释义") {
                ForEach(Array(viewModel.meanings.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 4) {
                        if !item.partOfSpeech.isEmpty {
                            Text(item.partOfSpeech)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                        Text(item.meaning)
                            .font(.subheadline)
                    }
                    .padding(.vertical, 2)
                }
            }
        }

        if !viewModel.examples.isEmpty {
            Section("例句") {
                ForEach(Array(viewModel.examples.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.source)
                            .font(.subheadline.weight(.medium))
                        Text(item.translation)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }

        if !viewModel.collocations.isEmpty {
            Section("常用搭配") {
                ForEach(Array(viewModel.collocations.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.phrase)
                            .font(.subheadline.weight(.medium))
                        Text(item.translation)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if !item.note.isEmpty {
                            Text(item.note)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var comparisonSection: some View {
        Section {
            ForEach(viewModel.alignedSections) { section in
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.sourceText.isEmpty ? " " : section.sourceText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(section.translatedText.isEmpty ? " " : section.translatedText)
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private struct ImageTranslateHistorySheet: View {
    @ObservedObject var viewModel: ImageTranslateViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.history.isEmpty {
                    ESEmptyState(
                        title: "暂无历史",
                        message: "翻译过的内容会保存在这里。",
                        systemImage: "clock"
                    )
                } else {
                    List {
                        ForEach(viewModel.history) { record in
                            Button {
                                viewModel.loadHistorySession(record)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.title)
                                        .font(.subheadline.weight(.medium))
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
                                .padding(.vertical, 2)
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                viewModel.deleteHistoryRecord(viewModel.history[index])
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("历史")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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
