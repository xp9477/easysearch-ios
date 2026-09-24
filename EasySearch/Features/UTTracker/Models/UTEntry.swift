import Foundation

enum UTTrackerMetrics {
    static let dailyReferenceHours: Double = 8
    static let targetRatio: Double = 0.7
    static let warningRatio: Double = 0.6
}

enum UTTrackerStorage {
    static let entriesKey = "ut_tracker_entries_v1"
    static let machinesKey = "ut_tracker_machines_v1"
    static let lastMachineKey = "ut_tracker_last_machine_v1"
    static let factoriesKey = "ut_tracker_factories_v1"
    static let factoryAssignmentsKey = "ut_tracker_machine_factories_v1"
    static let lastFactoryKey = "ut_tracker_last_factory_v1"
}

struct UTEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let date: Date
    let hours: Double
    let note: String
    let machine: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        date: Date,
        hours: Double,
        note: String,
        machine: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.hours = hours
        self.note = note
        self.machine = machine.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case date
        case hours
        case note
        case machine
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        hours = try container.decode(Double.self, forKey: .hours)
        note = try container.decode(String.self, forKey: .note)
        let rawMachine = try container.decodeIfPresent(String.self, forKey: .machine) ?? ""
        machine = rawMachine.trimmingCharacters(in: .whitespacesAndNewlines)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encode(hours, forKey: .hours)
        try container.encode(note, forKey: .note)
        try container.encode(machine, forKey: .machine)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

struct UTMachineDurationTotal: Identifiable, Hashable {
    let machine: String
    let totalHours: Double
    var id: String { machine }
}

enum UTMachineDuration {
    static func totals(
        entries: [UTEntry],
        machines: [String] = [],
        now: Date = Date(),
        calendar: Calendar = .utTracker
    ) -> [UTMachineDurationTotal] {
        let startOfToday = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .year, value: -1, to: startOfToday),
              let nextDayStart = calendar.date(byAdding: .day, value: 1, to: startOfToday) else {
            return []
        }

        var hoursByMachine: [String: Double] = [:]
        for m in machines {
            let trimmed = m.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            hoursByMachine[trimmed] = 0
        }
        for entry in entries {
            guard entry.date >= windowStart && entry.date < nextDayStart else { continue }
            let trimmedMachine = entry.machine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedMachine.isEmpty else { continue }
            hoursByMachine[trimmedMachine, default: 0] += entry.hours
        }

        return hoursByMachine
            .map { UTMachineDurationTotal(machine: $0.key, totalHours: $0.value) }
            .sorted { lhs, rhs in
                if lhs.totalHours != rhs.totalHours {
                    return lhs.totalHours > rhs.totalHours
                }
                return lhs.machine < rhs.machine
            }
    }
}

struct UTFactoryHoursGroup: Identifiable, Hashable {
    let factory: String
    let totals: [UTMachineDurationTotal]
    var id: String { factory }
    var totalHours: Double { totals.reduce(0) { $0 + $1.totalHours } }
}

enum UTFactoryLayout {
    static let defaultFactories = ["一厂", "二厂"]

    static func groups(
        factories: [String],
        machines: [String],
        assignments: [String: String],
        entries: [UTEntry],
        now: Date = Date(),
        calendar: Calendar = .utTracker
    ) -> [UTFactoryHoursGroup] {
        let effectiveFactories = normalizeFactories(factories)
        let firstFactory = effectiveFactories[0]

        let durationTotals = UTMachineDuration.totals(entries: entries, now: now, calendar: calendar)
        let hoursByMachine = Dictionary(uniqueKeysWithValues: durationTotals.map { ($0.machine, $0.totalHours) })

        var allMachines: [String] = []
        var seenMachines = Set<String>()
        for m in machines {
            let trimmed = m.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && seenMachines.insert(trimmed).inserted {
                allMachines.append(trimmed)
            }
        }
        for e in entries {
            let trimmed = e.machine.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && seenMachines.insert(trimmed).inserted {
                allMachines.append(trimmed)
            }
        }

        func factoryForMachine(_ machine: String) -> String {
            if let assigned = assignments[machine], effectiveFactories.contains(assigned) {
                return assigned
            }
            return firstFactory
        }

        return effectiveFactories.map { factory in
            let factoryMachines = allMachines.filter { factoryForMachine($0) == factory }
            let groupTotals = factoryMachines
                .map { UTMachineDurationTotal(machine: $0, totalHours: hoursByMachine[$0] ?? 0.0) }
                .sorted { lhs, rhs in
                    if lhs.totalHours != rhs.totalHours {
                        return lhs.totalHours > rhs.totalHours
                    }
                    return lhs.machine < rhs.machine
                }
            return UTFactoryHoursGroup(factory: factory, totals: groupTotals)
        }
    }

