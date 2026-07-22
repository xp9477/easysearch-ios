import AVFoundation
import Foundation
import UniformTypeIdentifiers

enum WebDAVStreamingError: LocalizedError {
    case invalidRequest
    case invalidResponse
    case rangeUnsupported
    case server(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "无法创建视频流请求。"
        case .invalidResponse:
            return "WebDAV 服务器返回了无效的视频响应。"
        case .rangeUnsupported:
            return "服务器不支持视频分段读取，正在改用完整下载预览。"
        case let .server(statusCode):
            return "视频流请求失败（HTTP \(statusCode)）。"
        }
    }
}

final class WebDAVStreamResourceLoader: NSObject, AVAssetResourceLoaderDelegate, URLSessionDataDelegate {
    private final class LoadingContext {
        let loadingRequest: AVAssetResourceLoadingRequest
        let requestedOffset: Int64
        let requestedLength: Int64?
        var task: URLSessionDataTask?
        var bytesToSkip: Int64 = 0
        var bytesResponded: Int64 = 0

        init(
            loadingRequest: AVAssetResourceLoadingRequest,
            requestedOffset: Int64,
            requestedLength: Int64?
        ) {
            self.loadingRequest = loadingRequest
            self.requestedOffset = requestedOffset
            self.requestedLength = requestedLength
        }
    }

    let asset: AVURLAsset

    private let item: WebDAVItem
    private let baseRequest: URLRequest
    private let delegateQueue = DispatchQueue(label: "com.easysearch.webdav.streaming")
    private let sessionDelegateQueue: OperationQueue
    private let onFailure: (Error) -> Void
    private var session: URLSession!
    private var contexts: [Int: LoadingContext] = [:]
    private var isInvalidated = false

    init(
        configuration: WebDAVConfiguration,
        item: WebDAVItem,
        onFailure: @escaping (Error) -> Void
    ) throws {
        let request = try WebDAVClient(configuration: configuration)
            .makeStreamingRequest(for: item, rangeHeader: nil)
        guard let remoteURL = request.url,
              var components = URLComponents(url: remoteURL, resolvingAgainstBaseURL: false) else {
            throw WebDAVStreamingError.invalidRequest
        }
        components.scheme = "easysearch-webdav"
        guard let assetURL = components.url else {
            throw WebDAVStreamingError.invalidRequest
        }

        self.item = item
        self.baseRequest = request
        self.onFailure = onFailure
        let operationQueue = OperationQueue()
        operationQueue.maxConcurrentOperationCount = 1
        operationQueue.qualityOfService = .userInitiated
        operationQueue.underlyingQueue = delegateQueue
        self.sessionDelegateQueue = operationQueue
        self.asset = AVURLAsset(url: assetURL)
        super.init()

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.urlCache = nil
        sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        sessionConfiguration.waitsForConnectivity = true
        sessionConfiguration.timeoutIntervalForRequest = 60
        sessionConfiguration.timeoutIntervalForResource = 6 * 60 * 60
        self.session = URLSession(
            configuration: sessionConfiguration,
            delegate: self,
            delegateQueue: operationQueue
        )
        asset.resourceLoader.setDelegate(self, queue: delegateQueue)
    }

    func invalidate() {
        delegateQueue.async { [weak self] in
            guard let self, !self.isInvalidated else { return }
            self.isInvalidated = true
            for context in self.contexts.values {
                context.task?.cancel()
            }
            self.contexts.removeAll()
            self.asset.cancelLoading()
            self.session.invalidateAndCancel()
        }
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard !isInvalidated else { return false }

        let descriptor = requestDescriptor(for: loadingRequest)
        if descriptor.length == 0 {
            fillContentInformationFromItem(loadingRequest.contentInformationRequest)
            loadingRequest.finishLoading()
            return true
        }
        var request = baseRequest
        request.setValue(descriptor.rangeHeader, forHTTPHeaderField: "Range")
        let task = session.dataTask(with: request)
        let context = LoadingContext(
            loadingRequest: loadingRequest,
            requestedOffset: descriptor.offset,
            requestedLength: descriptor.length
        )
        context.task = task
        contexts[task.taskIdentifier] = context
        task.resume()
        return true
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        guard let entry = contexts.first(where: { $0.value.loadingRequest === loadingRequest }) else {
            return
        }
        contexts.removeValue(forKey: entry.key)
        entry.value.task?.cancel()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let context = contexts[dataTask.taskIdentifier],
              let response = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            return
        }

        guard response.statusCode == 200 || response.statusCode == 206 else {
            completionHandler(.cancel)
            finish(
                taskIdentifier: dataTask.taskIdentifier,
                error: WebDAVStreamingError.server(statusCode: response.statusCode),
                notifyFailure: true
            )
            return
        }

        let responseOffset = response.statusCode == 206
            ? contentRangeStart(response.value(forHTTPHeaderField: "Content-Range")) ?? context.requestedOffset
            : 0
        guard responseOffset <= context.requestedOffset else {
            completionHandler(.cancel)
            finish(
                taskIdentifier: dataTask.taskIdentifier,
                error: WebDAVStreamingError.invalidResponse,
                notifyFailure: true
            )
            return
        }
        if response.statusCode == 200, context.requestedOffset > 0 {
            completionHandler(.cancel)
            finish(
                taskIdentifier: dataTask.taskIdentifier,
                error: WebDAVStreamingError.rangeUnsupported,
                notifyFailure: true
            )
            return
        }

        context.bytesToSkip = context.requestedOffset - responseOffset
        fillContentInformation(context.loadingRequest.contentInformationRequest, response: response)
        completionHandler(.allow)

