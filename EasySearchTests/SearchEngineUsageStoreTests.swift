import Foundation
import XCTest
@testable import EasySearch

final class SearchEngineUsageStoreTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private let suiteName = "SearchEngineUsageStoreTests"

    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeEngine(_ name: String) -> SearchEngine {
        SearchEngine(name: name, url: "https://example.com/{query}", urlScheme: nil, category: nil)
    }

    func testRecordUseTracksCountsAndLastUsed() {
        let store = SearchEngineUsageStore(userDefaults: userDefaults)
        store.recordUse(engineName: "Google")
        store.recordUse(engineName: "Google")
        store.recordUse(engineName: "百度")

        XCTAssertEqual(store.useCount(for: "Google"), 2)
        XCTAssertEqual(store.useCount(for: "百度"), 1)
        XCTAssertEqual(store.lastUsedEngineName, "百度")
    }

    func testSortedByUsageKeepsOriginalOrderForTies() {
        let store = SearchEngineUsageStore(userDefaults: userDefaults)
        let engines = [makeEngine("A"), makeEngine("B"), makeEngine("C")]
        store.recordUse(engineName: "C")

        let sorted = store.sortedByUsage(engines)
        XCTAssertEqual(sorted.map(\.name), ["C", "A", "B"])
    }

    func testFrequentEnginesOnlyIncludesUsed() {
        let store = SearchEngineUsageStore(userDefaults: userDefaults)
        let engines = [makeEngine("A"), makeEngine("B"), makeEngine("C")]
        store.recordUse(engineName: "B")
        store.recordUse(engineName: "B")
        store.recordUse(engineName: "A")

        let frequent = store.frequentEngines(from: engines)
        XCTAssertEqual(frequent.map(\.name), ["B", "A"])
    }
}
