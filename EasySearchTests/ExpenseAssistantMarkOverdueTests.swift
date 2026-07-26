import Foundation
import XCTest
@testable import EasySearch

@MainActor
final class ExpenseAssistantMarkOverdueTests: XCTestCase {
    private final class InMemoryExpenseStore: ExpenseAssistantStore {
        var snapshot = ExpenseAssistantSnapshot()

        func loadSnapshot() -> ExpenseAssistantSnapshot {
            snapshot
        }

        func saveSnapshot(_ snapshot: ExpenseAssistantSnapshot) {
            self.snapshot = snapshot
        }
    }

    func testMarkAllOverdueSubmittedResolvesOnlyOverdueClaims() {
        let calendar = makeCalendar()
        let now = makeDate(year: 2026, month: 2, day: 20, hour: 9, minute: 0, calendar: calendar)
        let store = InMemoryExpenseStore()
        store.snapshot = ExpenseAssistantSnapshot(
            monthlyClaims: [
                MonthlyExpenseClaim(
                    monthStart: makeDate(year: 2026, month: 1, day: 1, hour: 0, minute: 0, calendar: calendar),
                    calendar: calendar,
                    taxi: .completed,
                    parking: .pending,
                    phoneBill: .pending,
                    misc: .notNeeded
                ),
                MonthlyExpenseClaim(
                    monthStart: makeDate(year: 2026, month: 2, day: 1, hour: 0, minute: 0, calendar: calendar),
                    calendar: calendar,
                    taxi: .pending,
                    parking: .pending,
                    phoneBill: .pending,
                    misc: .pending
                )
            ],
            travelClaims: [
                TravelExpenseClaim(
                    title: "上海出差",
                    startDate: makeDate(year: 2026, month: 2, day: 1, hour: 9, minute: 0, calendar: calendar),
                    endDate: makeDate(year: 2026, month: 2, day: 3, hour: 18, minute: 0, calendar: calendar),
                    travelApprovalStatus: .approved,
                    perDiemStatus: .pending,
                    expenseStatus: .completed
                )
            ]
        )

        let viewModel = ExpenseAssistantViewModel(
            store: store,
            calendar: calendar,
            nowProvider: { now }
        )
        XCTAssertFalse(viewModel.overdueMonthlyClaimIDs.isEmpty)

        viewModel.markAllOverdueSubmitted()

        let january = viewModel.snapshot.monthlyClaims.first(where: { $0.id == "2026-01" })
        XCTAssertNotNil(january)
        XCTAssertTrue(january!.isCompleted)
        XCTAssertEqual(january!.status(for: .taxi), .completed)
        XCTAssertEqual(january!.status(for: .misc), .notNeeded)

        // 当前月不算逾期,保持 pending
        let february = viewModel.snapshot.monthlyClaims.first(where: { $0.id == "2026-02" })
        XCTAssertEqual(february?.status(for: .taxi), .pending)

        let travel = viewModel.snapshot.travelClaims.first
        XCTAssertEqual(travel?.perDiemStatus, .completed)
        XCTAssertEqual(travel?.expenseStatus, .completed)

        XCTAssertTrue(viewModel.overdueMonthlyClaimIDs.isEmpty)
        XCTAssertTrue(viewModel.overdueTravelClaimIDs.isEmpty)
    }

    func testMarkAllOverdueSubmittedIsNoOpWithoutOverdue() {
        let calendar = makeCalendar()
        let now = makeDate(year: 2026, month: 1, day: 10, hour: 9, minute: 0, calendar: calendar)
        let store = InMemoryExpenseStore()

        let viewModel = ExpenseAssistantViewModel(
            store: store,
            calendar: calendar,
            nowProvider: { now }
        )
        let before = viewModel.snapshot

        viewModel.markAllOverdueSubmitted()

        XCTAssertEqual(viewModel.snapshot, before)
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
        calendar: Calendar
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
        )!
    }
}
