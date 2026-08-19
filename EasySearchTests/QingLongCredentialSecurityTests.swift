import Foundation
import XCTest
@testable import EasySearch

final class QingLongCredentialSecurityTests: XCTestCase {
    override func tearDown() {
        QingLongDiagnosticURLProtocol.reset()
        super.tearDown()
    }

    func testEndpointNormalizationTreatsOnlyCanonicalEquivalentAddressesAsEqual() throws {
        let normalized = try QingLongEndpoint.normalizedURL(
            from: "  HTTPS://Example.COM:443/qinglong/open///  "
        )
        let equivalent = try QingLongEndpoint.normalizedURL(from: "https://example.com/qinglong")

        XCTAssertEqual(normalized, equivalent)
        XCTAssertEqual(try QingLongEndpoint.identity(for: normalized), "https://example.com/qinglong")
    }

    func testCredentialBindingRejectsChangedEndpoint() throws {
        let original = try QingLongEndpoint.normalizedURL(from: "https://panel.example.com:5700/ql")
        let credentials = QingLongCredentials(
            clientID: "client-id",
            clientSecret: "client-secret",
            endpointIdentity: try QingLongEndpoint.identity(for: original)
        )

        XCTAssertTrue(credentials.isBound(to: original))
        XCTAssertTrue(credentials.isBound(to: try QingLongEndpoint.normalizedURL(from: "https://PANEL.example.com:5700/ql/open/")))
        XCTAssertFalse(credentials.isBound(to: try QingLongEndpoint.normalizedURL(from: "https://attacker.example.com:5700/ql")))
        XCTAssertFalse(credentials.isBound(to: try QingLongEndpoint.normalizedURL(from: "http://panel.example.com:5700/ql")))
        XCTAssertFalse(credentials.isBound(to: try QingLongEndpoint.normalizedURL(from: "https://panel.example.com:5700/other")))
    }

    func testLegacyCredentialJSONFailsClosedWithoutEndpointBinding() throws {
        let legacyData = Data(#"{"clientID":"legacy-id","clientSecret":"legacy-secret"}"#.utf8)
        let credentials = try JSONDecoder().decode(QingLongCredentials.self, from: legacyData)
        let endpoint = try QingLongEndpoint.normalizedURL(from: "https://panel.example.com")

        XCTAssertNil(credentials.endpointIdentity)
        XCTAssertFalse(credentials.isBound(to: endpoint))
    }

    func testEndpointValidationRejectsUserInfoQueryAndFragment() {
        let invalidAddresses = [
            "https://user:password@panel.example.com",
            "https://panel.example.com?redirect=https://attacker.example.com",
            "https://panel.example.com#credentials",
            "https:\\attacker.example.com@panel.example.com",
            "https://panel.example.com:70000",
            "ftp://panel.example.com"
        ]

        for address in invalidAddresses {
            XCTAssertThrowsError(try QingLongEndpoint.normalizedURL(from: address), address)
        }
    }

    func testDiagnosticReportNeverContainsCredentialsOrReturnedToken() async throws {
        let clientID = "diagnostic-client-id"
        let clientSecret = "diagnostic-client-secret"
        let returnedToken = "diagnostic-access-token"
        QingLongDiagnosticURLProtocol.responseProvider = { request in
            let body: String
            if request.url?.path.hasSuffix("/auth/token") == true {
                body = #"{"code":200,"data":{"token":"\#(returnedToken)","expiration":1999999999,"echo":"\#(clientID) \#(clientSecret)"}}"#
            } else {
                body = #"{"code":200,"data":{"echo":"\#(clientID) \#(clientSecret) \#(returnedToken)"}}"#
            }
            return (200, Data(body.utf8))
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QingLongDiagnosticURLProtocol.self]
        let service = QingLongService(testingURLSession: URLSession(configuration: configuration))

        let report = try await service.diagnoseConnection(
            baseURLString: "https://panel.example.com:5700",
            clientID: clientID,
            clientSecret: clientSecret
        )

        let renderedReport = ([report.baseURL] + report.steps.flatMap {
            [$0.title, $0.url, $0.summary, $0.preview]
        }).joined(separator: "\n")
        XCTAssertFalse(renderedReport.contains(clientID))
        XCTAssertFalse(renderedReport.contains(clientSecret))
        XCTAssertFalse(renderedReport.contains(returnedToken))

        let tokenStep = try XCTUnwrap(report.steps.first)
        let displayedItems = URLComponents(string: tokenStep.url)?.queryItems ?? []
        XCTAssertEqual(displayedItems.first(where: { $0.name == "client_id" })?.value, "REDACTED")
        XCTAssertEqual(displayedItems.first(where: { $0.name == "client_secret" })?.value, "REDACTED")

        let tokenRequest = try XCTUnwrap(
            QingLongDiagnosticURLProtocol.requests.first(where: { $0.url?.path.hasSuffix("/auth/token") == true })
        )
        let requestItems = URLComponents(url: try XCTUnwrap(tokenRequest.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(requestItems.first(where: { $0.name == "client_id" })?.value, clientID)
        XCTAssertEqual(requestItems.first(where: { $0.name == "client_secret" })?.value, clientSecret)
    }

    func testAuthorizationErrorNeverEchoesCredentialsOrTokenResponse() async throws {
        let clientID = "error-client-id"
        let clientSecret = "error-client-secret"
        let returnedToken = "error-access-token"
        QingLongDiagnosticURLProtocol.responseProvider = { _ in
            let body = #"{"code":400,"message":"\#(clientID) \#(clientSecret) \#(returnedToken)"}"#
            return (400, Data(body.utf8))
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QingLongDiagnosticURLProtocol.self]
        let service = QingLongService(testingURLSession: URLSession(configuration: configuration))

        do {
            _ = try await service.connect(
                baseURLString: "https://panel.example.com:5700",
                clientID: clientID,
                clientSecret: clientSecret
            )
            XCTFail("Expected authorization to fail")
        } catch {
            let message = error.localizedDescription
            XCTAssertFalse(message.contains(clientID))
            XCTAssertFalse(message.contains(clientSecret))
            XCTAssertFalse(message.contains(returnedToken))
        }
    }
}

private final class QingLongDiagnosticURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var capturedRequests: [URLRequest] = []
    static var responseProvider: ((URLRequest) -> (statusCode: Int, data: Data))?

    static var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequests
    }

    static func reset() {
        lock.lock()
        capturedRequests = []
        responseProvider = nil
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        Self.capturedRequests.append(request)
        let provider = Self.responseProvider
        Self.lock.unlock()

        guard let url = request.url,
              let provider else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let response = provider(request)
        let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
