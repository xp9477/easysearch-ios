import AppIntents
import Foundation
import WidgetKit

struct LogUTHoursIntent: AppIntent {
    static let title: LocalizedStringResource = "记录今天 UT 工时"
    static let description = IntentDescription("为今天登记默认 8 小时工时。")

    func perform() async throws -> some IntentResult {
        let store = UTTrackerLocalStore()
        var entries = store.loadEntries()
        let calendar = Calendar.utTracker
        let now = Date()
        guard !entries.contains(where: { calendar.isDate($0.date, inSameDayAs: now) }) else {
            return .result()
        }
        entries.append(
            UTEntry(date: now, hours: UTTrackerMetrics.dailyReferenceHours, note: "")
        )
        store.saveEntries(entries)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct RepeatLastWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "重复上次训练"
    static let description = IntentDescription("把最近一个训练日的全部动作复制到今天。")

    func perform() async throws -> some IntentResult {
        let store = TrainingLogLocalStore()
        var snapshot = store.loadSnapshot()
        let now = Date()
        let todayKey = TrainingLogCalendar.dayKey(for: now)
        let todayStart = TrainingLogCalendar.startOfDay(now)

        guard let source = snapshot.days.values
            .filter({ $0.hasTraining && $0.dayStart < todayStart })
            .max(by: { $0.dayStart < $1.dayStart }) else {
            return .result()
        }

        var day = snapshot.days[todayKey] ?? WorkoutDay(
            id: todayKey,
            dayStart: todayStart,
            lines: [],
            note: nil
        )
        for line in source.lines {
            day.lines.append(
                WorkoutLine(
                    exerciseID: line.exerciseID,
                    exerciseName: line.exerciseName,
                    amount: line.amount,
                    unit: line.unit
                )
            )
        }
        snapshot.days[todayKey] = day
        store.saveSnapshot(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
