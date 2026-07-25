import Foundation
import UIKit

struct AppUpdateManifest: Codable, Equatable {
    let version: String
    let build: String
    let buildNumber: Int?
    let ipaURL: URL
    let releasedAt: String?
    let notes: String?
    let minOS: String?

    var resolvedBuildNumber: Int {
        if let buildNumber {
            return buildNumber
        }
        return Int(build.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    var displayVersion: String {
        let versionText = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let buildText = build.trimmingCharacters(in: .whitespacesAndNewlines)
        if versionText.isEmpty {
            return buildText.isEmpty ? "未知版本" : buildText
        }
        if buildText.isEmpty || buildText == versionText {
            return versionText
        }
        return "\(versionText) (\(buildText))"
    }
}

enum AppUpdateCheckResult: Equatable {
    case upToDate(current: String, remote: AppUpdateManifest)
    case updateAvailable(current: String, remote: AppUpdateManifest)
    case unavailable(message: String)
}

@MainActor
final class AppUpdateService: ObservableObject {
    static let shared = AppUpdateService()

    /// Public MinIO prefix for update metadata + IPA. No credentials needed.
    static let publicBaseURL = URL(string: "https://s3.990226.xyz:50442/files/easysearch-iOS")!

    @Published private(set) var isChecking = false
    @Published private(set) var isDownloading = false
    @Published private(set) var downloadProgress: Double = 0
    @Published private(set) var statusMessage: String?
    @Published private(set) var lastResult: AppUpdateCheckResult?
    @Published private(set) var downloadedIPAURL: URL?

    private let session: URLSession
    private var downloadTask: URLSessionDownloadTask?
    private var downloadDelegate: DownloadProgressDelegate?
    private var downloadSession: URLSession?

    init(session: URLSession = .shared) {
        self.session = session
    }

    var currentVersionText: String {
        Self.makeVersionText(version: Self.localShortVersion, build: Self.localBuild)
    }

    func checkForUpdates() async {
        guard !isChecking else { return }
        isChecking = true
        statusMessage = "正在检查更新…"
        defer { isChecking = false }

        do {
            let manifest = try await fetchManifest()
            let current = currentVersionText
            let localBuild = Self.localBuildNumber
            let remoteBuild = manifest.resolvedBuildNumber

            if remoteBuild > localBuild {
                lastResult = .updateAvailable(current: current, remote: manifest)
                statusMessage = "发现新版本 \(manifest.displayVersion)"
            } else {
                lastResult = .upToDate(current: current, remote: manifest)
                statusMessage = "已是最新版本 \(current)"
            }
        } catch {
            lastResult = .unavailable(message: error.localizedDescription)
            statusMessage = "检查失败：\(error.localizedDescription)"
        }
    }

    func downloadLatestIPA() async -> URL? {
        guard case let .updateAvailable(_, remote) = lastResult else {
            statusMessage = "请先检查更新"
            return nil
        }
        guard !isDownloading else { return nil }

        isDownloading = true
        downloadProgress = 0
        statusMessage = "正在下载 IPA…"
        defer {
            isDownloading = false
            downloadTask = nil
            downloadDelegate = nil
            downloadSession?.finishTasksAndInvalidate()
            downloadSession = nil
        }

        do {
            let fileURL = try await downloadFile(from: remote.ipaURL, suggestedName: "EasySearch-unsigned.ipa")
            downloadedIPAURL = fileURL
            statusMessage = "下载完成，请分享到签名工具后重签安装"
            return fileURL
        } catch {
            statusMessage = "下载失败：\(error.localizedDescription)"
            return nil
        }
    }

    func presentShareSheet(for fileURL: URL) {
        guard let presenter = Self.topViewController() else {
            statusMessage = "无法打开分享面板"
            return
        }

        let controller = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 1,
                height: 1
            )
            popover.permittedArrowDirections = []
        }
        presenter.present(controller, animated: true)
    }

    // MARK: - Private

    private func fetchManifest() async throws -> AppUpdateManifest {
        let url = Self.publicBaseURL.appendingPathComponent("latest.json")
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw AppUpdateError.httpStatus(http.statusCode)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(AppUpdateManifest.self, from: data)
    }

    private func downloadFile(from remoteURL: URL, suggestedName: String) async throws -> URL {
        let tempURL: URL = try await withCheckedThrowingContinuation { continuation in
            let delegate = DownloadProgressDelegate { [weak self] progress in
                Task { @MainActor in
                    self?.downloadProgress = progress
                }
            } completion: { result in
                continuation.resume(with: result)
            }
            self.downloadDelegate = delegate

            let downloadSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            self.downloadSession = downloadSession
            let task = downloadSession.downloadTask(with: remoteURL)
            self.downloadTask = task
            task.resume()
        }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EasySearchUpdates", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(suggestedName)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: tempURL, to: dest)
        return dest
    }

    private static var localShortVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static var localBuild: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static var localBuildNumber: Int {
        Int(localBuild) ?? 0
    }

    private static func makeVersionText(version: String, build: String) -> String {
        if version.isEmpty && build.isEmpty { return "未知" }
        if version.isEmpty { return build }
        if build.isEmpty { return version }
        return "\(version) (\(build))"
    }

    private static func topViewController(
        base: UIViewController? = {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let windows = scenes.flatMap { $0.windows }
            let window = windows.first(where: { $0.isKeyWindow }) ?? windows.first
            return window?.rootViewController
        }()
    ) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            return topViewController(base: tab.selectedViewController)
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }
}

private enum AppUpdateError: LocalizedError {
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case let .httpStatus(code):
            return "服务器返回 \(code)"
        }
    }
}

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    private let onProgress: (Double) -> Void
    private let onCompletion: (Result<URL, Error>) -> Void
    private var hasCompleted = false

    init(onProgress: @escaping (Double) -> Void, completion: @escaping (Result<URL, Error>) -> Void) {
        self.onProgress = onProgress
        self.onCompletion = completion
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let http = downloadTask.response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            complete(.failure(AppUpdateError.httpStatus(http.statusCode)))
            return
        }

        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("easysearch-download-\(UUID().uuidString).ipa")
        do {
            if FileManager.default.fileExists(atPath: tempFile.path) {
                try FileManager.default.removeItem(at: tempFile)
            }
            try FileManager.default.copyItem(at: location, to: tempFile)
            complete(.success(tempFile))
        } catch {
            complete(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            complete(.failure(error))
        }
    }

    private func complete(_ result: Result<URL, Error>) {
        guard !hasCompleted else { return }
        hasCompleted = true
        onCompletion(result)
    }
}
