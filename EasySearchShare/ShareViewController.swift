import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private static let appGroupID = "group.com.easysearch.xp9477"
    private static let inboxDirectoryName = "ShareInbox"
    private var hostingController: UIHostingController<ShareExtensionRootView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        let attachmentCount = extensionItems
            .compactMap(\.attachments)
            .reduce(0) { $0 + $1.count }
        let rootView = ShareExtensionRootView(
            attachmentCount: attachmentCount,
            storeAction: { [weak self] in
                guard let self else { return false }
                return try await self.stageAttachmentsAndOpenApp()
            },
            closeAction: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
        )
        let hostingController = UIHostingController(rootView: rootView)
        self.hostingController = hostingController
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)
    }

    private var extensionItems: [NSExtensionItem] {
        extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
    }

    private func stageAttachmentsAndOpenApp() async throws -> Bool {
        let providers = extensionItems.compactMap(\.attachments).flatMap { $0 }
        guard !providers.isEmpty else { throw ShareExtensionError.noAttachments }

        var stagedAttachments: [StagedAttachment] = []
        let batchID = UUID()
        do {
            for provider in providers {
                stagedAttachments.append(try await stage(provider: provider, batchID: batchID))
            }
            for attachment in stagedAttachments {
                try FileManager.default.moveItem(
                    at: attachment.stagingDirectory,
                    to: attachment.finalDirectory
                )
            }
            guard let markerURL = batchMarkerURL(for: batchID) else {
                throw ShareExtensionError.appGroupUnavailable
            }
            try Data().write(to: markerURL, options: .atomic)
        } catch {
            removeStagedAttachments(stagedAttachments)
            if let markerURL = batchMarkerURL(for: batchID) {
                try? FileManager.default.removeItem(at: markerURL)
            }
            throw error
        }

        guard let url = URL(string: "easysearch://share") else { return false }
        guard let extensionContext else { return false }
        extensionContext.open(url) { didOpen in
            if didOpen {
                extensionContext.completeRequest(returningItems: nil)
            }
        }
        return false
    }

    private func removeStagedAttachments(_ attachments: [StagedAttachment]) {
        for attachment in attachments {
            try? FileManager.default.removeItem(at: attachment.stagingDirectory)
            try? FileManager.default.removeItem(at: attachment.finalDirectory)
        }
    }

    private func batchMarkerURL(for batchID: UUID) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID)?
            .appendingPathComponent(Self.inboxDirectoryName, isDirectory: true)
            .appendingPathComponent(".batch-\(batchID.uuidString).complete")
    }

    private func stage(provider: NSItemProvider, batchID: UUID) async throws -> StagedAttachment {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupID
        ) else {
            throw ShareExtensionError.appGroupUnavailable
        }

        let fileManager = FileManager.default
        let inboxURL = containerURL.appendingPathComponent(Self.inboxDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: inboxURL, withIntermediateDirectories: true)

        let id = UUID()
        let stagingDirectory = inboxURL.appendingPathComponent(".staging-\(id.uuidString)", isDirectory: true)
        let finalDirectory = inboxURL.appendingPathComponent(id.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)

        do {
            let typeIdentifier = preferredTypeIdentifier(for: provider)
            let copiedFileName: String
            if let typeIdentifier {
                do {
                    copiedFileName = try await copyFileRepresentation(
                        from: provider,
                        typeIdentifier: typeIdentifier,
                        into: stagingDirectory
                    )
                } catch {
                    copiedFileName = try await copyLoadedItem(from: provider, into: stagingDirectory)
                }
            } else {
                copiedFileName = try await copyLoadedItem(from: provider, into: stagingDirectory)
            }

            let item = ExtensionSharedInboxItem(
                id: id,
                batchID: batchID,
                displayName: copiedFileName,
                relativePath: copiedFileName,
                contentType: typeIdentifier,
                createdAt: Date()
            )
            try writeManifest(item, in: stagingDirectory)
            try? fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: stagingDirectory.path
            )
            return StagedAttachment(
                stagingDirectory: stagingDirectory,
                finalDirectory: finalDirectory
            )
        } catch {
            try? fileManager.removeItem(at: stagingDirectory)
            throw error
        }
    }

    private func preferredTypeIdentifier(for provider: NSItemProvider) -> String? {
        provider.registeredTypeIdentifiers.first { identifier in
            guard let type = UTType(identifier) else { return false }
            return type.conforms(to: .content) || type.conforms(to: .item)
        }
    }

    private func copyFileRepresentation(
        from provider: NSItemProvider,
        typeIdentifier: String,
        into directory: URL
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { temporaryURL, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let temporaryURL else {
                    continuation.resume(throwing: ShareExtensionError.unreadableAttachment)
                    return
                }

                do {
                    let fileName = Self.preferredFileName(
                        suggestedName: provider.suggestedName,
                        sourceURL: temporaryURL,
                        typeIdentifier: typeIdentifier
                    )
                    let destination = directory.appendingPathComponent(fileName)
                    try FileManager.default.copyItem(at: temporaryURL, to: destination)
                    continuation.resume(returning: fileName)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func copyLoadedItem(from provider: NSItemProvider, into directory: URL) async throws -> String {
        guard let typeIdentifier = provider.registeredTypeIdentifiers.first else {
            throw ShareExtensionError.unreadableAttachment
        }
        let loadedItem: NSSecureCoding = try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let item {
                    continuation.resume(returning: item)
                } else {
                    continuation.resume(throwing: ShareExtensionError.unreadableAttachment)
                }
            }
        }

        let fileName = Self.preferredFileName(
            suggestedName: provider.suggestedName,
            sourceURL: loadedItem as? URL,
            typeIdentifier: typeIdentifier
        )
        let destination = directory.appendingPathComponent(fileName)
        switch loadedItem {
        case let url as URL:
            try FileManager.default.copyItem(at: url, to: destination)
        case let data as Data:
            try data.write(to: destination, options: .atomic)
        case let string as String:
            try Data(string.utf8).write(to: destination, options: .atomic)
        case let image as UIImage:
            let ext = destination.pathExtension.lowercased()
            let data = (ext == "jpg" || ext == "jpeg")
                ? image.jpegData(compressionQuality: 1)
                : image.pngData()
            guard let data else { throw ShareExtensionError.unreadableAttachment }
            try data.write(to: destination, options: .atomic)
        default:
            throw ShareExtensionError.unreadableAttachment
        }
        return fileName
    }

    private func writeManifest(_ item: ExtensionSharedInboxItem, in directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(item)
        try data.write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
    }

    private static func preferredFileName(
        suggestedName: String?,
        sourceURL: URL?,
        typeIdentifier: String
    ) -> String {
        let sourceName = sourceURL?.lastPathComponent ?? ""
        var name = suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if name.isEmpty { name = sourceName }
        if name.isEmpty { name = "分享文件" }

        if URL(fileURLWithPath: name).pathExtension.isEmpty,
           let fileExtension = UTType(typeIdentifier)?.preferredFilenameExtension {
            name.append(".\(fileExtension)")
        }
        return sanitizedFileName(name)
    }

    private static func sanitizedFileName(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:\0")
        let cleaned = value.components(separatedBy: forbidden).joined(separator: "_")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != ".", trimmed != ".." else { return "分享文件" }
        return trimmed
    }
}

