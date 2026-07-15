import Foundation

protocol WebDAVClientProtocol {
    func list(path: String) async throws -> [WebDAVItem]
    func createDirectory(path: String) async throws
    func upload(localURL: URL, remotePath: String) async throws
    func download(item: WebDAVItem, into localDirectory: URL) async throws -> URL
}

final class WebDAVClient: WebDAVClientProtocol {
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
                let childPath = join(createdPath, child.lastPathComponent)
                try await upload(localURL: child, remotePath: childPath)
            }
            return
        }

        try await uploadFile(localURL: localURL, requestedPath: remotePath)
    }

    func download(item: WebDAVItem, into localDirectory: URL) async throws -> URL {
        try fileManager.createDirectory(at: localDirectory, withIntermediateDirectories: true)
        if item.isDirectory {
            let stagingRoot = fileManager.temporaryDirectory
                .appendingPathComponent("EasySearchWebDAVDownloads", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let stagingTarget = stagingRoot.appendingPathComponent(
                WebDAVLocalFileStore.sanitizedFileName(item.name),
                isDirectory: true
            )
            do {
                try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
                try await downloadRecursively(item: item, to: stagingTarget)
                let finalTarget = WebDAVLocalFileStore.uniqueURL(
                    for: localDirectory.appendingPathComponent(
                        WebDAVLocalFileStore.sanitizedFileName(item.name),
                        isDirectory: true
                    )
                )
                try fileManager.moveItem(at: stagingTarget, to: finalTarget)
                try? fileManager.removeItem(at: stagingRoot)
                return finalTarget
            } catch {
                try? fileManager.removeItem(at: stagingRoot)
                throw error
            }
        }

        let target = WebDAVLocalFileStore.uniqueURL(
            for: localDirectory.appendingPathComponent(
                WebDAVLocalFileStore.sanitizedFileName(item.name),
                isDirectory: false
            )
        )
        try await downloadFile(path: item.path, to: target)
        return target
    }

    private func downloadRecursively(item: WebDAVItem, to target: URL) async throws {
        if !item.isDirectory {
            try await downloadFile(path: item.path, to: target)
            return
        }

        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        let children = try await list(path: item.path)
        for child in children {
            let childTarget = WebDAVLocalFileStore.uniqueURL(
                for: target.appendingPathComponent(
                    WebDAVLocalFileStore.sanitizedFileName(child.name),
                    isDirectory: child.isDirectory
                )
            )
            try await downloadRecursively(item: child, to: childTarget)
        }
    }

    private func downloadFile(path: String, to target: URL) async throws {
        let url = try remoteURL(for: path)
        let request = makeRequest(url: url, method: "GET")
        let (temporaryURL, response) = try await session.download(for: request)
        try validate(response: response, data: nil)
        try fileManager.moveItem(at: temporaryURL, to: target)
    }

    private func makeRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 60
        if !configuration.username.isEmpty {
            let credentials = "\(configuration.username):\(configuration.password)"
            let encoded = Data(credentials.utf8).base64EncodedString()
            request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
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
                let parent = parentPath(of: candidatePath)
                let existingItems = try await list(path: parent)
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

final class WebDAVListingParser: NSObject, XMLParserDelegate {
    private let baseURL: URL
    private let requestedPath: String
    private var currentResponse: ParsedResponse?
    private var currentElement = ""
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
                modifiedAt: response.modifiedAt
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
        currentElement = name
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
        currentElement = ""
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
    var sawStatus = false
    var hasSuccessfulStatus = false
}
