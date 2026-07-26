import Foundation

@MainActor
final class UTTrackerViewModel: ObservableObject {
    @Published private(set) var entries: [UTEntry] = []
    @Published private var holidayCalendar: UTHolidayCalendar

    private let store: any UTTrackerEntryStore
    private let calendar: Calendar
    private let notificationCenter: NotificationCenter
    private let holidayStore: UTHolidayCalendarStore
    private var entriesDidChangeObserver: NSObjectProtocol?

    init(
        store: any UTTrackerEntryStore = UTTrackerLocalStore(),
        calendar: Calendar = .utTracker,
        notificationCenter: NotificationCenter = .default,
        holidayCalendar: UTHolidayCalendar? = nil,
        holidayStore: UTHolidayCalendarStore = UTHolidayCalendarStore()
    ) {
        self.store = store
        self.calendar = calendar
        self.notificationCenter = notificationCenter
        self.holidayStore = holidayStore
        self.holidayCalendar = holidayCalendar
            ?? holidayStore.cachedCalendar(for: Self.relevantHolidayYears(calendar: calendar), calendar: calendar)
        entriesDidChangeObserver = notificationCenter.addObserver(
            forName: .utTrackerEntriesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadFromStore()
        }
        loadEntries()
        Task { [weak self] in
            await self?.refreshHolidayCalendar()
        }
    }

    deinit {
        if let entriesDidChangeObserver {
            notificationCenter.removeObserver(entriesDidChangeObserver)
        }
    }

    var currentMonthSummary: UTMonthSummary {
        monthSummary(for: Date())
    }

    var currentMonthEntries: [UTEntry] {
        entries(in: monthInterval(for: Date()))
    }

    func summary(for date: Date) -> UTMonthSummary {
        monthSummary(for: date)
    }

    func isInCurrentMonth(_ date: Date) -> Bool {
        monthInterval(for: date).start == monthInterval(for: Date()).start
    }

    func recentMonthSummaries(limit: Int = 6) -> [UTMonthSummary] {
        let currentMonthStart = monthInterval(for: Date()).start

        return (0..<limit).compactMap { offset in
            guard let monthStart = calendar.date(byAdding: .month, value: -offset, to: currentMonthStart) else {
                return nil
            }

            return monthSummary(monthStartingAt: monthStart)
        }
    }

    func addEntry(date: Date, hours: Double, note: String) {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDate = calendar.startOfDay(for: date)
        let entry = UTEntry(date: normalizedDate, hours: hours, note: trimmedNote)

        entries.append(entry)
        sortAndPersistEntries()
        Task {
            await CloudSyncViewModel.shared.syncUTEntryUpsertIfPossible(entry)
            await UTNotificationManager.shared.refreshSchedulesIfAuthorized()
        }
    }

    func deleteEntry(_ entry: UTEntry) {
        entries.removeAll { $0.id == entry.id }
        persistEntries()
        Task {
            await CloudSyncViewModel.shared.syncUTEntryDeletionIfPossible(entry)
            await UTNotificationManager.shared.refreshSchedulesIfAuthorized()
        }
    }

    func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
    }

    private func monthSummary(for date: Date) -> UTMonthSummary {
        monthSummary(monthStartingAt: monthInterval(for: date).start, now: date)
    }

    private func monthSummary(monthStartingAt monthStart: Date, now: Date? = nil) -> UTMonthSummary {
        let interval = monthInterval(for: monthStart)
        let monthEnd = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? monthStart
        let summaryNow = now ?? monthEnd
        let elapsedEnd = min(interval.end, summaryNow.addingTimeInterval(1))
        let elapsedInterval = DateInterval(start: interval.start, end: elapsedEnd)
        let totalWorkingDays = calendar.utWorkingDays(in: interval, holidayCalendar: holidayCalendar)
        let elapsedWorkingDays = calendar.utWorkingDays(in: elapsedInterval, holidayCalendar: holidayCalendar)
        let totalHours = entries(in: interval)
            .filter { calendar.isUTWorkingDay($0.date, holidayCalendar: holidayCalendar) }
            .reduce(0) { $0 + $1.hours }

        return UTMonthSummary(
            monthStart: monthStart,
            monthEnd: monthEnd,
            totalHours: totalHours,
            elapsedWorkingDays: elapsedWorkingDays.count,
            totalWorkingDays: totalWorkingDays.count
        )
    }

    private func entries(in interval: DateInterval) -> [UTEntry] {
        entries
            .filter { interval.contains($0.date) }
            .sorted(by: sortEntries(lhs:rhs:))
    }

    private func monthInterval(for date: Date) -> DateInterval {
        calendar.dateInterval(of: .month, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 31 * 24 * 60 * 60)
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

    private func refreshHolidayCalendar() async {
        holidayCalendar = await holidayStore.refreshCalendar(
            for: Self.relevantHolidayYears(calendar: calendar),
            calendar: calendar
        )
    }

    private static func relevantHolidayYears(calendar: Calendar, now: Date = Date()) -> Set<Int> {
        let currentYear = calendar.component(.year, from: now)
        return [currentYear - 1, currentYear, currentYear + 1]
    }
}
