import Foundation
import XCTest
@testable import EasySearch

@MainActor
final class SearchViewModelTests: XCTestCase {
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
