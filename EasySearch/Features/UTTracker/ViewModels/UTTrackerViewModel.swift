import Foundation

final class UTTrackerViewModel: ObservableObject {
    @Published private(set) var entries: [UTEntry] = []

    private let storageKey = "ut_tracker_entries_v1"
    private let userDefaults: UserDefaults
    private let calendar: Calendar

    init(
        userDefaults: UserDefaults = .standard,
        calendar: Calendar = .utTracker
    ) {
        self.userDefaults = userDefaults
        self.calendar = calendar
        loadEntries()
    }

    var currentWeekSummary: UTWeekSummary {
        weekSummary(for: Date())
    }

    var currentWeekEntries: [UTEntry] {
        entries(in: weekInterval(for: Date()))
    }

    var currentWeekDaySummaries: [UTDaySummary] {
        daySummaries(in: weekInterval(for: Date()))
    }

    func recentWeekSummaries(limit: Int = 6) -> [UTWeekSummary] {
        let currentWeekStart = weekInterval(for: Date()).start

        return (0..<limit).compactMap { offset in
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -offset, to: currentWeekStart) else {
                return nil
            }

            return weekSummary(weekStartingAt: weekStart)
        }
    }

    func addEntry(date: Date, hours: Double, note: String) {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDate = calendar.startOfDay(for: date)
        let entry = UTEntry(date: normalizedDate, hours: hours, note: trimmedNote)

        entries.append(entry)
        sortAndPersistEntries()
    }

    func deleteEntry(_ entry: UTEntry) {
        entries.removeAll { $0.id == entry.id }
        persistEntries()
    }

    func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
    }

    func weekdaySymbol(for date: Date) -> String {
        let weekdayIndex = calendar.component(.weekday, from: date) - 1
        let symbols = calendar.shortWeekdaySymbols
        guard weekdayIndex >= 0, weekdayIndex < symbols.count else { return "" }
        return symbols[weekdayIndex]
    }

    private func weekSummary(for date: Date) -> UTWeekSummary {
        weekSummary(weekStartingAt: weekInterval(for: date).start)
    }

    private func weekSummary(weekStartingAt weekStart: Date) -> UTWeekSummary {
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let intervalEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let interval = DateInterval(start: weekStart, end: intervalEnd)
        let totalHours = entries(in: interval).reduce(0) { $0 + $1.hours }

        return UTWeekSummary(weekStart: weekStart, weekEnd: weekEnd, totalHours: totalHours)
    }

    private func daySummaries(in weekInterval: DateInterval) -> [UTDaySummary] {
        (0..<7).compactMap { dayOffset in
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: weekInterval.start) else {
                return nil
            }

            let hours = entries.reduce(0) { partialResult, entry in
                partialResult + (calendar.isDate(entry.date, inSameDayAs: date) ? entry.hours : 0)
            }

            return UTDaySummary(date: date, hours: hours)
        }
    }

    private func entries(in weekInterval: DateInterval) -> [UTEntry] {
        entries
            .filter { weekInterval.contains($0.date) }
            .sorted(by: sortEntries(lhs:rhs:))
    }

    private func weekInterval(for date: Date) -> DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: date) ?? DateInterval(start: calendar.startOfDay(for: date), duration: 7 * 24 * 60 * 60)
    }

    private func sortAndPersistEntries() {
        entries.sort(by: sortEntries(lhs:rhs:))
        persistEntries()
    }

    private func sortEntries(lhs: UTEntry, rhs: UTEntry) -> Bool {
        if calendar.isDate(lhs.date, inSameDayAs: rhs.date) {
            return lhs.createdAt > rhs.createdAt
        }

        return lhs.date > rhs.date
    }

    private func loadEntries() {
        guard let data = userDefaults.data(forKey: storageKey),
              let storedEntries = try? JSONDecoder().decode([UTEntry].self, from: data) else {
            entries = []
            return
        }

        entries = storedEntries.sorted(by: sortEntries(lhs:rhs:))
    }

    private func persistEntries() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        userDefaults.set(data, forKey: storageKey)
    }
}

private extension Calendar {
    static let utTracker: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .autoupdatingCurrent
        calendar.timeZone = .autoupdatingCurrent
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }()
}
