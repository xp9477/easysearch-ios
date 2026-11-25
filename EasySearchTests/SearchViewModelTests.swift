import Foundation
import XCTest
@testable import EasySearch

@MainActor
final class SearchViewModelTests: XCTestCase {
    func testSearchEngineBuildsGoogleFaviconURL() throws {
        let engine = SearchEngine(
            name: "GitHub",
            url: "https://github.com/search?q={query}",
            urlScheme: nil,
            category: SearchCategory.search.rawValue
        )

        let faviconURL = try XCTUnwrap(engine.faviconURL)
        let components = try XCTUnwrap(URLComponents(url: faviconURL, resolvingAgainstBaseURL: false))

        XCTAssertEqual(engine.displayHost, "github.com")
        XCTAssertEqual(components.host, "www.google.com")
        XCTAssertEqual(components.path, "/s2/favicons")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "domain_url" })?.value, "https://github.com")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "sz" })?.value, "128")
    }

    func testInitializationLoadsCachedConfigWithoutRemoteRefresh() throws {
        let userDefaults = makeUserDefaults()
        let engines = [makeEngine(name: "Local")]
        let data = try JSONEncoder().encode(engines)
        userDefaults.set(data, forKey: "cached_search_engines")
        let remoteClient = SpySearchEngineRemoteConfigClient(remoteData: data)

        let viewModel = SearchViewModel(
            userDefaults: userDefaults,
            remoteConfigURL: URL(string: "https://example.com/search-engines.json"),
            remoteConfigClient: remoteClient
        )

        XCTAssertEqual(viewModel.searchEngines, engines)
        XCTAssertEqual(remoteClient.fetchLastModifiedCallCount, 0)
        XCTAssertEqual(remoteClient.downloadConfigCallCount, 0)
    }

    func testLaunchRefreshUsesRemoteClientOnlyOnce() async throws {
        let userDefaults = makeUserDefaults()
        let localEngines = [makeEngine(name: "Local")]
        let remoteEngines = [makeEngine(name: "Remote")]
        userDefaults.set(try JSONEncoder().encode(localEngines), forKey: "cached_search_engines")

        let remoteData = try JSONEncoder().encode(remoteEngines)
        let remoteClient = SpySearchEngineRemoteConfigClient(
            remoteLastModified: "Sat, 02 May 2026 00:00:00 GMT",
            remoteData: remoteData
        )
        let viewModel = SearchViewModel(
            userDefaults: userDefaults,
            remoteConfigURL: URL(string: "https://example.com/search-engines.json"),
            remoteConfigClient: remoteClient
        )

        await viewModel.refreshConfigIfNeededOnLaunch()
        await viewModel.refreshConfigIfNeededOnLaunch()

        XCTAssertEqual(viewModel.searchEngines, remoteEngines)
        XCTAssertEqual(remoteClient.fetchLastModifiedCallCount, 1)
        XCTAssertEqual(remoteClient.downloadConfigCallCount, 1)
    }

    func testDefaultPlatformNeverCrossesCategoryAndRemembersSelection() {
        let defaults = makeUserDefaults()
        let usageStore = SearchEngineUsageStore(userDefaults: defaults)
        usageStore.recordUse(engineName: "Google")
        let viewModel = SearchViewModel(userDefaults: defaults, remoteConfigURL: nil, usageStore: usageStore)
        let baidu = makeEngine(name: "百度")
        let google = makeEngine(name: "Google")
        let ai = SearchEngine(name: "AI", url: "https://example.com/?q={query}", urlScheme: nil, category: "AI")
        viewModel.searchEngines = [baidu, google, ai]

        XCTAssertEqual(viewModel.filteredEngines, [baidu, google])
        XCTAssertEqual(viewModel.defaultSearchEngine, google)
        viewModel.selectPlatform(baidu)
        viewModel.selectedCategory = .ai
        XCTAssertEqual(viewModel.defaultSearchEngine, ai)
        viewModel.selectPlatform(google)
        XCTAssertEqual(viewModel.defaultSearchEngine, ai)
        viewModel.selectedCategory = .search
        XCTAssertEqual(viewModel.defaultSearchEngine, baidu)
        viewModel.searchEngines = [google, ai]
        XCTAssertEqual(viewModel.defaultSearchEngine, google)
        viewModel.selectedCategory = .shopping
        XCTAssertNil(viewModel.defaultSearchEngine)
    }

    func testQueryStaysInSingleQueryValueOrPathSegment() throws {
        let query = "树 &a=b/# + 100%"
        let url = try XCTUnwrap(SearchEngine.searchURL(template: "https://example.com/?q={query}&source=app", query: query))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(items, [URLQueryItem(name: "q", value: query), URLQueryItem(name: "source", value: "app")])
        let path = try XCTUnwrap(SearchEngine.searchURL(template: "https://example.com/search/{query}", query: query))
        XCTAssertTrue(path.absoluteString.contains("%2F%23"))
        XCTAssertNil(path.fragment)
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "SearchViewModelTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        return userDefaults
    }

    private func makeEngine(name: String) -> SearchEngine {
        SearchEngine(
            name: name,
            url: "https://example.com/search?q={query}",
            urlScheme: nil,
            category: SearchCategory.search.rawValue
        )
    }
}

private final class SpySearchEngineRemoteConfigClient: SearchEngineRemoteConfigClient {
    private let remoteLastModified: String?
    private let remoteData: Data
    private(set) var fetchLastModifiedCallCount = 0
    private(set) var downloadConfigCallCount = 0

    init(
        remoteLastModified: String? = nil,
        remoteData: Data
    ) {
        self.remoteLastModified = remoteLastModified
        self.remoteData = remoteData
    }

    func fetchLastModified(from url: URL) async throws -> String? {
        fetchLastModifiedCallCount += 1
        return remoteLastModified
    }

    func downloadConfig(from url: URL) async throws -> (data: Data, lastModified: String?) {
        downloadConfigCallCount += 1
        return (remoteData, remoteLastModified)
    }
}
