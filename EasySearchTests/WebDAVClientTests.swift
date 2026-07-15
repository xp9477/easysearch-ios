import Foundation
import Security
import XCTest
@testable import EasySearch

final class WebDAVClientTests: XCTestCase {
    override func tearDown() {
        WebDAVURLProtocolStub.reset()
        super.tearDown()
    }

    func testListingParserExcludesRequestedDirectoryAndRejectsOutsideBasePath() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <d:multistatus xmlns:d="DAV:">
          <d:response>
            <d:href>/remote.php/dav/files/me/</d:href>
            <d:propstat><d:prop><d:resourcetype><d:collection /></d:resourcetype></d:prop></d:propstat>
          </d:response>
          <d:response>
            <d:href>/remote.php/dav/files/me/Folder%20One/</d:href>
            <d:propstat><d:prop><d:resourcetype><d:collection /></d:resourcetype></d:prop></d:propstat>
          </d:response>
          <d:response>
            <d:href>/remote.php/dav/files/other/private.txt</d:href>
            <d:propstat><d:prop><d:resourcetype /></d:prop></d:propstat>
          </d:response>
        </d:multistatus>
        """
        let parser = WebDAVListingParser(
            baseURL: try XCTUnwrap(URL(string: "https://dav.example.com/remote.php/dav/files/me/")),
            requestedPath: ""
        )

        parser.parse(Data(xml.utf8))

        XCTAssertFalse(parser.hasParseError)
        XCTAssertEqual(parser.items.count, 1)
        XCTAssertEqual(parser.items.first?.path, "Folder One")
        XCTAssertEqual(parser.items.first?.name, "Folder One")
        XCTAssertEqual(parser.items.first?.kind, .directory)
    }

    func testListingParserReadsUnicodeFileMetadata() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <d:multistatus xmlns:d="DAV:">
          <d:response>
            <d:href>/dav/%E8%B5%84%E6%96%99/report.pdf</d:href>
            <d:propstat>
              <d:prop>
                <d:resourcetype />
                <d:getcontentlength>1024</d:getcontentlength>
                <d:getlastmodified>Mon, 13 Jul 2026 08:00:00 GMT</d:getlastmodified>
                <d:getcontenttype>application/pdf</d:getcontenttype>
                <d:getetag>&quot;version-1&quot;</d:getetag>
              </d:prop>
            </d:propstat>
          </d:response>
        </d:multistatus>
        """
        let parser = WebDAVListingParser(
            baseURL: try XCTUnwrap(URL(string: "https://dav.example.com/dav/")),
            requestedPath: "资料"
        )

        parser.parse(Data(xml.utf8))