        if context.loadingRequest.dataRequest == nil {
            finish(taskIdentifier: dataTask.taskIdentifier, error: nil, notifyFailure: false)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let context = contexts[dataTask.taskIdentifier],
              let dataRequest = context.loadingRequest.dataRequest else { return }

        var chunk = data
        if context.bytesToSkip > 0 {
            let skipped = min(context.bytesToSkip, Int64(chunk.count))
            context.bytesToSkip -= skipped
            chunk.removeFirst(Int(skipped))
        }
        guard !chunk.isEmpty else { return }

        if let requestedLength = context.requestedLength {
            let remaining = requestedLength - context.bytesResponded
            guard remaining > 0 else {
                finish(taskIdentifier: dataTask.taskIdentifier, error: nil, notifyFailure: false)
                return
            }
            let acceptedCount = min(Int64(chunk.count), remaining)
            dataRequest.respond(with: Data(chunk.prefix(Int(acceptedCount))))
            context.bytesResponded += acceptedCount
            if context.bytesResponded >= requestedLength {
                finish(taskIdentifier: dataTask.taskIdentifier, error: nil, notifyFailure: false)
            }
        } else {
            dataRequest.respond(with: chunk)
            context.bytesResponded += Int64(chunk.count)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard contexts[task.taskIdentifier] != nil else { return }
        if let error, (error as NSError).code != NSURLErrorCancelled {
            finish(
                taskIdentifier: task.taskIdentifier,
                error: error,
                notifyFailure: true,
                cancelTask: false
            )
        } else {
            finish(
                taskIdentifier: task.taskIdentifier,
                error: nil,
                notifyFailure: false,
                cancelTask: false
            )
        }
    }

    private func requestDescriptor(
        for loadingRequest: AVAssetResourceLoadingRequest
    ) -> (offset: Int64, length: Int64?, rangeHeader: String) {
        guard let dataRequest = loadingRequest.dataRequest else {
            return (0, 1, "bytes=0-0")
        }

        let offset = max(dataRequest.currentOffset, dataRequest.requestedOffset)
        let availableLength = item.contentLength.map { max($0 - offset, 0) }
        let requestedLength: Int64?
        if dataRequest.requestsAllDataToEndOfResource {
            requestedLength = availableLength
        } else {
            let value = Int64(max(dataRequest.requestedLength, 1))
            requestedLength = availableLength.map { min($0, value) } ?? value
        }

        let rangeHeader: String
        if let requestedLength, requestedLength > 0 {
            let (end, overflow) = offset.addingReportingOverflow(requestedLength - 1)
            rangeHeader = overflow ? "bytes=\(offset)-" : "bytes=\(offset)-\(end)"
        } else {
            rangeHeader = "bytes=\(offset)-"
        }
        return (offset, requestedLength, rangeHeader)
    }

    private func fillContentInformation(
        _ information: AVAssetResourceLoadingContentInformationRequest?,
        response: HTTPURLResponse
    ) {
        guard let information else { return }
        information.contentType = contentTypeIdentifier(response: response)
        let contentLength = totalContentLength(response: response)
            ?? item.contentLength
            ?? response.expectedContentLength
        information.contentLength = max(contentLength, 0)
        information.isByteRangeAccessSupported = response.statusCode == 206
            || response.value(forHTTPHeaderField: "Accept-Ranges")?.lowercased().contains("bytes") == true
    }

    private func fillContentInformationFromItem(
        _ information: AVAssetResourceLoadingContentInformationRequest?
    ) {
        guard let information else { return }
        information.contentType = itemContentTypeIdentifier()
        information.contentLength = max(item.contentLength ?? 0, 0)
        information.isByteRangeAccessSupported = true
    }

    private func contentTypeIdentifier(response: HTTPURLResponse) -> String? {
        if let mimeType = response.mimeType,
           let type = UTType(mimeType: mimeType) {
            return type.identifier
        }
        if let contentType = item.contentType,
           let mimeType = contentType.split(separator: ";").first,
           let type = UTType(mimeType: String(mimeType)) {
            return type.identifier
        }
        let fileExtension = (item.name as NSString).pathExtension
        return UTType(filenameExtension: fileExtension)?.identifier
    }

    private func itemContentTypeIdentifier() -> String? {
        if let contentType = item.contentType,
           let mimeType = contentType.split(separator: ";").first,
           let type = UTType(mimeType: String(mimeType)) {
            return type.identifier
        }
        let fileExtension = (item.name as NSString).pathExtension
        return UTType(filenameExtension: fileExtension)?.identifier
    }

    private func contentRangeStart(_ header: String?) -> Int64? {
        guard let header,
              let range = header.split(separator: " ").last?.split(separator: "/").first,
              let start = range.split(separator: "-").first else { return nil }
        return Int64(start)
    }

    private func totalContentLength(response: HTTPURLResponse) -> Int64? {
        guard let value = response.value(forHTTPHeaderField: "Content-Range")?
            .split(separator: "/")
            .last,
              value != "*" else { return nil }
        return Int64(value)
    }

    private func finish(
        taskIdentifier: Int,
        error: Error?,
        notifyFailure: Bool,
        cancelTask: Bool = true
    ) {
        guard let context = contexts.removeValue(forKey: taskIdentifier) else { return }
        if cancelTask {
            context.task?.cancel()
        }
        if let error {
            context.loadingRequest.finishLoading(with: error)
            if notifyFailure, !isInvalidated {
                onFailure(error)
            }
        } else {
            context.loadingRequest.finishLoading()
        }
    }
}
