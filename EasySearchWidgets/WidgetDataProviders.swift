import Foundation
import WidgetKit

/// Widget 侧共享数据读取。
enum WidgetData {
    static func utSummary(now: Date = Date()) -> UTMonthSummary {
        UTTrackerSnapshot.currentMonthSummary(now: now)
    }

    static func utLoggedToday(now: Date = Date()) -> Bool {
        let calendar = Calendar.utTracker
        return UTTrackerLocalStore().loadEntries().contains {
            calendar.isDate($0.date, inSameDayAs: now)
        }
    }

    static func trainingSnapshot() -> TrainingLogSnapshot {
        TrainingLogLocalStore().loadSnapshot()
    }

    static func trainingTodayLineCount(now: Date = Date()) -> Int {
        trainingSnapshot().days[TrainingLogCalendar.dayKey(for: now)]?.lines.count ?? 0
    }

    static func trainingMonthDayCount(now: Date = Date()) -> Int {
        let calendar = TrainingLogCalendar.calendar
        guard let interval = calendar.dateInterval(of: .month, for: now) else { return 0 }
        return trainingSnapshot().days.values
            .filter { $0.hasTraining && interval.contains($0.dayStart) }
            .count
    }

    static func lastTrainedDay(before date: Date) -> WorkoutDay? {
        let dayStart = TrainingLogCalendar.startOfDay(date)
        return trainingSnapshot().days.values
            .filter { $0.hasTraining && $0.dayStart < dayStart }
            .max(by: { $0.dayStart < $1.dayStart })
    }

    static func overdueExpenseCount(now: Date = Date()) -> Int {
        let snapshot = ExpenseAssistantLocalStore().loadSnapshot()
        let calendar = Calendar.expenseAssistant
        let monthly = ExpenseAssistantReminderEngine.overdueMonthlyClaims(in: snapshot, asOf: now, calendar: calendar)
        let travel = ExpenseAssistantReminderEngine.overdueTravelClaims(in: snapshot, asOf: now, calendar: calendar)
        return monthly.count + travel.count
    }

    static func hoursText(_ hours: Double) -> String {
        hours.formatted(.number.precision(.fractionLength(0 ... 1)))
    }
}
