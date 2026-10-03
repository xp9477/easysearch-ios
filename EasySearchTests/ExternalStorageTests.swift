import Foundation
import XCTest
@testable import EasySearch

final class ExternalStorageTests: XCTestCase {
    override func tearDown() {
        ExternalStorageURLProtocolStub.reset()
        super.tearDown()
    }

    // MARK: - 1. SMB Configuration Validation & Inline Credential Rejection

    @MainActor
    func testSMBConfigurationValidation() {
        let store = WebDAVSettingsStore()

        // Valid SMB URLs
        let validCases = [
            "smb://192.168.1.100/data",
            "smb://192.168.1.100/data/",
            "smb://nas.local/share/folder",
            "smb://nas.local:445/share/docs",
            "smb://fileserver/media/2026/photos"
        ]

        for validURL in validCases {
            let result = store.makeLocation(
                name: "Test NAS",
                baseURLString: validURL,
                username: "user",
                password: "pw"
            )
            switch result {
            case let .success(location):
                XCTAssertTrue(location.isSMB, "Expected \(validURL) to be identified as SMB")
                XCTAssertTrue(location.configuration.isSMB)
                XCTAssertFalse(location.configuration.isWebDAV)
                XCTAssertTrue(location.configuration.isValid, "Expected configuration to be valid for \(validURL)")
            case let .failure(error):
                XCTFail("Failed to make location for \(validURL): \(error)")
            }
        }

        // Invalid SMB URLs (missing share, missing host, unsupported scheme, or inline credentials)
        let invalidCases = [
            "smb://192.168.1.100",                     // Missing share component
            "smb://192.168.1.100/",                    // Missing share component
            "smb:///data",                             // Missing host
            "smb://",                                  // Empty
            "ftp://192.168.1.100/data",                // Unsupported scheme
            "smb://192.168.1.100:445",                  // Missing share component
            "smb://user:pass@192.168.1.100/data",      // Inline credentials must be rejected to prevent cleartext in UserDefaults
            "https://user:pass@dav.example.com/files/" // Inline credentials in WebDAV must also be rejected
        ]

        for invalidURL in invalidCases {
            let result = store.makeLocation(
                name: "Invalid",
                baseURLString: invalidURL,
                username: "",
                password: ""
            )
            switch result {
            case .success(let loc):
                XCTAssertFalse(loc.configuration.isValid, "Expected configuration to be invalid for \(invalidURL)")
            case .failure:
                // Expected failure
                break
            }
        }
    }

    // MARK: - 2. Unicode Path & Traversal Attack Prevention

    func testUnicodePathSanitizationAndTraversalPrevention() throws {
        // Safe filename cleaning: must not contain path separators that would escape current directory
        let dirtyFileName = "../../etc/passwd"
        let sanitized = WebDAVLocalFileStore.sanitizedFileName(dirtyFileName)
        XCTAssertFalse(sanitized.contains("/"), "Sanitized filename must not contain '/'")
        XCTAssertFalse(sanitized.contains("\\"), "Sanitized filename must not contain '\\'")

        // Unicode file names must be preserved correctly
        let unicodeName = "周杰伦 - 晴天 🎵 (2026).flac"
        XCTAssertEqual(WebDAVLocalFileStore.sanitizedFileName(unicodeName), unicodeName)

        // Traversal rejection in destinationURL: must stay strictly within rootURL
        let destURL = WebDAVLocalFileStore.destinationURL(for: "../../../sensitive/data.txt")
        let rootPath = WebDAVLocalFileStore.rootURL.path
        XCTAssertTrue(destURL.path.hasPrefix(rootPath), "Destination URL must remain within rootURL sandbox")

        // Traversal rejection in SMBStorageClient
        let smbConfig = WebDAVConfiguration(
            baseURL: try XCTUnwrap(URL(string: "smb://192.168.1.1/share/sub")),
            username: "u",
            password: "p"
        )
        let smbClient = SMBStorageClient(configuration: smbConfig)

        XCTAssertThrowsError(try smbClient.resolveSMBPath(baseFolder: "sub", relativePath: "../secret.txt")) { error in
            guard case WebDAVError.invalidURL = error else {
                XCTFail("Expected invalidURL, got \(error)")
                return
            }
        }
        XCTAssertThrowsError(try smbClient.resolveSMBPath(baseFolder: "sub", relativePath: "a/../../b")) { error in
            guard case WebDAVError.invalidURL = error else {
                XCTFail("Expected invalidURL, got \(error)")
                return
            }
        }

        // Valid Unicode SMB Path
        let resolved = try smbClient.resolveSMBPath(baseFolder: "sub", relativePath: "工作资料/2026报告.pdf")
        XCTAssertEqual(resolved, "sub/工作资料/2026报告.pdf")
    }

    // MARK: - 3. MOVE HTTP Request & Conflict Handling

    func testWebDAVMoveHTTPRequestAndConflictHandling() async throws {
        let baseURL = try XCTUnwrap(URL(string: "https://dav.example.com/files/"))
        let configuration = WebDAVConfiguration(baseURL: baseURL, username: "user", password: "pwd")
        let session = makeTestSession()
        let client = WebDAVClient(configuration: configuration, session: session)

        let sourceItem = WebDAVItem(
            path: "docs/report.pdf",
            name: "report.pdf",
            kind: .file,
            contentLength: 1024,
            modifiedAt: Date()
        )

        // 1. Verify successful MOVE sends correct headers (MOVE, Destination, Overwrite: F)
        ExternalStorageURLProtocolStub.setHandler { request in
            XCTAssertEqual(request.httpMethod, "MOVE")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Overwrite"), "F")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Destination"),
                "https://dav.example.com/files/archive/report.pdf"
            )
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 201,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        try await client.move(item: sourceItem, to: "archive/report.pdf")

