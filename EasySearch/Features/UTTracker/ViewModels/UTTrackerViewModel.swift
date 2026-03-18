import Foundation

final class UTTrackerViewModel: ObservableObject {
    @Published private(set) var entries: [UTEntry] = []

    private let store: any UTTrackerEntryStore
    private let calendar: Calendar
    private let notificationCenter: NotificationCenter
    private var entriesDidChangeObserver: NSObjectProtocol?

    init(
        store: any UTTrackerEntryStore = UTTrackerLocalStore(),
        calendar: Calendar = .utTracker,
        notificationCenter: NotificationCenter = .default
    ) {
        self.store = store
        self.calendar = calendar
        self.notificationCenter = notificationCenter
        entriesDidChangeObserver = notificationCenter.addObserver(
            forName: .utTrackerEntriesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadFromStore()
        }
        loadEntries()
    }

    deinit {
        if let entriesDidChangeObserver {
            notificationCenter.removeObserver(entriesDidChangeObserver)
        }
    }

    var currentWeekSummary: UTWeekSummary {
        weekSummary(for: Date())
    }

    var currentWeekEntries: [UTEntry] {
        entries(in: weekInterval(for: Date()))
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
        Task {
            await HiddenCloudSyncViewModel.shared.syncUTEntryUpsertIfPossible(entry)
            await UTNotificationManager.shared.refreshSchedulesIfAuthorized()
        }
    }

    func deleteEntry(_ entry: UTEntry) {
        entries.removeAll { $0.id == entry.id }
        persistEntries()
        Task {
            await HiddenCloudSyncViewModel.shared.syncUTEntryDeletionIfPossible(entry)
            await UTNotificationManager.shared.refreshSchedulesIfAuthorized()
        }
    }

    func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
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
        entries = store.loadEntries().sorted(by: sortEntries(lhs:rhs:))
    }

    private func persistEntries() {
        store.saveEntries(entries)
    }

    private func reloadFromStore() {
        let reloaded = store.loadEntries().sorted(by: sortEntries(lhs:rhs:))
        guard reloaded != entries else { return }
        entries = reloaded
    }
}

extension Calendar {
    static let utTracker: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .autoupdatingCurrent
        calendar.timeZone = .autoupdatingCurrent
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }()
}