    static func normalizeFactories(_ factories: [String]) -> [String] {
        let cleaned = factories
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if cleaned.count == 2 && cleaned[0] != cleaned[1] {
            return cleaned
        }

        var result: [String] = []
        var seen = Set<String>()
        for f in cleaned {
            if seen.insert(f).inserted {
                result.append(f)
                if result.count == 2 { break }
            }
        }
        for def in defaultFactories {
            if result.count == 2 { break }
            if seen.insert(def).inserted {
                result.append(def)
            }
        }
        return result.count == 2 ? result : defaultFactories
    }
}


struct UTHolidayCalendar: Codable, Hashable {
    let holidays: Set<Date>
    let makeupWorkdays: Set<Date>

    static let empty = UTHolidayCalendar(holidays: [], makeupWorkdays: [])

    func merging(_ other: UTHolidayCalendar) -> UTHolidayCalendar {
        UTHolidayCalendar(
            holidays: holidays.union(other.holidays),
            makeupWorkdays: makeupWorkdays.union(other.makeupWorkdays)
        )
    }

    static func chinaPRC2026(calendar: Calendar = .utTracker) -> UTHolidayCalendar {
        func days(_ values: [String]) -> Set<Date> {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            return Set(values.compactMap { formatter.date(from: $0) }.map { calendar.startOfDay(for: $0) })
        }

        return UTHolidayCalendar(
            holidays: days([
                "2026-01-01", "2026-01-02", "2026-01-03",
                "2026-02-15", "2026-02-16", "2026-02-17", "2026-02-18", "2026-02-19", "2026-02-20", "2026-02-21", "2026-02-22", "2026-02-23",
                "2026-04-04", "2026-04-05", "2026-04-06",
                "2026-05-01", "2026-05-02", "2026-05-03", "2026-05-04", "2026-05-05",
                "2026-06-19", "2026-06-20", "2026-06-21",
                "2026-09-25", "2026-09-26", "2026-09-27",
                "2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04", "2026-10-05", "2026-10-06", "2026-10-07"
            ]),
            makeupWorkdays: days([
                "2026-01-04",
                "2026-02-14", "2026-02-28",
                "2026-05-09",
                "2026-09-20",
                "2026-10-10"
            ])
        )
    }
}

struct UTHolidayCalendarStore {
    private struct RemotePayload: Decodable {
        struct Day: Decodable {
            let date: String
            let isOffDay: Bool
        }

        let year: Int
        let days: [Day]
    }

    private let userDefaults: UserDefaults
    private let session: URLSession

    init(userDefaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.userDefaults = userDefaults
        self.session = session
    }

    func cachedCalendar(for years: Set<Int>, calendar: Calendar = .utTracker) -> UTHolidayCalendar {
        years.reduce(into: .empty) { result, year in
            let yearCalendar = cachedCalendar(for: year) ?? fallbackCalendar(for: year, calendar: calendar)
            result = result.merging(yearCalendar)
        }
    }

    func refreshCalendar(for years: Set<Int>, calendar: Calendar = .utTracker) async -> UTHolidayCalendar {
        var result = UTHolidayCalendar.empty

        for year in years.sorted() {
            let yearCalendar: UTHolidayCalendar
            do {
                yearCalendar = try await fetchCalendar(for: year, calendar: calendar)
                cache(yearCalendar, for: year)
            } catch {
                yearCalendar = cachedCalendar(for: year) ?? fallbackCalendar(for: year, calendar: calendar)
            }
            result = result.merging(yearCalendar)
        }

        return result
    }