        // 2. Verify 412 status is caught and mapped to destinationExists
        ExternalStorageURLProtocolStub.setHandler { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 412,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        do {
            try await client.move(item: sourceItem, to: "archive/report.pdf")
            XCTFail("Expected conflict error")
        } catch WebDAVError.destinationExists {
            // Expected!
        } catch {
            XCTFail("Expected destinationExists, got \(error)")
        }

        // 3. Verify directory self/descendant validation
        let folderItem = WebDAVItem(
            path: "parent",
            name: "parent",
            kind: .directory,
            contentLength: nil,
            modifiedAt: Date()
        )

        do {
            try await client.move(item: folderItem, to: "parent/child")
            XCTFail("Expected destinationIsDescendant")
        } catch WebDAVError.destinationIsDescendant {
            // Expected!
        } catch {
            XCTFail("Expected destinationIsDescendant, got \(error)")
        }

        do {
            try await client.move(item: folderItem, to: "parent")
            // Same path is a no-op, shouldn't throw error
        } catch {
            XCTFail("Moving to same path should be no-op, got \(error)")
        }
    }

    // MARK: - 4. uploadExact without Auto-Rename on Conflict

    func testUploadExactDoesNotAutoRenameOnConflict() async throws {
        let baseURL = try XCTUnwrap(URL(string: "https://dav.example.com/files/"))
        let configuration = WebDAVConfiguration(baseURL: baseURL, username: "user", password: "pwd")
        let session = makeTestSession()
        let client = WebDAVClient(configuration: configuration, session: session)

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try "test data".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        var requestCount = 0
        ExternalStorageURLProtocolStub.setHandler { request in
            requestCount += 1
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "*")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 412,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        do {
            try await client.uploadExact(localURL: tempFile, remotePath: "notes.txt")
            XCTFail("Expected destinationExists error")
        } catch WebDAVError.destinationExists {
            // Success! Must NOT auto-rename and retry
            XCTAssertEqual(requestCount, 1, "uploadExact must not auto-rename or retry on 412")
        } catch {
            XCTFail("Expected destinationExists, got \(error)")
        }
    }

    // MARK: - 5. Cross-Origin Redirection Security

    func testCrossOriginRedirectionRejection() throws {
        let delegate = WebDAVRedirectDelegate(initialURL: URL(string: "https://dav.example.com:443/files/"))
        let session = URLSession.shared
        let dummyTask = session.dataTask(with: URL(string: "https://dav.example.com/files/test")!)

        // 1. Cross-host redirect must be rejected (completionHandler receives nil)
        let crossHostReq = URLRequest(url: URL(string: "https://attacker.com/files/test")!)
        var receivedRequest: URLRequest? = crossHostReq
        delegate.urlSession(
            session,
            task: dummyTask,
            willPerformHTTPRedirection: HTTPURLResponse(url: crossHostReq.url!, statusCode: 302, httpVersion: nil, headerFields: nil)!,
            newRequest: crossHostReq
        ) { req in
            receivedRequest = req
        }
        XCTAssertNil(receivedRequest, "Cross-host redirect must be completely rejected")

        // 2. HTTPS to HTTP downgrade must be rejected
        let downgradeReq = URLRequest(url: URL(string: "http://dav.example.com/files/test")!)
        receivedRequest = downgradeReq
        delegate.urlSession(
            session,
            task: dummyTask,
            willPerformHTTPRedirection: HTTPURLResponse(url: downgradeReq.url!, statusCode: 302, httpVersion: nil, headerFields: nil)!,
            newRequest: downgradeReq
        ) { req in
            receivedRequest = req
        }
        XCTAssertNil(receivedRequest, "HTTPS to HTTP downgrade redirect must be completely rejected")

        // 3. Same-origin redirect is allowed
        let sameOriginReq = URLRequest(url: URL(string: "https://dav.example.com/files/new-path")!)
        receivedRequest = nil
        delegate.urlSession(
            session,
            task: dummyTask,
            willPerformHTTPRedirection: HTTPURLResponse(url: sameOriginReq.url!, statusCode: 302, httpVersion: nil, headerFields: nil)!,
            newRequest: sameOriginReq
        ) { req in
            receivedRequest = req
        }
        XCTAssertNotNil(receivedRequest, "Same-origin redirect must be allowed")
    }

    // MARK: - 6. Legacy Configuration Preservation

    func testLegacyConfigurationPreserved() throws {
        let legacyURL = try XCTUnwrap(URL(string: "https://legacy.example.com/dav/"))
        let config = WebDAVConfiguration(
            locationID: UUID(),
            displayName: "Old WebDAV",
            baseURL: legacyURL,
            username: "olduser",
            password: "oldpassword"
        )

        XCTAssertTrue(config.isWebDAV)
        XCTAssertFalse(config.isSMB)
        XCTAssertTrue(config.isValid)
        XCTAssertEqual(config.displayName, "Old WebDAV")
    }

    private func makeTestSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ExternalStorageURLProtocolStub.self]
        return URLSession(configuration: config)
    }
}

// MARK: - Test URLProtocol Stub

private final class ExternalStorageURLProtocolStub: URLProtocol {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    private static var handler: Handler?

    static func setHandler(_ handler: @escaping Handler) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        handler = nil
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
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
