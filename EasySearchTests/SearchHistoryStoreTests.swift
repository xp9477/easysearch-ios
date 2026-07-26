import Foundation
import XCTest
@testable import EasySearch

final class SearchHistoryStoreTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private let suiteName = "SearchHistoryStoreTests"

    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testRecordInsertsNewestFirst() {
        let store = SearchHistoryStore(userDefaults: userDefaults)
        store.record(query: "first", engineName: "Google")
        store.record(query: "second", engineName: "百度")

        let entries = store.load()
        XCTAssertEqual(entries.map(\.query), ["second", "first"])
        XCTAssertEqual(entries.first?.engineName, "百度")
    }

    func testRecordDeduplicatesSameQuery() {
        let store = SearchHistoryStore(userDefaults: userDefaults)
        store.record(query: "swift", engineName: "Google")
        store.record(query: "ios", engineName: "Google")
        store.record(query: "swift", engineName: "Bilibili")

        let entries = store.load()
        XCTAssertEqual(entries.map(\.query), ["swift", "ios"])
        XCTAssertEqual(entries.first?.engineName, "Bilibili")
    }

    func testRecordIgnoresEmptyQuery() {
        let store = SearchHistoryStore(userDefaults: userDefaults)
        store.record(query: "   ", engineName: "Google")
        XCTAssertTrue(store.load().isEmpty)
    }

    func testRecordCapsAtMaxEntries() {
        let store = SearchHistoryStore(userDefaults: userDefaults)
        for index in 0..<(SearchHistoryStore.maxEntries + 5) {
            store.record(query: "query-\(index)", engineName: "Google")
        }

        let entries = store.load()
        XCTAssertEqual(entries.count, SearchHistoryStore.maxEntries)
        XCTAssertEqual(entries.first?.query, "query-\(SearchHistoryStore.maxEntries + 4)")
    }

    func testRemoveAndClear() {
        let store = SearchHistoryStore(userDefaults: userDefaults)
        store.record(query: "keep", engineName: "Google")
        store.record(query: "drop", engineName: "Google")

        store.remove(query: "drop")
        XCTAssertEqual(store.load().map(\.query), ["keep"])

        store.clear()
        XCTAssertTrue(store.load().isEmpty)
    }
}
