import Foundation
import XCTest
@testable import EasySearch

final class UTTrackerMonthSummaryTests: XCTestCase {
    func testMonthSummaryUsesChineseHolidaysAndMakeupWorkdays() throws {
        let userDefaults = makeUserDefaults()
        let calendar = Calendar.utTracker
        let holidayCalendar = UTHolidayCalendar.chinaPRC2026(calendar: calendar)
        let formatter = makeFormatter(calendar: calendar)

        let normalWorkday = try XCTUnwrap(formatter.date(from: "2026-10-08"))
        let nationalHoliday = try XCTUnwrap(formatter.date(from: "2026-10-02"))
        let makeupWorkday = try XCTUnwrap(formatter.date(from: "2026-10-10"))
        let now = try XCTUnwrap(formatter.date(from: "2026-10-10"))

        let entries = [
            UTEntry(date: normalWorkday, hours: 8, note: "normal"),
            UTEntry(date: nationalHoliday, hours: 8, note: "holiday"),
            UTEntry(date: makeupWorkday, hours: 8, note: "makeup")
        ]
        userDefaults.set(try JSONEncoder().encode(entries), forKey: UTTrackerStorage.entriesKey)

        let summary = UTTrackerSnapshot.currentMonthSummary(
            userDefaults: userDefaults,
            calendar: calendar,
            now: now,
            holidayCalendar: holidayCalendar
        )

        XCTAssertEqual(summary.totalHours, 16)
        XCTAssertFalse(calendar.isUTWorkingDay(nationalHoliday, holidayCalendar: holidayCalendar))
        XCTAssertTrue(calendar.isUTWorkingDay(makeupWorkday, holidayCalendar: holidayCalendar))
        XCTAssertEqual(summary.targetHours, summary.elapsedMonthHours * UTTrackerMetrics.targetRatio, accuracy: 0.001)
        XCTAssertLessThanOrEqual(summary.elapsedWorkingDays, summary.totalWorkingDays)
    }

    func testTargetUsesElapsedWorkingDaysNotWholeMonth() throws {
        let userDefaults = makeUserDefaults()
        let calendar = Calendar.utTracker
        let holidayCalendar = UTHolidayCalendar(holidays: [], makeupWorkdays: [])
        let formatter = makeFormatter(calendar: calendar)

        let now = try XCTUnwrap(formatter.date(from: "2026-07-06"))
        let first = try XCTUnwrap(formatter.date(from: "2026-07-01"))
        let second = try XCTUnwrap(formatter.date(from: "2026-07-02"))

        let entries = [
            UTEntry(date: first, hours: 8, note: "d1"),
            UTEntry(date: second, hours: 8, note: "d2")
        ]
        userDefaults.set(try JSONEncoder().encode(entries), forKey: UTTrackerStorage.entriesKey)

        let summary = UTTrackerSnapshot.currentMonthSummary(
            userDefaults: userDefaults,
            calendar: calendar,
            now: now,
            holidayCalendar: holidayCalendar
        )

        XCTAssertLessThan(summary.elapsedWorkingDays, summary.totalWorkingDays)
        XCTAssertEqual(summary.targetHours, Double(summary.elapsedWorkingDays) * 8 * UTTrackerMetrics.targetRatio, accuracy: 0.001)
        XCTAssertEqual(summary.elapsedMonthProgress, summary.totalHours / summary.elapsedMonthHours, accuracy: 0.001)
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "UTTrackerMonthSummaryTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        return userDefaults
    }

    private func makeFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}
