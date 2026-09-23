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

    func testLegacyJSONWithoutMachineDecodesToEmptyString() throws {
        let legacyJSON = """
        {
            "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
            "date": 700000000.0,
            "hours": 8.0,
            "note": "legacy entry",
            "createdAt": 700000000.0
        }
        """
        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let entry = try JSONDecoder().decode(UTEntry.self, from: data)
        XCTAssertEqual(entry.machine, "")
        XCTAssertEqual(entry.hours, 8.0)
        XCTAssertEqual(entry.note, "legacy entry")

        let encoded = try JSONEncoder().encode(entry)
        let roundTripped = try JSONDecoder().decode(UTEntry.self, from: encoded)
        XCTAssertEqual(roundTripped.machine, "")
    }

    func testMachineDurationTotalsWithinOneYearWindow() throws {
        let calendar = Calendar.utTracker
        let formatter = makeFormatter(calendar: calendar)

        let now = try XCTUnwrap(formatter.date(from: "2026-10-10"))
        let startOfToday = calendar.startOfDay(for: now)
        let windowStart = try XCTUnwrap(calendar.date(byAdding: .year, value: -1, to: startOfToday))
        let beforeWindow = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: windowStart))
        let midDate1 = try XCTUnwrap(formatter.date(from: "2026-05-01"))
        let midDate2 = try XCTUnwrap(formatter.date(from: "2026-06-01"))
        let emptyDate1 = try XCTUnwrap(formatter.date(from: "2026-07-01"))
        let emptyDate2 = try XCTUnwrap(formatter.date(from: "2026-07-02"))

        let entries = [
            // Machine A: windowStart (included), today (included), beforeWindow (excluded)
            UTEntry(date: windowStart, hours: 4, note: "start of window", machine: "ECI-01"),
            UTEntry(date: startOfToday, hours: 6, note: "today", machine: "ECI-01"),
            UTEntry(date: beforeWindow, hours: 8, note: "one day before window", machine: "ECI-01"),

            // Machine B: two entries in window
            UTEntry(date: midDate1, hours: 5, note: "mid1", machine: "ECI-02"),
            UTEntry(date: midDate2, hours: 7, note: "mid2", machine: "ECI-02"),

            // Empty machine entries: should not enter totals
            UTEntry(date: emptyDate1, hours: 8, note: "no machine", machine: ""),
            UTEntry(date: emptyDate2, hours: 8, note: "whitespace machine", machine: "   ")
        ]

        let totals = UTMachineDuration.totals(entries: entries, now: now, calendar: calendar)

        XCTAssertEqual(totals.count, 2)
        XCTAssertEqual(totals.first?.machine, "ECI-02")
        XCTAssertEqual(totals.first?.totalHours, 12.0)
        XCTAssertEqual(totals.last?.machine, "ECI-01")
        XCTAssertEqual(totals.last?.totalHours, 10.0)

        // Equal hours tie-break: sorted by machine name ascending
        let tieEntries = [
            UTEntry(date: now, hours: 5, note: "", machine: "Machine-B"),
            UTEntry(date: now, hours: 5, note: "", machine: "Machine-A")
        ]
        let tieTotals = UTMachineDuration.totals(entries: tieEntries, now: now, calendar: calendar)
        XCTAssertEqual(tieTotals.map(\.machine), ["Machine-A", "Machine-B"])
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
