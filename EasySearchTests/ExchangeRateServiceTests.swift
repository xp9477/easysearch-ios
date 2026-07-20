import XCTest
@testable import EasySearch

final class ExchangeRateServiceTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var defaultsSuiteName: String!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "ExchangeRateServiceTests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: defaultsSuiteName)
        userDefaults.removePersistentDomain(forName: defaultsSuiteName)
        MockURLProtocol.requestHandler = nil
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        if let defaultsSuiteName {
            userDefaults?.removePersistentDomain(forName: defaultsSuiteName)
        }
        userDefaults = nil
        defaultsSuiteName = nil
        super.tearDown()
    }

    func testFetchRateParsesTWDFromNetworkResponse() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://open.er-api.com/v6/latest/CNY")
            let body = """
            {
              "result": "success",
              "rates": {
                "TWD": 4.321,
                "USD": 0.14
              }
            }
            """.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, body)
        }

        let service = ExchangeRateService(
            urlSession: makeMockSession(),
            userDefaults: userDefaults
        )

        let result = try await service.fetchRate(force: true)

        XCTAssertEqual(result.rate, 4.321, accuracy: 0.0001)
        XCTAssertEqual(result.source, .network)
        XCTAssertEqual(userDefaults.double(forKey: "currencyConverter.cachedRate"), 4.321, accuracy: 0.0001)
    }

    func testNetworkFailureFallsBackToCache() async throws {
        userDefaults.set(4.2, forKey: "currencyConverter.cachedRate")
        userDefaults.set(Date().timeIntervalSince1970 - 3600, forKey: "currencyConverter.cachedDate")

        MockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        let service = ExchangeRateService(
            urlSession: makeMockSession(),
            userDefaults: userDefaults
        )

        let result = try await service.fetchRate(force: true)

        XCTAssertEqual(result.rate, 4.2, accuracy: 0.0001)
        XCTAssertEqual(result.source, .cache)
    }

    func testFreshCacheSkipsNetworkWhenNotForced() async throws {
        let now = Date()
        userDefaults.set(4.11, forKey: "currencyConverter.cachedRate")
        userDefaults.set(now.timeIntervalSince1970, forKey: "currencyConverter.cachedDate")

        var networkCallCount = 0
        MockURLProtocol.requestHandler = { request in
            networkCallCount += 1
            let body = """
            {"result":"success","rates":{"TWD":9.99}}
            """.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, body)
        }

        let service = ExchangeRateService(
            urlSession: makeMockSession(),
            userDefaults: userDefaults
        )

        let result = try await service.fetchRate(force: false)

        XCTAssertEqual(result.rate, 4.11, accuracy: 0.0001)
        XCTAssertEqual(result.source, .cache)
        XCTAssertEqual(networkCallCount, 0)
    }

    private func makeMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

// MARK: - Mock URLProtocol

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        do {
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
