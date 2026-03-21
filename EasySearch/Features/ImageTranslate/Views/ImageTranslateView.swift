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

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heroCard

                if viewModel.hasHistory {
                    historyCard
                }

                if viewModel.selectedImage != nil {
                    imageCard
                }

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

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("截图 / 拍照翻译")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
            }

            HStack(spacing: 12) {
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

            HStack {
                Picker("输出语言", selection: $viewModel.targetLanguage) {
                    ForEach(ImageTranslateTargetLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)

                Spacer()
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
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
            sectionHeader("最近")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
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
            sectionHeader("图片")

            if let image = viewModel.selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )

                HStack(alignment: .center, spacing: 10) {
                    statusChip(title: viewModel.imageStatusText, color: .cyan, compact: true)

                    if viewModel.isRecognizingText {
                        statusChip(title: "识别中", color: .orange, compact: true)
                    } else if viewModel.isTranslating {
                        statusChip(title: "翻译中", color: .green, compact: true)
                    }

                    Spacer(minLength: 0)

                    compactToolButton(title: "裁剪", icon: "crop", tint: .cyan) {
                        isCropSheetPresented = true
                    }
                    .disabled(viewModel.isRecognizingText || viewModel.isTranslating)

                    compactToolButton(title: "重识别", icon: "viewfinder", tint: .secondary) {
                        Task {
                            await viewModel.reRecognizeSelectedImage()
                        }
                    }
                    .disabled(viewModel.isRecognizingText || viewModel.isTranslating)
                }
            }
        }
        .padding(24)
        .cardStyle()
    }

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                sectionHeader("文本")

                Spacer()

                if !viewModel.extractedText.isEmpty {
                    Text("\(viewModel.extractedText.count)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                if !viewModel.extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        viewModel.copyText(viewModel.extractedText, successMessage: "已复制识别文本。")
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
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
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(minHeight: 180)
                    .background(Color.clear)
            }

            if viewModel.needsRetranslation {
                Text("文本已改动")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
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
            HStack(alignment: .center, spacing: 12) {
                sectionHeader("结果")

                Spacer()

                Button {
                    viewModel.copyText(viewModel.latestTranslation, successMessage: "已复制翻译结果。")
                } label: {
                    Image(systemName: "doc.on.doc.fill")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.borderless)
            }

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
                    Text(viewModel.translationNotes)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
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
                                .foregroundStyle(.secondary)

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
        .padding(24)
        .cardStyle()
    }

    private var conversationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("追问")

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
                TextField("继续说", text: $viewModel.composerText, axis: .vertical)
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
        VStack(alignment: .leading, spacing: 10) {
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
            .frame(width: 132, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text(record.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            HStack(spacing: 8) {
                statusChip(title: record.targetLanguage.title, color: .cyan)

                Text(relativeDateText(record.updatedAt))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if let detectedSourceLanguage = record.detectedSourceLanguage,
               !detectedSourceLanguage.isEmpty {
                Text(detectedSourceLanguage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 148, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.tertiarySystemFill))
        )
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture {
            viewModel.loadHistorySession(record)
        }
        .contextMenu {
            Button(role: .destructive) {
                viewModel.deleteHistoryRecord(record)
            } label: {
                Label("删除", systemImage: "trash")
            }
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

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.primary)
    }

    private func statusChip(title: String, color: Color, compact: Bool = false) -> some View {
        Text(title)
            .font(.system(size: compact ? 11 : 12, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.vertical, compact ? 6 : 8)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.14))
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

    private func compactToolButton(
        title: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .tint(tint)
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