        let item = try XCTUnwrap(parser.items.first)
        XCTAssertEqual(item.path, "资料/report.pdf")
        XCTAssertEqual(item.name, "report.pdf")
        XCTAssertEqual(item.kind, .file)
        XCTAssertEqual(item.contentLength, 1024)
        XCTAssertNotNil(item.modifiedAt)
        XCTAssertEqual(item.contentType, "application/pdf")
        XCTAssertEqual(item.etag, "\"version-1\"")
    }

    func testSanitizedFileNameBlocksTraversalComponents() {
        XCTAssertEqual(WebDAVLocalFileStore.sanitizedFileName(".."), "未命名文件")
        XCTAssertEqual(WebDAVLocalFileStore.sanitizedFileName("a/b\\c.txt"), "a_b_c.txt")
        XCTAssertEqual(WebDAVLocalFileStore.sanitizedFileName(" report.pdf "), "report.pdf")
    }

    func testHiddenFolderRecognitionDoesNotHideDotFiles() {
        let folder = WebDAVItem(
            path: ".archive",
            name: ".archive",
            kind: .directory,
            contentLength: nil,
            modifiedAt: nil
        )
        let file = WebDAVItem(
            path: ".env",
            name: ".env",
            kind: .file,
            contentLength: 10,
            modifiedAt: nil
        )

        XCTAssertTrue(folder.isHiddenFolder)
        XCTAssertFalse(file.isHiddenFolder)
    }

    func testListingParserPreservesLiteralPercentEscapeInFileName() throws {
        let xml = """
        <d:multistatus xmlns:d="DAV:">
          <d:response>
            <d:href>/dav/literal%2520name.txt</d:href>
            <d:propstat><d:prop><d:resourcetype /></d:prop></d:propstat>
          </d:response>
        </d:multistatus>
        """
        let parser = WebDAVListingParser(
            baseURL: try XCTUnwrap(URL(string: "https://dav.example.com/dav/")),
            requestedPath: ""
        )

        parser.parse(Data(xml.utf8))

        XCTAssertEqual(parser.items.first?.path, "literal%20name.txt")
        XCTAssertEqual(parser.items.first?.name, "literal%20name.txt")
    }

    func testListingParserIgnoresResponseWithoutSuccessfulStatus() throws {
        let xml = """
        <d:multistatus xmlns:d="DAV:">
          <d:response>
            <d:href>/dav/missing.txt</d:href>
            <d:propstat>
              <d:prop><d:resourcetype /></d:prop>
              <d:status>HTTP/1.1 404 Not Found</d:status>
            </d:propstat>
          </d:response>
        </d:multistatus>
        """
        let parser = WebDAVListingParser(
            baseURL: try XCTUnwrap(URL(string: "https://dav.example.com/dav/")),
            requestedPath: ""
        )

        parser.parse(Data(xml.utf8))

        XCTAssertTrue(parser.items.isEmpty)
    }

    func testListSendsDepthOnePropfindToCollectionURL() async throws {
        let xml = """
        <d:multistatus xmlns:d="DAV:">
          <d:response><d:href>/dav/folder/</d:href><d:propstat><d:prop><d:resourcetype><d:collection /></d:resourcetype></d:prop></d:propstat></d:response>
        </d:multistatus>
        """
        WebDAVURLProtocolStub.setHandler { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 207,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/xml"]
            ))
            return (response, Data(xml.utf8))
        }
        let client = makeClient()

        _ = try await client.list(path: "folder")

        let request = try XCTUnwrap(WebDAVURLProtocolStub.requests.first)
        XCTAssertEqual(request.httpMethod, "PROPFIND")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Depth"), "1")
        XCTAssertEqual(request.url?.path, "/dav/folder/")
    }

    func testUploadKeepsBothWhenRemoteFileAlreadyExists() async throws {
        WebDAVURLProtocolStub.setHandler { request in
            let statusCode = request.url?.lastPathComponent == "report.txt" ? 412 : 201
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data())
        }
        let localURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("webdav-upload-\(UUID().uuidString).txt")
        try Data("test".utf8).write(to: localURL)
        defer { try? FileManager.default.removeItem(at: localURL) }

        try await makeClient().upload(localURL: localURL, remotePath: "report.txt")

        let requests = WebDAVURLProtocolStub.requests
        XCTAssertEqual(requests.map(\.httpMethod), ["PUT", "PUT"])
        XCTAssertEqual(requests.map { $0.url?.lastPathComponent }, ["report.txt", "report (2).txt"])
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "If-None-Match") == "*" })
    }

    func testDetailsRecursivelyCountsFilesFoldersAndKnownSize() async throws {
        WebDAVURLProtocolStub.setHandler { request in
            let path = try XCTUnwrap(request.url?.path)
            let body: String
            switch path {
            case "/dav/folder/":
                body = """
                <d:multistatus xmlns:d="DAV:">
                  <d:response><d:href>/dav/folder/</d:href><d:propstat><d:prop><d:resourcetype><d:collection /></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
                  <d:response><d:href>/dav/folder/a.txt</d:href><d:propstat><d:prop><d:resourcetype /><d:getcontentlength>5</d:getcontentlength></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
                  <d:response><d:href>/dav/folder/nested/</d:href><d:propstat><d:prop><d:resourcetype><d:collection /></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
                </d:multistatus>
                """
            case "/dav/folder/nested/":
                body = """
                <d:multistatus xmlns:d="DAV:">
                  <d:response><d:href>/dav/folder/nested/</d:href><d:propstat><d:prop><d:resourcetype><d:collection /></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
                  <d:response><d:href>/dav/folder/nested/b.txt</d:href><d:propstat><d:prop><d:resourcetype /><d:getcontentlength>7</d:getcontentlength></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
                </d:multistatus>
                """
            default:
                XCTFail("Unexpected path: \(path)")
                body = "<d:multistatus xmlns:d=\"DAV:\" />"
            }
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 207,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data(body.utf8))
        }

        let details = try await makeClient().details(for: WebDAVItem(
            path: "folder",
            name: "folder",
            kind: .directory,
            contentLength: nil,
            modifiedAt: nil
        ))

        XCTAssertEqual(details.fileCount, 2)
        XCTAssertEqual(details.folderCount, 1)
        XCTAssertEqual(details.totalSize, 12)
        XCTAssertEqual(details.unknownSizeFileCount, 0)
    }

    func testDeleteDirectoryUsesCollectionURL() async throws {
        WebDAVURLProtocolStub.setHandler { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 204,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data())
        }

        try await makeClient().delete(item: WebDAVItem(
            path: "folder",
            name: "folder",
            kind: .directory,
            contentLength: nil,
            modifiedAt: nil
        ))

        let request = try XCTUnwrap(WebDAVURLProtocolStub.requests.first)
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.path, "/dav/folder/")
    }

    func testReplaceUsesOriginalPathAndETag() async throws {
        WebDAVURLProtocolStub.setHandler { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 204,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data())
        }
        let localURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("webdav-edit-\(UUID().uuidString).txt")
        try Data("edited".utf8).write(to: localURL)
        defer { try? FileManager.default.removeItem(at: localURL) }

        try await makeClient().replace(
            localURL: localURL,
            item: WebDAVItem(
                path: "notes/report.txt",
                name: "report.txt",
                kind: .file,
                contentLength: 6,
                modifiedAt: nil,
                etag: "\"version-1\""
            ),
            force: false
        )

        let request = try XCTUnwrap(WebDAVURLProtocolStub.requests.first)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/dav/notes/report.txt")
        XCTAssertEqual(request.value(forHTTPHeaderField: "If-Match"), "\"version-1\"")
    }

    func testReplaceMapsPreconditionFailureToEditConflict() async throws {
        WebDAVURLProtocolStub.setHandler { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 412,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data())
        }
        let localURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("webdav-conflict-\(UUID().uuidString).txt")
        try Data("edited".utf8).write(to: localURL)
        defer { try? FileManager.default.removeItem(at: localURL) }

        do {
            try await makeClient().replace(
                localURL: localURL,
                item: WebDAVItem(
                    path: "report.txt",
                    name: "report.txt",
                    kind: .file,
                    contentLength: 6,
                    modifiedAt: nil,
                    etag: "\"old\""
                ),
                force: false
            )
            XCTFail("Expected edit conflict")
        } catch WebDAVError.editConflict {
            // Expected.
        }
    }

    func testStreamingRequestUsesRangeAuthenticationAndNoCache() throws {
        let item = WebDAVItem(
            path: "videos/demo.mp4",
            name: "demo.mp4",
            kind: .file,
            contentLength: 1_024,
            modifiedAt: nil,
            contentType: "video/mp4"
        )

        let request = try makeClient().makeStreamingRequest(
            for: item,
            rangeHeader: "bytes=128-255"
        )

        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/dav/videos/demo.mp4")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=128-255")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        let expectedCredentials = Data("user:password".utf8).base64EncodedString()
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Basic \(expectedCredentials)"
        )
    }

    private func makeClient() -> WebDAVClient {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [WebDAVURLProtocolStub.self]
        let configuration = WebDAVConfiguration(
            baseURL: URL(string: "https://dav.example.com/dav/")!,
            username: "user",
            password: "password"
        )
        return WebDAVClient(
            configuration: configuration,
            session: URLSession(configuration: sessionConfiguration)
        )
    }
}

