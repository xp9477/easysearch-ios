import Foundation
import XCTest
@testable import EasySearch

final class AppGroupRollbackTests: XCTestCase {
    private var standard: UserDefaults!
    private var group: UserDefaults!
    private let standardSuite = "AppGroupRollbackTests.standard"
    private let groupSuite = "AppGroupRollbackTests.group"

    override func setUp() {
        super.setUp()
        standard = UserDefaults(suiteName: standardSuite)
        group = UserDefaults(suiteName: groupSuite)
        standard.removePersistentDomain(forName: standardSuite)
        group.removePersistentDomain(forName: groupSuite)
    }

    override func tearDown() {
        standard.removePersistentDomain(forName: standardSuite)
        group.removePersistentDomain(forName: groupSuite)
        super.tearDown()
    }

    func testRollbackCopiesGroupValuesOverStandard() {
        let entriesData = Data("group-entries".utf8)
        group.set(entriesData, forKey: UTTrackerStorage.entriesKey)
        group.set(["Google": 3], forKey: SearchEngineUsageStore.countsKey)
        group.set(Data("group-holiday".utf8), forKey: "\(AppGroupStorage.holidayCacheKeyPrefix)2026_v1")
        standard.set(Data("stale".utf8), forKey: UTTrackerStorage.entriesKey)

        AppGroupStorage.rollbackToStandardIfNeeded(standard: standard, group: group)

        XCTAssertEqual(standard.data(forKey: UTTrackerStorage.entriesKey), entriesData)
        XCTAssertEqual(standard.dictionary(forKey: SearchEngineUsageStore.countsKey) as? [String: Int], ["Google": 3])
        XCTAssertEqual(
            standard.data(forKey: "\(AppGroupStorage.holidayCacheKeyPrefix)2026_v1"),
            Data("group-holiday".utf8)
        )
        XCTAssertTrue(standard.bool(forKey: AppGroupStorage.rollbackMarkerKey))
    }

    func testRollbackRunsOnlyOnce() {
        group.set(Data("first".utf8), forKey: TrainingLogStorage.snapshotKey)
        AppGroupStorage.rollbackToStandardIfNeeded(standard: standard, group: group)

        group.set(Data("second".utf8), forKey: TrainingLogStorage.snapshotKey)
        AppGroupStorage.rollbackToStandardIfNeeded(standard: standard, group: group)

        XCTAssertEqual(standard.data(forKey: TrainingLogStorage.snapshotKey), Data("first".utf8))
    }

    func testRollbackKeepsStandardValuesWhenGroupIsEmpty() {
        let existing = Data("local-only".utf8)
        standard.set(existing, forKey: ExpenseAssistantStorage.snapshotKey)

        AppGroupStorage.rollbackToStandardIfNeeded(standard: standard, group: group)

        XCTAssertEqual(standard.data(forKey: ExpenseAssistantStorage.snapshotKey), existing)
    }

    func testRollbackMarksDoneWhenGroupUnavailable() {
        AppGroupStorage.rollbackToStandardIfNeeded(standard: standard, group: nil)

        XCTAssertTrue(standard.bool(forKey: AppGroupStorage.rollbackMarkerKey))
    }

    func testCloudIdentityStoreBindsFirstAccountAndRejectsDifferentAccount() {
        let key = "test.cloud.identity"
        let store = CloudSyncIdentityStore(userDefaults: standard, key: key)
        let firstUserID = UUID()
        let secondUserID = UUID()

        XCTAssertEqual(store.match(for: firstUserID), .unbound)

        store.bind(to: firstUserID)

        XCTAssertEqual(store.match(for: firstUserID), .matches)
        XCTAssertEqual(store.match(for: secondUserID), .mismatches)
    }

    func testCloudIdentityStoreRejectsCorruptBindingInsteadOfRebinding() {
        let key = "test.cloud.identity.corrupt"
        standard.set("not-a-uuid", forKey: key)
        let store = CloudSyncIdentityStore(userDefaults: standard, key: key)

        XCTAssertEqual(store.match(for: UUID()), .mismatches)
        XCTAssertEqual(standard.string(forKey: key), "not-a-uuid")
    }
}
