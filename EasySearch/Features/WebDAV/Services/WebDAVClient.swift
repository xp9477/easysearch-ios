import Foundation

protocol WebDAVClientProtocol {
    func list(path: String) async throws -> [WebDAVItem]
    func createDirectory(path: String) async throws
    func upload(localURL: URL, remotePath: String) async throws
    func details(for item: WebDAVItem) async throws -> WebDAVItemDetails
    func delete(item: WebDAVItem) async throws
    func replace(localURL: URL, item: WebDAVItem, force: Bool) async throws
    func download(
        item: WebDAVItem,
        into localDirectory: URL,
        progress: @escaping (WebDAVTransferProgress) -> Void
    ) async throws -> URL
    func downloadForPreview(
        item: WebDAVItem,
        progress: @escaping (WebDAVTransferProgress) -> Void
    ) async throws -> URL
}

extension WebDAVClientProtocol {
    func download(item: WebDAVItem, into localDirectory: URL) async throws -> URL {
        try await download(item: item, into: localDirectory, progress: { _ in })
    }
}

final class WebDAVClient: WebDAVClientProtocol {
    private struct PlannedItem {
        let item: WebDAVItem
        let relativePath: String
    }

    private struct DownloadPlan {
        let directories: [PlannedItem]
        let files: [PlannedItem]
        let totalBytes: Int64?
    }

    private let configuration: WebDAVConfiguration
    private let session: URLSession
    private let fileManager: FileManager

    init(
        configuration: WebDAVConfiguration,
        session: URLSession = .shared,
        fileManager: FileManager = .default
    ) {
        self.configuration = configuration
        self.session = session
        self.fileManager = fileManager
    }

    func list(path: String = "") async throws -> [WebDAVItem] {
        let url = try remoteURL(for: path, isCollection: true)
        var request = makeRequest(url: url, method: "PROPFIND")
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("""
        <?xml version="1.0" encoding="utf-8" ?>
        <d:propfind xmlns:d="DAV:">
          <d:prop>
            <d:resourcetype />
            <d:getcontentlength />
            <d:getlastmodified />
            <d:getcontenttype />
            <d:getetag />
          </d:prop>
        </d:propfind>
        """.utf8)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data, accepted: [207])