@MainActor
final class WebDAVSettingsStoreTests: XCTestCase {
    func testMultipleLocationsPersistSelectionAndSeparatePasswords() throws {
        let context = makeContext()
        defer { context.cleanup() }
        let store = WebDAVSettingsStore(userDefaults: context.defaults, keychain: context.credentials)
        let home = try store.makeLocation(
            name: "Home",
            baseURLString: "https://home.example/dav",
            username: "home-user",
            password: "home-password"
        ).get()
        let work = try store.makeLocation(
            name: "Work",
            baseURLString: "https://work.example/dav",
            username: "work-user",
            password: "work-password"
        ).get()

        try store.save(location: home).get()
        try store.save(location: work).get()
        store.select(locationID: home.id)

        XCTAssertEqual(store.locations.count, 2)
        XCTAssertEqual(store.selectedLocationID, home.id)
        XCTAssertEqual(try context.credentials.readPassword(locationID: home.id), "home-password")
        XCTAssertEqual(try context.credentials.readPassword(locationID: work.id), "work-password")

        let reloaded = WebDAVSettingsStore(userDefaults: context.defaults, keychain: context.credentials)
        XCTAssertEqual(reloaded.selectedLocationID, home.id)
        XCTAssertEqual(reloaded.location(withID: work.id)?.password, "work-password")
    }

