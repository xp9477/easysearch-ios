import Foundation
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
    }

    func testSanitizedFileNameBlocksTraversalComponents() {
        XCTAssertEqual(WebDAVLocalFileStore.sanitizedFileName(".."), "未命名文件")
        XCTAssertEqual(WebDAVLocalFileStore.sanitizedFileName("a/b\\c.txt"), "a_b_c.txt")
        XCTAssertEqual(WebDAVLocalFileStore.sanitizedFileName(" report.pdf "), "report.pdf")
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
