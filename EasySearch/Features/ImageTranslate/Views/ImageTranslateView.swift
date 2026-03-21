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
    @State private var isComparisonExpanded = false

    private let accentColor = Color(red: 0.05, green: 0.67, blue: 0.73)
    private let accentDeepColor = Color(red: 0.05, green: 0.23, blue: 0.29)
    private let accentSoftColor = Color(red: 0.79, green: 0.95, blue: 0.96)

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
            VStack(alignment: .leading, spacing: 20) {
                captureDeck

                workspaceCard

                if viewModel.hasTranslation {
                    translationCard
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 120)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("截图翻译")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .overlay(alignment: .top) {
            if let notice = viewModel.notice {
                noticeToast(notice)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: viewModel.notice)
        .task {
            await viewModel.prepare()
        }
        .onChange(of: viewModel.latestTranslation) { _ in
            isComparisonExpanded = false
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

    private var captureDeck: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accentColor, accentDeepColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("截图翻译")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        HStack(spacing: 8) {
                            deckPill(systemImage: "globe", title: viewModel.targetLanguage.title)

                            if viewModel.isRecognizingText {
                                deckPill(systemImage: "viewfinder", title: "识别中")
                            } else if viewModel.isTranslating {
                                deckPill(systemImage: "sparkles", title: "翻译中")
                            }
                        }
                    }

                    Spacer(minLength: 12)

                    Button {
                        viewModel.startFreshSession()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.16))
                            )
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 12) {
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

                HStack(spacing: 10) {
                    Menu {
                        ForEach(ImageTranslateTargetLanguage.allCases) { language in
                            Button(language.title) {
                                viewModel.targetLanguage = language
                            }
                        }
                    } label: {
                        controlPill(systemImage: "globe.asia.australia.fill", title: "输出", value: viewModel.targetLanguage.title)
                    }
                    .buttonStyle(.plain)

                    if hasActiveSession {
                        quickStatusStrip
                    }
                }
            }
            .padding(22)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: accentDeepColor.opacity(0.20), radius: 18, y: 10)
    }

    private var quickStatusStrip: some View {
        HStack(spacing: 8) {
            Image(systemName: viewModel.hasTranslation ? "checkmark.seal.fill" : "wand.and.stars")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))

            Text(
                viewModel.hasTranslation
                    ? "已生成结果"
                    : (viewModel.selectedImage != nil ? (hasRecognizedText ? "可继续处理" : "待识别") : "可直接开始")
            )
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.86))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.12))
        )
    }

    private var workspaceCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                sectionHeader("工作区")

                Spacer()

                if !viewModel.extractedText.isEmpty {
                    metaToken(title: "\(viewModel.extractedText.count) 字", tint: .secondary)
                }

                if viewModel.needsRetranslation {
                    metaToken(title: "待重翻", tint: .orange)
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
                HStack(spacing: 10) {
                    Image(systemName: primaryActionIcon)
                    Text(primaryActionTitle)
                    Spacer()
                    if viewModel.isRecognizingText || viewModel.isTranslating {
                        ProgressView()
                            .tint(.white)
                    }
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [accentColor, accentDeepColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(!canRunPrimaryAction)
            .opacity(canRunPrimaryAction ? 1 : 0.55)
        }
        .padding(20)
        .cardStyle()
    }

    private func imageWorkbench(_ image: UIImage) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accentSoftColor.opacity(0.78), Color(.secondarySystemGroupedBackground)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        statusChip(title: viewModel.imageStatusText, color: accentColor, compact: true)

                        if viewModel.isRecognizingText {
                            statusChip(title: "识别中", color: .orange, compact: true)
                        } else if viewModel.isTranslating {
                            statusChip(title: "翻译中", color: .green, compact: true)
                        }
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 8) {
                        imageToolButton(title: "裁剪", systemImage: "crop") {
                            isCropSheetPresented = true
                        }
                        .disabled(viewModel.isRecognizingText || viewModel.isTranslating)

                        imageToolButton(title: hasRecognizedText ? "重识别" : "识别全文", systemImage: "viewfinder") {
                            Task {
                                await viewModel.reRecognizeSelectedImage()
                            }
                        }
                        .disabled(viewModel.isRecognizingText || viewModel.isTranslating)
                    }
                }
                .padding(14)

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 280)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(accentColor.opacity(0.10), lineWidth: 1)
        )
    }

    private var emptyWorkbench: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(accentColor.opacity(0.12))
                .frame(width: 54, height: 54)
                .overlay(
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(accentColor)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("导入图片或直接粘贴文本")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("可先裁剪，再识别翻译")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.tertiarySystemFill))
        )
    }

    private var textWorkbench: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Text("识别文本")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                if !viewModel.extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        viewModel.copyText(viewModel.extractedText, successMessage: "已复制识别文本。")
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 34, height: 34)
                            .background(
                                Circle()
                                    .fill(Color(.tertiarySystemFill))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.tertiarySystemFill))

                if viewModel.extractedText.isEmpty {
                    Text("可直接粘贴文本")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                }

                TextEditor(text: $viewModel.extractedText)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(minHeight: 170)
                    .background(Color.clear)
            }
        }
    }

    private var translationCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                sectionHeader("译文")

                Spacer()

                Button {
                    viewModel.copyText(viewModel.latestTranslation, successMessage: "已复制翻译结果。")
                } label: {
                    Label("复制", systemImage: "doc.on.doc.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(accentColor.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 16) {
                Text(viewModel.latestTranslation)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)

                HStack(spacing: 8) {
                    if let detectedSourceLanguage = viewModel.detectedSourceLanguage,
                       !detectedSourceLanguage.isEmpty {
                        statusChip(title: "源 \(detectedSourceLanguage)", color: .secondary)
                    }

                    statusChip(title: "目标 \(viewModel.targetLanguage.title)", color: accentColor)
                }

                if !viewModel.translationNotes.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(accentColor)
                            .padding(.top, 2)

                        Text(viewModel.translationNotes)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accentSoftColor.opacity(0.62), Color(.tertiarySystemFill)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )

            if !viewModel.alignedSections.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                            isComparisonExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text("对照")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary)

                            Spacer()

                            Text("\(viewModel.alignedSections.count)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(accentColor)

                            Image(systemName: isComparisonExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    if isComparisonExpanded {
                        ForEach(viewModel.alignedSections) { section in
                            comparisonRow(section)
                        }
                    }
                }
            }
        }
        .padding(20)
        .cardStyle()
    }

    private func comparisonRow(_ section: AlignedTextSection) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                comparisonToken(title: "原文", tint: .secondary)

                Text(section.sourceText.isEmpty ? " " : section.sourceText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                comparisonToken(title: "译文", tint: accentColor)

                Text(section.translatedText.isEmpty ? " " : section.translatedText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.primary)
    }

    private func statusChip(
        title: String,
        color: Color,
        compact: Bool = false,
        fillColor: Color? = nil
    ) -> some View {
        Text(title)
            .font(.system(size: compact ? 11 : 12, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.vertical, compact ? 6 : 8)
            .background(
                Capsule(style: .continuous)
                    .fill(fillColor ?? color.opacity(0.14))
            )
    }

    private func noticeToast(_ notice: ImageTranslateNotice) -> some View {
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

        return HStack(alignment: .center, spacing: 10) {
            Image(systemName: notice.tone == .caution ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint)

            Text(notice.message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(tint.opacity(0.20), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }

    private func deckPill(systemImage: String, title: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))

            Text(title)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(.white.opacity(0.90))
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.12))
        )
    }

    private func deckActionButton(
        title: String,
        icon: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .foregroundStyle(Color.white.opacity(isEnabled ? 1 : 0.45))
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(isEnabled ? 0.14 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(isEnabled ? 0.10 : 0.04), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private func controlPill(systemImage: String, title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.84))

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.76))

            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.12))
        )
    }

    private func metaToken(title: String, tint: Color) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            )
    }

    private func imageToolButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                )
        }
        .buttonStyle(.plain)
    }

    private func comparisonToken(title: String, tint: Color) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            )
    }
}

private struct CropImageEditor: View {
    @Environment(\.dismiss) private var dismiss

    let image: UIImage
    let onConfirm: (CGRect) -> Void

    @State private var selectionRect: CGRect?
    @State private var imageFrame: CGRect = .zero
    private let cropCoordinateSpace = "ImageTranslateCropCanvas"

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
                            Text("拖出要翻译的区域")
                                .font(.system(size: 15, weight: .semibold))
                            Text("重新拖动可改选")
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
                .coordinateSpace(name: cropCoordinateSpace)
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
