import Foundation
import XCTest
@testable import EasySearch

final class ExpenseAssistantTests: XCTestCase {
    func testNormalizedBackfillsMonthlyClaimsFromJanuary2026ThroughCurrentMonth() {
        let calendar = makeCalendar()
        let now = makeDate(year: 2026, month: 3, day: 18, hour: 10, minute: 0, calendar: calendar)
        let existingClaim = MonthlyExpenseClaim(
            monthStart: makeDate(year: 2026, month: 2, day: 1, hour: 0, minute: 0, calendar: calendar),
            calendar: calendar,
            taxi: .completed,
            parking: .pending,
            phoneBill: .pending,
            misc: .pending
        )

        let snapshot = ExpenseAssistantReminderEngine.normalized(
            snapshot: ExpenseAssistantSnapshot(monthlyClaims: [existingClaim]),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.monthlyClaims.map(\.id), ["2026-03", "2026-02", "2026-01"])
        XCTAssertEqual(snapshot.monthlyClaims.first(where: { $0.id == "2026-02" })?.taxi, .completed)
    }

    func testClaimCompletionAllowsCompletedAndNotNeededMix() {
        let monthlyClaim = MonthlyExpenseClaim(
            monthStart: makeDate(year: 2026, month: 1, day: 1, hour: 0, minute: 0),
            taxi: .completed,
            parking: .notNeeded,
            phoneBill: .completed,
            misc: .notNeeded
        )
        let travelClaim = TravelExpenseClaim(
            title: "",
            startDate: makeDate(year: 2026, month: 2, day: 3, hour: 9, minute: 0),
            endDate: makeDate(year: 2026, month: 2, day: 5, hour: 18, minute: 0),
            travelApprovalStatus: .approved,
            perDiemStatus: .notNeeded,
            expenseStatus: .completed
        )
        let submittedTravelClaim = TravelExpenseClaim(
            title: "",
            startDate: makeDate(year: 2026, month: 2, day: 3, hour: 9, minute: 0),
            endDate: makeDate(year: 2026, month: 2, day: 5, hour: 18, minute: 0),
            travelApprovalStatus: .submitted,
            perDiemStatus: .completed,
            expenseStatus: .completed
        )

        XCTAssertTrue(monthlyClaim.isCompleted)
        XCTAssertTrue(travelClaim.isCompleted)
        XCTAssertFalse(submittedTravelClaim.isCompleted)
    }

