import Foundation
import XCTest
@testable import EasySearch

final class SearchEngineIconCacheTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SearchEngineIconURLProtocol.reset()
    }

    override func tearDown() {
        SearchEngineIconURLProtocol.reset()
        super.tearDown()
    }

    func testSuccessfulResponseIsReusedAcrossLoaders() async throws {
        let directoryURL = makeCacheDirectory()
        let iconData = try makeIconData()
        SearchEngineIconURLProtocol.setHandler { request in
            (try Self.imageResponse(for: request), iconData)
        }

        let url = URL(string: "https://icons.example/github.png")!
        let urlCache = makeURLCache(at: directoryURL)
        var firstLoader: SearchEngineIconCache? = makeLoader(urlCache: urlCache)
        let firstData = try await firstLoader!.data(for: url)
        await firstLoader?.invalidate()
        firstLoader = nil

        var request = URLRequest(url: url)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        XCTAssertNotNil(urlCache.cachedResponse(for: request))

        SearchEngineIconURLProtocol.setHandler { _ in
            throw URLError(.notConnectedToInternet)
        }
        let secondLoader = makeLoader(urlCache: urlCache)
        let secondData = try await secondLoader.data(for: url)

        XCTAssertEqual(firstData, iconData)
        XCTAssertEqual(secondData, iconData)
        XCTAssertEqual(SearchEngineIconURLProtocol.requestCount, 1)
    }

    func testConcurrentRequestsAreCoalesced() async throws {
        let urlCache = makeURLCache(at: makeCacheDirectory())
        let iconData = try makeIconData()
        SearchEngineIconURLProtocol.setHandler(delay: 0.05) { request in
            (try Self.imageResponse(for: request), iconData)
        }

        let loader = makeLoader(urlCache: urlCache)
        let url = URL(string: "https://icons.example/concurrent.png")!
        let responses = try await withThrowingTaskGroup(of: Data.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    try await loader.data(for: url)
                }
            }

            var values: [Data] = []
            for try await value in group {
                values.append(value)
            }
            return values
        }

        XCTAssertEqual(responses.count, 10)
        XCTAssertTrue(responses.allSatisfy { $0 == iconData })
        XCTAssertEqual(SearchEngineIconURLProtocol.requestCount, 1)
    }

    func testInvalidResponseIsNotReused() async throws {
        let urlCache = makeURLCache(at: makeCacheDirectory())
        SearchEngineIconURLProtocol.setHandler { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Cache-Control": "public, max-age=604800",
                    "Content-Type": "text/html"
                ]
            )!
            return (response, Data("not an image".utf8))
        }

        let loader = makeLoader(urlCache: urlCache)
        let url = URL(string: "https://icons.example/invalid.png")!
        do {
            _ = try await loader.data(for: url)
            XCTFail("Expected invalid image response to fail")
        } catch {
            // Expected.
        }

        let iconData = try makeIconData()
        SearchEngineIconURLProtocol.setHandler { request in
            (try Self.imageResponse(for: request), iconData)
        }
        let retriedData = try await loader.data(for: url)

        XCTAssertEqual(retriedData, iconData)
        XCTAssertEqual(SearchEngineIconURLProtocol.requestCount, 2)
    }

    func testNoStoreResponseIsNotCached() async throws {
        let urlCache = makeURLCache(at: makeCacheDirectory())
        let iconData = try makeIconData()
        SearchEngineIconURLProtocol.setHandler { request in
            (
                try Self.imageResponse(for: request, cacheControl: "no-store"),
                iconData
            )
        }

        let loader = makeLoader(urlCache: urlCache)
        let url = URL(string: "https://icons.example/no-store.png")!
        _ = try await loader.data(for: url)
        _ = try await loader.data(for: url)

        XCTAssertEqual(SearchEngineIconURLProtocol.requestCount, 2)
    }

    private func makeCacheDirectory() -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SearchEngineIconCacheTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        return directoryURL
    }

    private func makeURLCache(at directoryURL: URL) -> URLCache {
        return URLCache(
            memoryCapacity: 0,
            diskCapacity: 1024 * 1024,
            directory: directoryURL
        )
    }

    private func makeLoader(urlCache: URLCache) -> SearchEngineIconCache {
        SearchEngineIconCache(
            urlCache: urlCache,
            protocolClasses: [SearchEngineIconURLProtocol.self]
        )
    }

    private func makeIconData() throws -> Data {
        try XCTUnwrap(
            Data(
                base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
            )
        )
    }

    private static func imageResponse(
        for request: URLRequest,
        cacheControl: String = "public, max-age=604800"
    ) throws -> HTTPURLResponse {
        HTTPURLResponse(
            url: try XCTUnwrap(request.url),
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Cache-Control": cacheControl,
                "Content-Type": "image/png"
            ]
        )!
    }
}

private final class SearchEngineIconURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    private static var handler: Handler?
    private static var delay: TimeInterval = 0
    private static var storedRequestCount = 0

    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedRequestCount
    }

    static func setHandler(delay: TimeInterval = 0, _ handler: @escaping Handler) {
        lock.lock()
        self.handler = handler
        self.delay = delay
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        handler = nil
        delay = 0
        storedRequestCount = 0
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "icons.example"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let configuration = Self.currentConfiguration()
        guard let handler = configuration.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        if configuration.delay > 0 {
            Thread.sleep(forTimeInterval: configuration.delay)
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .allowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func currentConfiguration() -> (handler: Handler?, delay: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        storedRequestCount += 1
        return (handler, delay)
    }
}
