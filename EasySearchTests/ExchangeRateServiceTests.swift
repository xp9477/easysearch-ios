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

    func testFetchRateParsesAllSupportedCurrenciesFromNetworkResponse() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://open.er-api.com/v6/latest/CNY")
            let body = """
            {
              "result": "success",
              "rates": {
                "TWD": 4.321,
                "USD": 0.14,
                "JPY": 21.5,
                "KRW": 190.2,
                "TRY": 4.8,
                "INR": 11.6
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

        XCTAssertEqual(result.rate(of: .twd), 4.321, accuracy: 0.0001)
        XCTAssertEqual(result.rate(of: .usd), 0.14, accuracy: 0.0001)
        XCTAssertEqual(result.rate(of: .jpy), 21.5, accuracy: 0.0001)
        XCTAssertEqual(result.rate(of: .krw), 190.2, accuracy: 0.0001)
        XCTAssertEqual(result.rate(of: .tryLira), 4.8, accuracy: 0.0001)
        XCTAssertEqual(result.rate(of: .inr), 11.6, accuracy: 0.0001)
        XCTAssertEqual(result.rate(of: .cny), 1, accuracy: 0.0001)
        XCTAssertEqual(result.source, .network)
        XCTAssertEqual(userDefaults.double(forKey: "currencyConverter.cachedRate"), 4.321, accuracy: 0.0001)
    }

    func testConvertAcrossNonCNYPair() {
        let result = ExchangeRateResult(
            ratesAgainstCNY: [
                .cny: 1,
                .usd: 0.1,
                .jpy: 15
            ],
            updatedAt: Date(),
            source: .network
        )
        // 2 USD -> 20 CNY -> 300 JPY
        let converted = result.convert(amount: 2, from: .usd, to: .jpy)
        XCTAssertEqual(converted ?? 0, 300, accuracy: 0.0001)
    }

    func testNetworkFailureFallsBackToCache() async throws {
        let payload: [String: Double] = [
            "CNY": 1,
            "TWD": 4.2,
            "USD": 0.14,
            "JPY": 21,
            "KRW": 190,
            "TRY": 4.8,
            "INR": 11.5
        ]
        userDefaults.set(try! JSONEncoder().encode(payload), forKey: "currencyConverter.cachedRates.v2")
        userDefaults.set(Date().timeIntervalSince1970 - 3600, forKey: "currencyConverter.cachedDate.v2")

        MockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        let service = ExchangeRateService(
            urlSession: makeMockSession(),
            userDefaults: userDefaults
        )

        let result = try await service.fetchRate(force: true)

        XCTAssertEqual(result.rate(of: .twd), 4.2, accuracy: 0.0001)
        XCTAssertEqual(result.source, .cache)
    }

    func testFreshCacheSkipsNetworkWhenNotForced() async throws {
        let now = Date()
        let payload: [String: Double] = [
            "CNY": 1,
            "TWD": 4.11,
            "USD": 0.14,
            "JPY": 21,
            "KRW": 190,
            "TRY": 4.8,
            "INR": 11.5
        ]
        userDefaults.set(try! JSONEncoder().encode(payload), forKey: "currencyConverter.cachedRates.v2")
        userDefaults.set(now.timeIntervalSince1970, forKey: "currencyConverter.cachedDate.v2")

        var networkCallCount = 0
        MockURLProtocol.requestHandler = { request in
            networkCallCount += 1
            let body = """
            {"result":"success","rates":{"TWD":9.99,"USD":0.1,"JPY":1,"KRW":1,"TRY":1,"INR":1}}
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

        XCTAssertEqual(result.rate(of: .twd), 4.11, accuracy: 0.0001)
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