    func testOverdueMonthlyClaimsSkipCurrentMonthButIncludeOlderMonths() {
        let calendar = makeCalendar()
        let snapshot = ExpenseAssistantSnapshot(
            monthlyClaims: [
                MonthlyExpenseClaim(
                    monthStart: makeDate(year: 2026, month: 1, day: 1, hour: 0, minute: 0, calendar: calendar),
                    calendar: calendar,
                    taxi: .completed,
                    parking: .pending,
                    phoneBill: .pending,
                    misc: .pending
                ),
                MonthlyExpenseClaim(
                    monthStart: makeDate(year: 2026, month: 2, day: 1, hour: 0, minute: 0, calendar: calendar),
                    calendar: calendar,
                    taxi: .pending,
                    parking: .pending,
                    phoneBill: .pending,
                    misc: .pending
                )
            ]
        )
        let referenceDate = makeDate(year: 2026, month: 2, day: 20, hour: 9, minute: 0, calendar: calendar)

        let overdueClaims = ExpenseAssistantReminderEngine.overdueMonthlyClaims(
            in: snapshot,
            asOf: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(overdueClaims.map(\.id), ["2026-01"])
    }

    func testOverdueTravelClaimsRequireEndedTripAndIncompleteStatuses() {
        let calendar = makeCalendar()
        let endedPendingClaim = TravelExpenseClaim(
            title: "上海出差",
            startDate: makeDate(year: 2026, month: 2, day: 1, hour: 9, minute: 0, calendar: calendar),
            endDate: makeDate(year: 2026, month: 2, day: 3, hour: 18, minute: 0, calendar: calendar),
            travelApprovalStatus: .approved,
            perDiemStatus: .pending,
            expenseStatus: .completed
        )
        let notEndedClaim = TravelExpenseClaim(
            title: "北京出差",
            startDate: makeDate(year: 2026, month: 2, day: 10, hour: 9, minute: 0, calendar: calendar),
            endDate: nil,
            travelApprovalStatus: .pending,
            perDiemStatus: .pending,
            expenseStatus: .pending
        )
        let sameMorningClaim = TravelExpenseClaim(
            title: "杭州出差",
            startDate: makeDate(year: 2026, month: 2, day: 11, hour: 8, minute: 0, calendar: calendar),
            endDate: makeDate(year: 2026, month: 2, day: 12, hour: 8, minute: 0, calendar: calendar),
            travelApprovalStatus: .pending,
            perDiemStatus: .pending,
            expenseStatus: .pending
        )
        let referenceDate = makeDate(year: 2026, month: 2, day: 12, hour: 9, minute: 0, calendar: calendar)

        let overdueClaims = ExpenseAssistantReminderEngine.overdueTravelClaims(
            in: ExpenseAssistantSnapshot(travelClaims: [endedPendingClaim, notEndedClaim, sameMorningClaim]),
            asOf: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(overdueClaims.map(\.resolvedTitle(calendar:)), ["上海出差", "杭州出差"])
    }

    func testReminderContentSummarizesMonthlyAndTravelClaims() {
        let calendar = makeCalendar()
        let snapshot = ExpenseAssistantSnapshot(
            monthlyClaims: [
                MonthlyExpenseClaim(
                    monthStart: makeDate(year: 2026, month: 1, day: 1, hour: 0, minute: 0, calendar: calendar),
                    calendar: calendar,
                    taxi: .pending,
                    parking: .pending,
                    phoneBill: .pending,
                    misc: .pending
                )
            ],
            travelClaims: [
                TravelExpenseClaim(
                    title: "",
                    startDate: makeDate(year: 2026, month: 2, day: 8, hour: 9, minute: 0, calendar: calendar),
                    endDate: makeDate(year: 2026, month: 2, day: 9, hour: 18, minute: 0, calendar: calendar),
                    travelApprovalStatus: .submitted,
                    perDiemStatus: .pending,
                    expenseStatus: .pending
                )
            ]
        )
        let reminderDate = makeDate(year: 2026, month: 2, day: 10, hour: 9, minute: 0, calendar: calendar)

        let content = ExpenseAssistantReminderEngine.reminderContent(
            in: snapshot,
            asOf: reminderDate,
            calendar: calendar
        )

        XCTAssertEqual(content?.title, "报销助手：2 项待处理")
        XCTAssertEqual(content?.body, "月单 1 项，出差 1 项。待处理：2026年1月 月度报销、2月8日 - 2月9日 出差。")
    }

    func testReminderContentCondensesLongList() {
        let calendar = makeCalendar()
        let snapshot = ExpenseAssistantSnapshot(
            monthlyClaims: [
                MonthlyExpenseClaim(monthStart: makeDate(year: 2026, month: 1, day: 1, hour: 0, minute: 0, calendar: calendar), calendar: calendar),
                MonthlyExpenseClaim(monthStart: makeDate(year: 2026, month: 2, day: 1, hour: 0, minute: 0, calendar: calendar), calendar: calendar),
                MonthlyExpenseClaim(monthStart: makeDate(year: 2026, month: 3, day: 1, hour: 0, minute: 0, calendar: calendar), calendar: calendar)
            ],
            travelClaims: [
                TravelExpenseClaim(
                    title: "广州出差",
                    startDate: makeDate(year: 2026, month: 3, day: 1, hour: 9, minute: 0, calendar: calendar),
                    endDate: makeDate(year: 2026, month: 3, day: 2, hour: 18, minute: 0, calendar: calendar),
                    travelApprovalStatus: .pending,
                    perDiemStatus: .pending,
                    expenseStatus: .pending
                )
            ]
        )
        let reminderDate = makeDate(year: 2026, month: 4, day: 1, hour: 9, minute: 0, calendar: calendar)

        let content = ExpenseAssistantReminderEngine.reminderContent(
            in: snapshot,
            asOf: reminderDate,
            calendar: calendar
        )

        XCTAssertEqual(content?.title, "报销助手：4 项待处理")
        XCTAssertTrue(content?.body.contains("等 2 项。") == true)
    }

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar = Calendar.expenseAssistant
    ) -> Date {
        calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        ) ?? Date(timeIntervalSince1970: 0)
    }
}
