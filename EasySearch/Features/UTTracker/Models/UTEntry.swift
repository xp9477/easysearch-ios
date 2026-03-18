import Foundation

enum UTTrackerMetrics {
    static let fullWeekHours: Double = 40
    static let targetRatio: Double = 0.7
    static let targetHours: Double = fullWeekHours * targetRatio
    static let weeklyWarningRatio: Double = 0.6
    static let weeklyWarningHours: Double = fullWeekHours * weeklyWarningRatio
    static let dailyReferenceHours: Double = 8
}

enum UTTrackerStorage {
    static let entriesKey = "ut_tracker_entries_v1"
}

struct UTEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let date: Date
    let hours: Double
    let note: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        date: Date,
        hours: Double,
        note: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.hours = hours
        self.note = note
        self.createdAt = createdAt
    }
}

struct UTWeekSummary: Identifiable, Hashable {
    let weekStart: Date
    let weekEnd: Date
    let totalHours: Double

    var id: Date { weekStart }

    var targetProgress: Double {
        guard UTTrackerMetrics.targetHours > 0 else { return 0 }
        return totalHours / UTTrackerMetrics.targetHours
    }

    var fullWeekProgress: Double {
        guard UTTrackerMetrics.fullWeekHours > 0 else { return 0 }
        return totalHours / UTTrackerMetrics.fullWeekHours
    }

    var remainingToTarget: Double {
        max(0, UTTrackerMetrics.targetHours - totalHours)
    }

    var isTargetMet: Bool {
        totalHours >= UTTrackerMetrics.targetHours
    }
}

enum UTTrackerSnapshot {
    static func currentWeekSummary(
        userDefaults: UserDefaults = .standard,
        calendar: Calendar = .utTracker,
        now: Date = Date()
    ) -> UTWeekSummary {
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now)
            ?? DateInterval(start: calendar.startOfDay(for: now), duration: 7 * 24 * 60 * 60)
        let weekStart = weekInterval.start
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart

        let totalHours = UTTrackerLocalStore(userDefaults: userDefaults)
            .loadEntries()
            .filter { weekInterval.contains($0.date) }
            .reduce(0) { $0 + $1.hours }

        return UTWeekSummary(
            weekStart: weekStart,
            weekEnd: weekEnd,
            totalHours: totalHours
        )
    }
}