        let parser = WebDAVListingParser(baseURL: configuration.baseURL, requestedPath: path)
        parser.parse(data)
        guard !parser.hasParseError else { throw WebDAVError.malformedListing }
        return parser.items.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func createDirectory(path: String) async throws {
        let url = try remoteURL(for: path, isCollection: true)
        let request = makeRequest(url: url, method: "MKCOL")
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw WebDAVError.invalidResponse }
        if (200..<300).contains(httpResponse.statusCode) || httpResponse.statusCode == 405 {
            return
        }
        throw WebDAVError.server(statusCode: httpResponse.statusCode, message: "")
    }

    func upload(localURL: URL, remotePath: String) async throws {
        guard fileManager.fileExists(atPath: localURL.path) else {
            throw WebDAVError.localFileMissing
        }

        let resourceValues = try localURL.resourceValues(forKeys: [.isSymbolicLinkKey])
        if resourceValues.isSymbolicLink == true {
            throw WebDAVError.symbolicLinkUnsupported
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: localURL.path, isDirectory: &isDirectory) else {
            throw WebDAVError.localFileMissing
        }

        if isDirectory.boolValue {
            let createdPath = try await createUniqueDirectory(requestedPath: remotePath)
            let children = try fileManager.contentsOfDirectory(
                at: localURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                if try child.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                    continue
                }
                try await upload(localURL: child, remotePath: join(createdPath, child.lastPathComponent))
            }
            return
        }

        try await uploadFile(localURL: localURL, requestedPath: remotePath)
    }

    func details(for item: WebDAVItem) async throws -> WebDAVItemDetails {
        let plan = try await makeDownloadPlan(for: item)
        return WebDAVItemDetails(
            fileCount: plan.files.count,
            folderCount: max(0, plan.directories.count - (item.isDirectory ? 1 : 0)),
            totalSize: plan.files.reduce(0) { $0 + max($1.item.contentLength ?? 0, 0) },
            unknownSizeFileCount: plan.files.filter { $0.item.contentLength == nil }.count
        )
    }

    func delete(item: WebDAVItem) async throws {
        let url = try remoteURL(for: item.path, isCollection: item.isDirectory)
        let request = makeRequest(url: url, method: "DELETE")
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
    }

    func replace(localURL: URL, item: WebDAVItem, force: Bool = false) async throws {
        guard !item.isDirectory, fileManager.fileExists(atPath: localURL.path) else {
            throw WebDAVError.localFileMissing
        }
        let url = try remoteURL(for: item.path)
        var request = makeRequest(url: url, method: "PUT")
        if !force, let etag = item.etag, !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-Match")
        }
        let (data, response) = try await session.upload(for: request, fromFile: localURL)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebDAVError.invalidResponse
        }
        if httpResponse.statusCode == 412 {
            throw WebDAVError.editConflict
        }
        try validate(response: response, data: data)
    }

    func download(
        item: WebDAVItem,
        into localDirectory: URL,
        progress: @escaping (WebDAVTransferProgress) -> Void
    ) async throws -> URL {
        try fileManager.createDirectory(at: localDirectory, withIntermediateDirectories: true)
        let plan = try await makeDownloadPlan(for: item)
        let stagingRoot = fileManager.temporaryDirectory
            .appendingPathComponent("EasySearchWebDAVDownloads", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let rootName = WebDAVLocalFileStore.sanitizedFileName(item.name)
        let stagedRoot = stagingRoot.appendingPathComponent(rootName, isDirectory: item.isDirectory)

        do {
            try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
            for directory in plan.directories {
                let target = stagingRoot.appendingPathComponent(
                    directory.relativePath,
                    isDirectory: true
                )
                try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            }

            var completedBytes: Int64 = 0
            var completedFiles = 0
            reportProgress(
                completedBytes: 0,
                totalBytes: plan.totalBytes,
                completedFiles: 0,
                totalFiles: plan.files.count,
                progress: progress
            )

            for file in plan.files {
                try Task.checkCancellation()
                let target = stagingRoot.appendingPathComponent(file.relativePath, isDirectory: false)
                try fileManager.createDirectory(
                    at: target.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let output = try await downloadFile(path: file.item.path) { written, _ in
                    self.reportProgress(
                        completedBytes: completedBytes + written,
                        totalBytes: plan.totalBytes,
                        completedFiles: completedFiles,
                        totalFiles: plan.files.count,
                        progress: progress
                    )
                }
                do {
                    try Task.checkCancellation()
                    try fileManager.moveItem(at: output.localURL, to: target)
                } catch {
                    try? fileManager.removeItem(at: output.localURL)
                    throw error
                }
                completedBytes += output.bytesWritten
                completedFiles += 1
                reportProgress(
                    completedBytes: completedBytes,
                    totalBytes: plan.totalBytes,
                    completedFiles: completedFiles,
                    totalFiles: plan.files.count,
                    progress: progress
                )
            }

            try Task.checkCancellation()
            let finalTarget = WebDAVLocalFileStore.uniqueURL(
                for: localDirectory.appendingPathComponent(rootName, isDirectory: item.isDirectory)
            )
            try fileManager.moveItem(at: stagedRoot, to: finalTarget)
            try? fileManager.removeItem(at: stagingRoot)
            return finalTarget
        } catch {
            try? fileManager.removeItem(at: stagingRoot)
            throw error
        }
    }

    func downloadForPreview(
        item: WebDAVItem,
        progress: @escaping (WebDAVTransferProgress) -> Void
    ) async throws -> URL {
        guard !item.isDirectory else { throw WebDAVError.invalidURL }
        let previewDirectory = try WebDAVLocalFileStore.makePreviewDirectory()
        let target = previewDirectory.appendingPathComponent(
            WebDAVLocalFileStore.sanitizedFileName(item.name),
            isDirectory: false
        )
        do {
            let output = try await downloadFile(path: item.path) { written, expected in
                let total: Int64?
                if let contentLength = item.contentLength, contentLength > 0 {
                    total = contentLength
                } else if expected > 0 {
                    total = expected
                } else {
                    total = nil
                }
                progress(WebDAVTransferProgress(
                    completedBytes: written,
                    totalBytes: total,
                    completedFiles: 0,
                    totalFiles: 1
                ))
            }
            do {
                try Task.checkCancellation()
                try fileManager.moveItem(at: output.localURL, to: target)
            } catch {
                try? fileManager.removeItem(at: output.localURL)
                throw error
            }
            progress(WebDAVTransferProgress(
                completedBytes: output.bytesWritten,
                totalBytes: item.contentLength.flatMap { $0 > 0 ? $0 : nil } ?? output.bytesWritten,
                completedFiles: 1,
                totalFiles: 1
            ))
            return target
        } catch {
            try? fileManager.removeItem(at: previewDirectory)
            throw error
        }
    }

    private func makeDownloadPlan(for root: WebDAVItem) async throws -> DownloadPlan {
        let rootName = WebDAVLocalFileStore.sanitizedFileName(root.name)
        var pending = [PlannedItem(item: root, relativePath: rootName)]
        var directories: [PlannedItem] = []
        var files: [PlannedItem] = []
        var visitedDirectories = Set<String>()

        while let current = pending.popLast() {
            try Task.checkCancellation()
            if current.item.isDirectory {
                guard visitedDirectories.insert(current.item.path).inserted else { continue }
                directories.append(current)
                let children = try await list(path: current.item.path)
                var usedNames = Set<String>()
                let plannedChildren = children.map { child -> PlannedItem in
                    let component = uniqueLocalName(
                        WebDAVLocalFileStore.sanitizedFileName(child.name),
                        isDirectory: child.isDirectory,
                        usedNames: &usedNames
                    )
                    return PlannedItem(
                        item: child,
                        relativePath: join(current.relativePath, component)
                    )
                }
                pending.append(contentsOf: plannedChildren.reversed())
            } else {
                files.append(current)
            }
        }

        let hasUnknownSize = files.contains { ($0.item.contentLength ?? -1) < 0 }
        let totalBytes = hasUnknownSize
            ? nil
            : files.reduce(Int64(0)) { $0 + ($1.item.contentLength ?? 0) }
        return DownloadPlan(directories: directories, files: files, totalBytes: totalBytes)
    }

    private func uniqueLocalName(
        _ requestedName: String,
        isDirectory: Bool,
        usedNames: inout Set<String>
    ) -> String {
        guard usedNames.contains(requestedName) else {
            usedNames.insert(requestedName)
            return requestedName
        }
        let source = requestedName as NSString
        let ext = isDirectory ? "" : source.pathExtension
        let stem = ext.isEmpty ? requestedName : source.deletingPathExtension
        var index = 2
        while true {
            let candidate = ext.isEmpty ? "\(stem) (\(index))" : "\(stem) (\(index)).\(ext)"
            if usedNames.insert(candidate).inserted { return candidate }
            index += 1
        }
    }

    private func reportProgress(
        completedBytes: Int64,
        totalBytes: Int64?,
        completedFiles: Int,
        totalFiles: Int,
        progress: (WebDAVTransferProgress) -> Void
    ) {
        progress(WebDAVTransferProgress(
            completedBytes: max(completedBytes, 0),
            totalBytes: totalBytes,
            completedFiles: completedFiles,
            totalFiles: totalFiles
        ))
    }

    private func downloadFile(
        path: String,
        progress: @escaping (Int64, Int64) -> Void
    ) async throws -> WebDAVProgressDownloadOperation.Output {
        let url = try remoteURL(for: path)
        let request = makeRequest(url: url, method: "GET")
        return try await WebDAVProgressDownloadOperation(progress: progress).run(request: request)
    }

    private func makeRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 60
        if !configuration.username.isEmpty {
            let credentials = "\(configuration.username):\(configuration.password)"
            request.setValue("Basic \(Data(credentials.utf8).base64EncodedString())", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func uploadFile(localURL: URL, requestedPath: String) async throws {
        for attempt in 1...1_000 {
            let candidatePath = uniqueRemotePath(requestedPath, attempt: attempt, isDirectory: false)
            let url = try remoteURL(for: candidatePath)
            var request = makeRequest(url: url, method: "PUT")
            request.setValue("*", forHTTPHeaderField: "If-None-Match")
            let (data, response) = try await session.upload(for: request, fromFile: localURL)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw WebDAVError.invalidResponse
            }
            if httpResponse.statusCode == 412 { continue }
            try validate(response: response, data: data)
            return
        }
        throw WebDAVError.tooManyNameConflicts
    }

    private func createUniqueDirectory(requestedPath: String) async throws -> String {
        for attempt in 1...1_000 {
            let candidatePath = uniqueRemotePath(requestedPath, attempt: attempt, isDirectory: true)
            let url = try remoteURL(for: candidatePath, isCollection: true)
            let request = makeRequest(url: url, method: "MKCOL")
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw WebDAVError.invalidResponse
            }
            if (200..<300).contains(httpResponse.statusCode) {
                return candidatePath
            }
            if httpResponse.statusCode == 405 {
                let existingItems = try await list(path: parentPath(of: candidatePath))
                if existingItems.contains(where: { $0.path == candidatePath }) {
                    continue
                }
            }
            try validate(response: response, data: data)
        }
        throw WebDAVError.tooManyNameConflicts
    }

    private func uniqueRemotePath(_ requestedPath: String, attempt: Int, isDirectory: Bool) -> String {
        guard attempt > 1 else { return requestedPath }
        let parent = parentPath(of: requestedPath)
        let name = requestedPath.split(separator: "/").last.map(String.init) ?? "未命名文件"
        let renamed: String
        if isDirectory {
            renamed = "\(name) (\(attempt))"
        } else {
            let fileName = name as NSString
            let ext = fileName.pathExtension
            let stem = fileName.deletingPathExtension
            renamed = ext.isEmpty ? "\(stem) (\(attempt))" : "\(stem) (\(attempt)).\(ext)"
        }
        return join(parent, renamed)
    }

    private func parentPath(of path: String) -> String {
        let parts = path.split(separator: "/")
        guard parts.count > 1 else { return "" }
        return parts.dropLast().joined(separator: "/")
    }

    private func validate(
        response: URLResponse,
        data: Data?,
        accepted: [Int] = []
    ) throws {
        guard let httpResponse = response as? HTTPURLResponse else { throw WebDAVError.invalidResponse }
        let isAccepted = accepted.isEmpty
            ? (200..<300).contains(httpResponse.statusCode)
            : accepted.contains(httpResponse.statusCode)
        guard isAccepted else {
            let message: String
            if let data, let body = String(data: data, encoding: .utf8) {
                message = body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160).description
            } else {
                message = ""
            }
            throw WebDAVError.server(statusCode: httpResponse.statusCode, message: message)
        }
    }

    private func remoteURL(for path: String, isCollection: Bool = false) throws -> URL {
        guard configuration.isValid,
              var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false) else {
            throw WebDAVError.invalidConfiguration
        }

        let basePath = components.path.hasSuffix("/") ? components.path : components.path + "/"
        let segments = path.split(separator: "/").map(String.init)
        guard !segments.contains(where: { $0 == "." || $0 == ".." }) else {
            throw WebDAVError.invalidURL
        }
        var resolvedPath = basePath + segments.joined(separator: "/")
        if isCollection, !resolvedPath.hasSuffix("/") {
            resolvedPath.append("/")
        }
        components.path = resolvedPath
        components.query = nil
        components.fragment = nil
        guard let url = components.url else { throw WebDAVError.invalidURL }
        return url
    }

    private func join(_ lhs: String, _ rhs: String) -> String {
        let left = lhs.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let right = rhs.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if left.isEmpty { return right }
        if right.isEmpty { return left }
        return "\(left)/\(right)"
    }
}