private struct ExtensionSharedInboxItem: Codable {
    let id: UUID
    let batchID: UUID
    let displayName: String
    let relativePath: String
    let contentType: String?
    let createdAt: Date
}

private struct StagedAttachment {
    let stagingDirectory: URL
    let finalDirectory: URL
}

private enum ShareExtensionError: LocalizedError {
    case noAttachments
    case appGroupUnavailable
    case unreadableAttachment

    var errorDescription: String? {
        switch self {
        case .noAttachments:
            return "没有找到可处理的分享内容。"
        case .appGroupUnavailable:
            return "共享容器不可用，请检查 EasySearch 的 App Group 配置。"
        case .unreadableAttachment:
            return "无法读取这个分享项目。"
        }
    }
}

private struct ShareExtensionRootView: View {
    enum ViewState {
        case ready
        case staging
        case staged
        case failed(String)
    }

    let attachmentCount: Int
    let storeAction: () async throws -> Bool
    let closeAction: () -> Void

    @State private var state: ViewState = .ready

    var body: some View {
        NavigationStack {
            List {
                Section("分享内容") {
                    Label("\(attachmentCount) 个项目", systemImage: "doc.on.doc")
                }

                Section("选择操作") {
                    Button(action: storeToWebDAV) {
                        HStack {
                            Label("存储到 WebDAV", systemImage: "externaldrive.badge.plus")
                            Spacer()
                            if case .staging = state { ProgressView() }
                        }
                    }
                    .disabled(isBusy || attachmentCount == 0)

                    HStack {
                        Label("其他功能", systemImage: "ellipsis.circle")
                        Spacer()
                        Text("预留")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                if let message {
                    Section {
                        Text(message)
                            .foregroundStyle(messageIsError ? .red : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .navigationTitle("EasySearch")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isStaging)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭", action: closeAction)
                        .disabled(isStaging)
                }
            }
        }
    }

    private var isBusy: Bool {
        if case .staging = state { return true }
        if case .staged = state { return true }
        return false
    }

    private var isStaging: Bool {
        if case .staging = state { return true }
        return false
    }

    private var message: String? {
        switch state {
        case .ready, .staging:
            return nil
        case .staged:
            return "内容已安全暂存。系统未允许分享扩展自动打开主 App，请打开 EasySearch 继续选择远程文件夹。"
        case let .failed(message):
            return message
        }
    }

    private var messageIsError: Bool {
        if case .failed = state { return true }
        return false
    }

    private func storeToWebDAV() {
        state = .staging
        Task {
            do {
                let didOpen = try await storeAction()
                if !didOpen { state = .staged }
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }
}
