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

    var remainingToTarget: Double {
        max(0, UTTrackerMetrics.targetHours - totalHours)
    }

    var isTargetMet: Bool {
        totalHours >= UTTrackerMetrics.targetHours
    }
}