    private func fetchCalendar(for year: Int, calendar: Calendar) async throws -> UTHolidayCalendar {
        let url = URL(string: "https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/\(year).json")!
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let payload = try JSONDecoder().decode(RemotePayload.self, from: data)
        guard payload.year == year else {
            throw URLError(.cannotParseResponse)
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        var holidays = Set<Date>()
        var makeupWorkdays = Set<Date>()
        for item in payload.days {
            guard let date = formatter.date(from: item.date) else { continue }
            let day = calendar.startOfDay(for: date)
            if item.isOffDay {
                holidays.insert(day)
            } else {
                makeupWorkdays.insert(day)
            }
        }

        guard !holidays.isEmpty || !makeupWorkdays.isEmpty else {
            throw URLError(.cannotParseResponse)
        }
        return UTHolidayCalendar(holidays: holidays, makeupWorkdays: makeupWorkdays)
    }

    private func cachedCalendar(for year: Int) -> UTHolidayCalendar? {
        guard let data = userDefaults.data(forKey: cacheKey(for: year)) else { return nil }
        return try? JSONDecoder().decode(UTHolidayCalendar.self, from: data)
    }

    private func cache(_ holidayCalendar: UTHolidayCalendar, for year: Int) {
        guard let data = try? JSONEncoder().encode(holidayCalendar) else { return }
        userDefaults.set(data, forKey: cacheKey(for: year))
    }

    private func cacheKey(for year: Int) -> String {
        "ut_holiday_calendar_\(year)_v1"
    }

    private func fallbackCalendar(for year: Int, calendar: Calendar) -> UTHolidayCalendar {
        year == 2026 ? .chinaPRC2026(calendar: calendar) : .empty
    }
}

struct UTMonthSummary: Identifiable, Hashable {
    let monthStart: Date
    let monthEnd: Date
    let totalHours: Double
    let elapsedWorkingDays: Int
    let totalWorkingDays: Int

    var id: Date { monthStart }

    var elapsedMonthHours: Double {
        Double(elapsedWorkingDays) * UTTrackerMetrics.dailyReferenceHours
    }

    var fullMonthHours: Double {
        Double(totalWorkingDays) * UTTrackerMetrics.dailyReferenceHours
    }

    var targetHours: Double {
        elapsedMonthHours * UTTrackerMetrics.targetRatio
    }

    var targetProgress: Double {
        guard targetHours > 0 else { return 0 }
        return totalHours / targetHours
    }

    var elapsedMonthProgress: Double {
        guard elapsedMonthHours > 0 else { return 0 }
        return totalHours / elapsedMonthHours
    }

    var fullMonthProgress: Double {
        guard fullMonthHours > 0 else { return 0 }
        return totalHours / fullMonthHours
    }

    var remainingToTarget: Double {
        max(0, targetHours - totalHours)
    }

    var isTargetMet: Bool {
        totalHours >= targetHours
    }
}

enum UTTrackerSnapshot {
    static func currentMonthSummary(
        userDefaults: UserDefaults = .standard,
        calendar: Calendar = .utTracker,
        now: Date = Date(),
        holidayCalendar: UTHolidayCalendar? = nil
    ) -> UTMonthSummary {
        let year = calendar.component(.year, from: now)
        let effectiveHolidayCalendar = holidayCalendar
            ?? UTHolidayCalendarStore(userDefaults: userDefaults).cachedCalendar(for: [year], calendar: calendar)
        let monthInterval = calendar.dateInterval(of: .month, for: now)
            ?? DateInterval(start: calendar.startOfDay(for: now), duration: 31 * 24 * 60 * 60)
        let monthStart = monthInterval.start
        let monthEnd = calendar.date(byAdding: .day, value: -1, to: monthInterval.end) ?? monthStart
        let elapsedInterval = DateInterval(start: monthStart, end: min(monthInterval.end, now.addingTimeInterval(1)))

        let totalHours = UTTrackerLocalStore(userDefaults: userDefaults)
            .loadEntries()
            .filter { monthInterval.contains($0.date) && calendar.isUTWorkingDay($0.date, holidayCalendar: effectiveHolidayCalendar) }
            .reduce(0) { $0 + $1.hours }

        return UTMonthSummary(
            monthStart: monthStart,
            monthEnd: monthEnd,
            totalHours: totalHours,
            elapsedWorkingDays: calendar.utWorkingDays(in: elapsedInterval, holidayCalendar: effectiveHolidayCalendar).count,
            totalWorkingDays: calendar.utWorkingDays(in: monthInterval, holidayCalendar: effectiveHolidayCalendar).count
        )
    }
}

extension Calendar {
    func isUTWorkingDay(_ date: Date, holidayCalendar: UTHolidayCalendar? = nil) -> Bool {
        let day = startOfDay(for: date)
        if let holidayCalendar {
            if holidayCalendar.makeupWorkdays.contains(day) {
                return true
            }
            if holidayCalendar.holidays.contains(day) {
                return false
            }
        }
        return !isDateInWeekend(day)
    }

    func utWorkingDays(in interval: DateInterval, holidayCalendar: UTHolidayCalendar? = nil) -> [Date] {
        var result: [Date] = []
        var day = startOfDay(for: interval.start)
        while day < interval.end {
            if isUTWorkingDay(day, holidayCalendar: holidayCalendar) {
                result.append(day)
            }
            guard let nextDay = date(byAdding: .day, value: 1, to: day) else { break }
            day = nextDay
        }
        return result
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
