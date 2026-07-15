import AVKit
import Foundation
import QuickLook
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct WebDAVPreviewRequest: Identifiable {
    let id = UUID()
    let configuration: WebDAVConfiguration
    let item: WebDAVItem
}

struct WebDAVPreviewView: View {
    @Environment(\.dismiss) private var dismiss

    let request: WebDAVPreviewRequest
    @State private var localURL: URL?
    @State private var progress: WebDAVTransferProgress?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var saveMessage: String?
    @State private var hasUnsavedTextChanges = false
    @State private var isShowingDiscardConfirmation = false
    @State private var loadToken = UUID()

    var body: some View {
        Group {
            if let localURL {
                viewer(for: localURL)
            } else if isLoading {
                loadingContent
            } else {
                ESEmptyState(
                    title: "无法打开文件",
                    message: errorMessage ?? "文件预览准备失败。",
                    systemImage: "doc.badge.ellipsis"
                )
                .padding(20)
            }
        }
        .navigationTitle(request.item.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(usesQuickLook ? .hidden : .visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { requestDismiss() }
                    .disabled(isSaving)
            }
            if localURL == nil, !isLoading {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        loadToken = UUID()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("重试")
                }
            }
        }
        .overlay {
            if isSaving {
                ProgressView("正在保存到 WebDAV…")
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .interactiveDismissDisabled(isSaving || hasUnsavedTextChanges)
        .alert("文件预览", isPresented: Binding(
            get: { saveMessage != nil },
            set: { if !$0 { saveMessage = nil } }
        )) {
            Button("好", role: .cancel) { saveMessage = nil }
        } message: {
            Text(saveMessage ?? "")
        }
        .confirmationDialog(
            "放弃未保存的修改？",
            isPresented: $isShowingDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("放弃修改", role: .destructive) {
                hasUnsavedTextChanges = false
                dismiss()
            }
            Button("继续编辑", role: .cancel) {}
        }
        .task(id: loadToken) {
            await loadPreview()
        }
        .onDisappear {
            if let localURL {
                WebDAVLocalFileStore.removePreview(containing: localURL)
            }
        }
    }

    private var loadingContent: some View {
        VStack(spacing: 16) {
            if let fraction = progress?.fractionCompleted {
                ProgressView(value: fraction)
                    .frame(maxWidth: 240)
                Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
            Text("正在准备预览…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func viewer(for url: URL) -> some View {
        if WebDAVPreviewKind(url: url) == .video {
            WebDAVVideoPlayerView(url: url)
                .ignoresSafeArea(edges: .bottom)
        } else if WebDAVPreviewKind(url: url) == .editableText {
            WebDAVTextEditorView(
                url: url,
                hasUnsavedChanges: $hasUnsavedTextChanges,
                save: { try await replaceRemoteFile(with: url) }
            )
        } else if QLPreviewController.canPreview(url as NSURL) {
            WebDAVQuickLookView(
                url: url,
                onClose: { if !isSaving { requestDismiss() } },
                onEdited: { editedURL in saveQuickLookEdit(from: editedURL) }
            )
        } else {
            VStack(spacing: 18) {
                ESEmptyState(
                    title: "系统无法预览此格式",
                    message: "可以交给支持该格式的其他 App 打开。",
                    systemImage: "doc.badge.ellipsis"
                )
                ShareLink(item: url) {
                    Label("用其他 App 打开", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
    }

    private func loadPreview() async {
        if let localURL {
            WebDAVLocalFileStore.removePreview(containing: localURL)
            self.localURL = nil
        }
        isLoading = true
        errorMessage = nil
        progress = nil
        do {
            let url = try await WebDAVClient(configuration: request.configuration)
                .downloadForPreview(item: request.item) { progress in
                    Task { @MainActor in
                        self.progress = progress
                    }
                }
            guard !Task.isCancelled else {
                WebDAVLocalFileStore.removePreview(containing: url)
                return
            }
            localURL = url
            isLoading = false
        } catch is CancellationError {
            return
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    private var usesQuickLook: Bool {
        guard let localURL,
              WebDAVPreviewKind(url: localURL) == .quickLook else { return false }
        return QLPreviewController.canPreview(localURL as NSURL)
    }

    private func saveQuickLookEdit(from url: URL) {
        guard !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await replaceRemoteFile(with: url)
                saveMessage = "修改已保存到 WebDAV。"
            } catch {
                saveMessage = error.localizedDescription
            }
        }
    }

    private func requestDismiss() {
        if hasUnsavedTextChanges {
            isShowingDiscardConfirmation = true
        } else {
            dismiss()
        }
    }

    private func replaceRemoteFile(with url: URL) async throws {
        let stagedEdit = try WebDAVLocalFileStore.stageEditedFile(url)
        defer { WebDAVLocalFileStore.removeStagedEdit(stagedEdit) }
        try await WebDAVClient(configuration: request.configuration).replace(
            localURL: stagedEdit.localURL,
            item: request.item,
            force: false
        )
    }
}

private enum WebDAVPreviewKind: Equatable {
    case video
    case editableText
    case quickLook

    init(url: URL) {
        let ext = url.pathExtension.lowercased()
        if let type = UTType(filenameExtension: ext),
           type.conforms(to: .audiovisualContent) || type.conforms(to: .movie) {
            self = .video
            return
        }
        let editableExtensions: Set<String> = [
            "txt", "md", "markdown", "json", "xml", "csv", "tsv", "yaml", "yml",
            "log", "ini", "conf", "swift", "js", "ts", "css", "html", "htm", "py", "sh"
        ]
        if editableExtensions.contains(ext) {
            self = .editableText
            return
        }
        self = .quickLook
    }
}

private struct WebDAVTextEditorView: View {
    let url: URL
    @Binding var hasUnsavedChanges: Bool
    let save: () async throws -> Void

    @State private var text = ""
    @State private var originalText = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var hasChanges = false
    @State private var loadErrorMessage: String?
    @State private var saveErrorMessage: String?
    @State private var statusMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("正在读取文档…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadErrorMessage {
                ESEmptyState(
                    title: "无法编辑文档",
                    message: loadErrorMessage,
                    systemImage: "doc.text.magnifyingglass"
                )
                .padding(20)
            } else {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 8)
                    .onChange(of: text) { newValue in
                        if !isLoading {
                            hasChanges = newValue != originalText
                            hasUnsavedChanges = hasChanges
                            if hasChanges { statusMessage = nil }
                        }
                    }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.bar)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    saveChanges()
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Image(systemName: "checkmark")
                    }
                }
                .accessibilityLabel("保存文档")
                .disabled(isLoading || isSaving || !hasChanges)
            }
        }
        .task { loadText() }
        .alert("保存失败", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("好", role: .cancel) { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? "")
        }
    }

    private func loadText() {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            if let size = values.fileSize, size > 5 * 1_024 * 1_024 {
                throw WebDAVError.textFileTooLarge
            }
            let data = try Data(contentsOf: url)
            guard let value = String(data: data, encoding: .utf8) else {
                throw WebDAVError.unsupportedTextEncoding
            }
            text = value
            originalText = value
            hasChanges = false
            hasUnsavedChanges = false
            isLoading = false
        } catch {
            loadErrorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func saveChanges() {
        isSaving = true
        statusMessage = nil
        saveErrorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                try Data(text.utf8).write(to: url, options: .atomic)
                try await save()
                originalText = text
                hasChanges = false
                hasUnsavedChanges = false
                statusMessage = "已保存到 WebDAV"
            } catch {
                saveErrorMessage = error.localizedDescription
            }
        }
    }
}

private struct WebDAVQuickLookView: UIViewControllerRepresentable {
    let url: URL
    let onClose: () -> Void
    let onEdited: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url, onClose: onClose, onEdited: onEdited)
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        controller.navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: context.coordinator,
            action: #selector(Coordinator.close)
        )
        context.coordinator.previewController = controller
        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.navigationBar.prefersLargeTitles = false
        return navigationController
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {
        context.coordinator.url = url
        context.coordinator.onClose = onClose
        context.coordinator.onEdited = onEdited
        context.coordinator.previewController?.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        var url: URL
        var onClose: () -> Void
        var onEdited: (URL) -> Void
        weak var previewController: QLPreviewController?

        init(url: URL, onClose: @escaping () -> Void, onEdited: @escaping (URL) -> Void) {
            self.url = url
            self.onClose = onClose
            self.onEdited = onEdited
        }

        @objc func close() {
            onClose()
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }

        func previewController(
            _ controller: QLPreviewController,
            editingModeFor previewItem: QLPreviewItem
        ) -> QLPreviewItemEditingMode {
            .updateContents
        }

        func previewController(_ controller: QLPreviewController, didUpdateContentsOf previewItem: QLPreviewItem) {
            onEdited(url)
        }
    }
}

private struct WebDAVVideoPlayerView: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        let player = AVPlayer(url: url)
        context.coordinator.player = player
        controller.player = player
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = true
        controller.videoGravity = .resizeAspect
        player.play()
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.player?.pause()
        controller.player = nil
        coordinator.player = nil
    }

    final class Coordinator {
        var player: AVPlayer?
    }
}