    func testRemovingLocationKeepsOtherCredentials() throws {
        let context = makeContext()
        defer { context.cleanup() }
        let store = WebDAVSettingsStore(userDefaults: context.defaults, keychain: context.credentials)
        let first = try store.makeLocation(
            name: "One",
            baseURLString: "https://one.example/dav",
            username: "",
            password: "one"
        ).get()
        let second = try store.makeLocation(
            name: "Two",
            baseURLString: "https://two.example/dav",
            username: "",
            password: "two"
        ).get()
        try store.save(location: first).get()
        try store.save(location: second).get()

        store.remove(locationID: first.id)

        XCTAssertNil(store.location(withID: first.id))
        XCTAssertThrowsError(try context.credentials.readPassword(locationID: first.id))
        XCTAssertEqual(try context.credentials.readPassword(locationID: second.id), "two")
    }

    func testHiddenFolderPreferencePersists() {
        let context = makeContext()
        defer { context.cleanup() }
        let store = WebDAVSettingsStore(userDefaults: context.defaults, keychain: context.credentials)

        store.setShowsHiddenFolders(true)

        let reloaded = WebDAVSettingsStore(userDefaults: context.defaults, keychain: context.credentials)
        XCTAssertTrue(reloaded.showsHiddenFolders)
    }

    func testLegacyConfigurationMigratesToLocation() throws {
        let context = makeContext()
        defer { context.cleanup() }
        context.defaults.set("https://legacy.example/dav", forKey: "webdav.baseURL")
        context.defaults.set("legacy-user", forKey: "webdav.username")
        context.credentials.legacyPassword = "legacy-password"

        let store = WebDAVSettingsStore(userDefaults: context.defaults, keychain: context.credentials)

        let location = try XCTUnwrap(store.locations.first)
        XCTAssertEqual(store.locations.count, 1)
        XCTAssertEqual(location.name, "legacy.example")
        XCTAssertEqual(location.username, "legacy-user")
        XCTAssertEqual(location.password, "legacy-password")
        XCTAssertNil(context.defaults.string(forKey: "webdav.baseURL"))
        XCTAssertNil(context.credentials.legacyPassword)
        XCTAssertEqual(try context.credentials.readPassword(locationID: location.id), "legacy-password")
    }

    private func makeContext() -> WebDAVSettingsTestContext {
        let suiteName = "WebDAVSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return WebDAVSettingsTestContext(
            suiteName: suiteName,
            defaults: defaults,
            credentials: InMemoryWebDAVCredentials()
        )
    }
}

private struct WebDAVSettingsTestContext {
    let suiteName: String
    let defaults: UserDefaults
    let credentials: InMemoryWebDAVCredentials

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private final class InMemoryWebDAVCredentials: WebDAVCredentialStoring {
    var legacyPassword: String?
    private var passwords: [UUID: String] = [:]

    func save(password: String, locationID: UUID) throws {
        passwords[locationID] = password
    }

    func readPassword(locationID: UUID) throws -> String {
        guard let password = passwords[locationID] else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(errSecItemNotFound))
        }
        return password
    }

    func deletePassword(locationID: UUID) throws {
        passwords.removeValue(forKey: locationID)
    }

    func readLegacyPassword() throws -> String {
        guard let legacyPassword else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(errSecItemNotFound))
        }
        return legacyPassword
    }

    func deleteLegacyPassword() throws {
        legacyPassword = nil
    }
}

private final class WebDAVURLProtocolStub: URLProtocol {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    private static var handler: Handler?
    private static var capturedRequests: [URLRequest] = []

    static var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequests
    }

    static func setHandler(_ handler: @escaping Handler) {
        lock.lock()
        self.handler = handler
        capturedRequests = []
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        handler = nil
        capturedRequests = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.capturedRequests.append(request)
        let handler = Self.handler
        Self.lock.unlock()

        do {
            guard let handler else { throw URLError(.badServerResponse) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
