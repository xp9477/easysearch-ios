import Foundation

enum UTTrackerMetrics {
    static let fullWeekHours: Double = 40
    static let targetRatio: Double = 0.7
    static let targetHours: Double = fullWeekHours * targetRatio
    static let dailyReferenceHours: Double = 8
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

struct UTDaySummary: Identifiable, Hashable {
    let date: Date
    let hours: Double

    var id: Date { date }
}

struct UTWeekSummary: Identifiable, Hashable {
    let weekStart: Date
    let weekEnd: Date
    let totalHours: Double

    var id: Date { weekStart }

    var fullProgress: Double {
        guard UTTrackerMetrics.fullWeekHours > 0 else { return 0 }
        return totalHours / UTTrackerMetrics.fullWeekHours
    }

    var targetProgress: Double {
        guard UTTrackerMetrics.targetHours > 0 else { return 0 }
        return totalHours / UTTrackerMetrics.targetHours
    }

    var remainingToTarget: Double {
        max(0, UTTrackerMetrics.targetHours - totalHours)
    }

    var remainingToFull: Double {
        max(0, UTTrackerMetrics.fullWeekHours - totalHours)
    }

    var extraBeyondFull: Double {
        max(0, totalHours - UTTrackerMetrics.fullWeekHours)
    }

    var isTargetMet: Bool {
        totalHours >= UTTrackerMetrics.targetHours
    }
}