private final class WebDAVProgressDownloadOperation: NSObject, URLSessionDownloadDelegate {
    struct Output {
        let localURL: URL
        let bytesWritten: Int64
    }

    private let progress: (Int64, Int64) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Output, Error>?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var stagedURL: URL?
    private var stagingError: Error?
    private var bytesWritten: Int64 = 0
    private var cancellationRequested = false

    init(progress: @escaping (Int64, Int64) -> Void) {
        self.progress = progress
    }

    func run(request: URLRequest) async throws -> Output {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = 60
                configuration.timeoutIntervalForResource = 24 * 60 * 60
                let queue = OperationQueue()
                queue.maxConcurrentOperationCount = 1
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
                self.session = session
                let task = session.downloadTask(with: request)
                self.lock.lock()
                self.task = task
                let shouldCancel = self.cancellationRequested
                self.lock.unlock()
                if shouldCancel {
                    task.resume()
                    task.cancel()
                } else {
                    task.resume()
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    func cancel() {
        lock.lock()
        cancellationRequested = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        self.bytesWritten = totalBytesWritten
        progress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("EasySearchWebDAVTransport", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let target = directory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.moveItem(at: location, to: target)
            stagedURL = target
            if bytesWritten == 0 {
                let fileSize = try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize
                bytesWritten = Int64(fileSize ?? 0)
            }
        } catch {
            stagingError = error
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        defer {
            self.session?.finishTasksAndInvalidate()
            self.session = nil
            self.task = nil
        }
        guard let continuation else { return }
        self.continuation = nil

        if let error {
            if let stagedURL { try? FileManager.default.removeItem(at: stagedURL) }
            continuation.resume(throwing: error)
            return
        }
        if let stagingError {
            if let stagedURL { try? FileManager.default.removeItem(at: stagedURL) }
            continuation.resume(throwing: stagingError)
            return
        }
        guard let response = task.response as? HTTPURLResponse else {
            continuation.resume(throwing: WebDAVError.invalidResponse)
            return
        }
        guard (200..<300).contains(response.statusCode) else {
            if let stagedURL { try? FileManager.default.removeItem(at: stagedURL) }
            continuation.resume(throwing: WebDAVError.server(statusCode: response.statusCode, message: ""))
            return
        }
        guard let stagedURL else {
            continuation.resume(throwing: WebDAVError.invalidResponse)
            return
        }
        continuation.resume(returning: Output(localURL: stagedURL, bytesWritten: bytesWritten))
    }
}

final class WebDAVListingParser: NSObject, XMLParserDelegate {
    private let baseURL: URL
    private let requestedPath: String
    private var currentResponse: ParsedResponse?
    private var text = ""
    private var parsedResponses: [ParsedResponse] = []
    private(set) var hasParseError = false

    init(baseURL: URL, requestedPath: String) {
        self.baseURL = baseURL
        self.requestedPath = requestedPath
    }

    func parse(_ data: Data) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        if !parser.parse() { hasParseError = true }
    }

    var items: [WebDAVItem] {
        let requested = normalize(requestedPath)
        return parsedResponses.compactMap { response in
            guard !response.sawStatus || response.hasSuccessfulStatus else { return nil }
            guard let path = path(from: response.href) else { return nil }
            guard !path.isEmpty || !requested.isEmpty, path != requested else { return nil }
            let parentPath = path.split(separator: "/").dropLast().joined(separator: "/")
            guard parentPath == requested else { return nil }
            let fallbackName = path.split(separator: "/").last.map(String.init) ?? response.href
            return WebDAVItem(
                path: path,
                name: fallbackName,
                kind: response.isDirectory ? .directory : .file,
                contentLength: response.contentLength,
                modifiedAt: response.modifiedAt,
                contentType: response.contentType,
                etag: response.etag
            )
        }
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = localName(elementName)
        text = ""
        if name == "response" {
            currentResponse = ParsedResponse()
        } else if name == "collection", currentResponse != nil {
            currentResponse?.isDirectory = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text.append(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = localName(elementName)
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if var response = currentResponse {
            switch name {
            case "href":
                response.href = value
            case "getcontentlength":
                response.contentLength = Int64(value)
            case "getlastmodified":
                response.modifiedAt = Self.dateFormatter.date(from: value)
            case "getcontenttype":
                response.contentType = value.isEmpty ? nil : value
            case "getetag":
                response.etag = value.isEmpty ? nil : value
            case "status":
                response.sawStatus = true
                if value.contains(" 200 ") || value.hasSuffix(" 200") {
                    response.hasSuccessfulStatus = true
                }
            case "response":
                if !response.href.isEmpty { parsedResponses.append(response) }
                currentResponse = nil
            default:
                break
            }
            if name != "response" {
                currentResponse = response
            }
        }
        text = ""
    }

    private func path(from href: String) -> String? {
        guard let hrefURL = URL(string: href, relativeTo: baseURL)?.absoluteURL else {
            return nil
        }
        let basePath = normalize(baseURL.path)
        let responsePath = normalize(hrefURL.path)
        if responsePath == basePath { return "" }
        if basePath.isEmpty { return responsePath }
        if responsePath.hasPrefix(basePath + "/") {
            return String(responsePath.dropFirst(basePath.count + 1))
        }
        return nil
    }

    private func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func localName(_ value: String) -> String {
        value.split(separator: ":").last.map(String.init) ?? value
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()
}

private struct ParsedResponse {
    var href = ""
    var isDirectory = false
    var contentLength: Int64?
    var modifiedAt: Date?
    var contentType: String?
    var etag: String?
    var sawStatus = false
    var hasSuccessfulStatus = false
}
