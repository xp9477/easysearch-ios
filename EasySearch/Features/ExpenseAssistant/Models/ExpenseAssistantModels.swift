import Foundation

enum ExpenseAssistantStorage {
    static let snapshotKey = "expense_assistant.snapshot.v1"
}

extension Notification.Name {
    static let expenseAssistantDataDidChange = Notification.Name("expenseAssistantDataDidChange")
}

enum ExpenseClaimItemStatus: String, Codable, CaseIterable, Hashable, Identifiable {
    case pending
    case completed
    case notNeeded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pending:
            return "未开始"
        case .completed:
            return "已完成"
        case .notNeeded:
            return "不需要"
        }
    }

    var isResolved: Bool {
        self != .pending
    }
}

enum TravelApprovalStatus: String, Codable, CaseIterable, Hashable, Identifiable {
    case pending
    case submitted
    case approved

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pending:
            return "未开始"
        case .submitted:
            return "已提交"
        case .approved:
            return "已通过"
        }
    }

    var isResolved: Bool {
        self == .approved
    }
}

enum MonthlyExpenseField: String, CaseIterable, Hashable, Identifiable {
    case taxi
    case parking
    case phoneBill
    case misc

    var id: String { rawValue }

    var title: String {
        switch self {
        case .taxi:
            return "打车费"
        case .parking:
            return "停车费"
        case .phoneBill:
            return "手机话费"
        case .misc:
            return "杂费"
        }
    }
}

enum TravelExpenseField: String, CaseIterable, Hashable, Identifiable {
    case perDiem
    case expense

    var id: String { rawValue }

    var title: String {
        switch self {
        case .perDiem:
            return "Per Diem"
        case .expense:
            return "Expense"
        }
    }
}

struct MonthlyExpenseClaim: Identifiable, Codable, Hashable {
    let id: String
    let monthStart: Date
    var taxi: ExpenseClaimItemStatus
    var parking: ExpenseClaimItemStatus
    var phoneBill: ExpenseClaimItemStatus
    var misc: ExpenseClaimItemStatus

    init(
        monthStart: Date,
        calendar: Calendar = .expenseAssistant,
        taxi: ExpenseClaimItemStatus = .pending,
        parking: ExpenseClaimItemStatus = .pending,
        phoneBill: ExpenseClaimItemStatus = .pending,
        misc: ExpenseClaimItemStatus = .pending
    ) {
        let normalizedMonthStart = calendar.expenseMonthStart(for: monthStart)
        self.id = Self.makeID(for: normalizedMonthStart, calendar: calendar)
        self.monthStart = normalizedMonthStart
        self.taxi = taxi
        self.parking = parking
        self.phoneBill = phoneBill
        self.misc = misc
    }

    var isCompleted: Bool {
        statuses.allSatisfy(\.isResolved)
    }

    var completedItemCount: Int {
        statuses.filter(\.isResolved).count
    }

    var statuses: [ExpenseClaimItemStatus] {
        [taxi, parking, phoneBill, misc]
    }

    static func makeID(for monthStart: Date, calendar: Calendar = .expenseAssistant) -> String {
        let components = calendar.dateComponents([.year, .month], from: monthStart)
        let year = components.year ?? 0
        let month = components.month ?? 0
        return String(format: "%04d-%02d", year, month)
    }

    func status(for field: MonthlyExpenseField) -> ExpenseClaimItemStatus {
        switch field {
        case .taxi:
            return taxi
        case .parking:
            return parking
        case .phoneBill:
            return phoneBill
        case .misc:
            return misc
        }
    }

    mutating func setStatus(_ status: ExpenseClaimItemStatus, for field: MonthlyExpenseField) {
        switch field {
        case .taxi:
            taxi = status
        case .parking:
            parking = status
        case .phoneBill:
            phoneBill = status
        case .misc:
            misc = status
        }
    }
}

struct TravelExpenseClaim: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var startDate: Date
    var endDate: Date?
    var travelApprovalStatus: TravelApprovalStatus
    var perDiemStatus: ExpenseClaimItemStatus
    var expenseStatus: ExpenseClaimItemStatus
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "",
        startDate: Date,
        endDate: Date? = nil,
        travelApprovalStatus: TravelApprovalStatus = .pending,
        perDiemStatus: ExpenseClaimItemStatus = .pending,
        expenseStatus: ExpenseClaimItemStatus = .pending,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.travelApprovalStatus = travelApprovalStatus
        self.perDiemStatus = perDiemStatus
        self.expenseStatus = expenseStatus
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var isCompleted: Bool {
        travelApprovalStatus.isResolved && perDiemStatus.isResolved && expenseStatus.isResolved
    }

    func status(for field: TravelExpenseField) -> ExpenseClaimItemStatus {
        switch field {
        case .perDiem:
            return perDiemStatus
        case .expense:
            return expenseStatus
        }
    }

    mutating func setStatus(_ status: ExpenseClaimItemStatus, for field: TravelExpenseField) {
        switch field {
        case .perDiem:
            perDiemStatus = status
        case .expense:
            expenseStatus = status
        }
    }

    func resolvedTitle(calendar: Calendar = .expenseAssistant) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTitle.isEmpty else {
            return trimmedTitle
        }

        let startText = ExpenseAssistantTextFormatter.dayText(startDate, calendar: calendar)
        if let endDate {
            let endText = ExpenseAssistantTextFormatter.dayText(endDate, calendar: calendar)
            return "\(startText) - \(endText) 出差"
        }

        return "\(startText) 出差"
    }
}

struct ExpenseAssistantSnapshot: Codable, Hashable {
    var monthlyClaims: [MonthlyExpenseClaim]
    var travelClaims: [TravelExpenseClaim]

    init(
        monthlyClaims: [MonthlyExpenseClaim] = [],
        travelClaims: [TravelExpenseClaim] = []
    ) {
        self.monthlyClaims = monthlyClaims
        self.travelClaims = travelClaims
    }
}

struct ExpenseAssistantReminderContent: Hashable {
    let title: String
    let body: String
}

enum ExpenseAssistantReminderEngine {
    static let reminderHour = 9
    static let reminderMinute = 0
    static let scheduleWindowDays = 30

    static func normalized(
        snapshot: ExpenseAssistantSnapshot,
        now: Date = Date(),
        calendar: Calendar = .expenseAssistant
    ) -> ExpenseAssistantSnapshot {
        var monthlyClaimsByID: [String: MonthlyExpenseClaim] = [:]

        for claim in snapshot.monthlyClaims {
            let normalizedClaim = MonthlyExpenseClaim(
                monthStart: claim.monthStart,
                calendar: calendar,
                taxi: claim.taxi,
                parking: claim.parking,
                phoneBill: claim.phoneBill,
                misc: claim.misc
            )
            monthlyClaimsByID[normalizedClaim.id] = normalizedClaim
        }

        for defaultClaim in generatedMonthlyClaims(through: now, calendar: calendar) {
            monthlyClaimsByID[defaultClaim.id] = monthlyClaimsByID[defaultClaim.id] ?? defaultClaim
        }

        let monthlyClaims = monthlyClaimsByID.values.sorted { lhs, rhs in
            lhs.monthStart > rhs.monthStart
        }
        let travelClaims = snapshot.travelClaims.sorted(by: travelSort(lhs:rhs:))

        return ExpenseAssistantSnapshot(monthlyClaims: monthlyClaims, travelClaims: travelClaims)
    }

    static func generatedMonthlyClaims(
        through now: Date,
        calendar: Calendar = .expenseAssistant
    ) -> [MonthlyExpenseClaim] {
        let startMonth = calendar.expenseStartMonth
        let currentMonth = calendar.expenseMonthStart(for: now)
        guard startMonth <= currentMonth else { return [] }

        var claims: [MonthlyExpenseClaim] = []
        var cursor = startMonth

        while cursor <= currentMonth {
            claims.append(MonthlyExpenseClaim(monthStart: cursor, calendar: calendar))
            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: cursor) else {
                break
            }
            cursor = nextMonth
        }

        return claims
    }

    static func overdueMonthlyClaims(
        in snapshot: ExpenseAssistantSnapshot,
        asOf referenceDate: Date,
        calendar: Calendar = .expenseAssistant
    ) -> [MonthlyExpenseClaim] {
        let normalizedSnapshot = normalized(snapshot: snapshot, now: referenceDate, calendar: calendar)
        let currentMonth = calendar.expenseMonthStart(for: referenceDate)

        return normalizedSnapshot.monthlyClaims
            .filter { $0.monthStart < currentMonth && !$0.isCompleted }
            .sorted { $0.monthStart < $1.monthStart }
    }

    static func overdueTravelClaims(
        in snapshot: ExpenseAssistantSnapshot,
        asOf referenceDate: Date,
        calendar: Calendar = .expenseAssistant
    ) -> [TravelExpenseClaim] {
        let normalizedSnapshot = normalized(snapshot: snapshot, now: referenceDate, calendar: calendar)

        return normalizedSnapshot.travelClaims
            .filter { claim in
                guard let endDate = claim.endDate else { return false }
                return endDate < referenceDate && !claim.isCompleted
            }
            .sorted { lhs, rhs in
                let lhsEndDate = lhs.endDate ?? lhs.startDate
                let rhsEndDate = rhs.endDate ?? rhs.startDate
                if lhsEndDate == rhsEndDate {
                    return travelSort(lhs: lhs, rhs: rhs)
                }
                return lhsEndDate < rhsEndDate
            }
    }

    static func reminderContent(
        in snapshot: ExpenseAssistantSnapshot,
        asOf reminderDate: Date,
        calendar: Calendar = .expenseAssistant
    ) -> ExpenseAssistantReminderContent? {
        let overdueMonthly = overdueMonthlyClaims(in: snapshot, asOf: reminderDate, calendar: calendar)
        let overdueTravel = overdueTravelClaims(in: snapshot, asOf: reminderDate, calendar: calendar)
        let totalCount = overdueMonthly.count + overdueTravel.count

        guard totalCount > 0 else { return nil }

        let title = "报销助手：\(totalCount) 项待处理"
        let summary = "月单 \(overdueMonthly.count) 项，出差 \(overdueTravel.count) 项"

        let examples = representativeItems(
            overdueMonthly: overdueMonthly,
            overdueTravel: overdueTravel,
            calendar: calendar
        )
        let examplesText = examples.joined(separator: "、")
        let remainingCount = max(0, totalCount - examples.count)

        var body = summary
        if !examplesText.isEmpty {
            body += "。待处理：\(examplesText)"
            if remainingCount > 0 {
                body += " 等 \(remainingCount) 项。"
            } else {
                body += "。"
            }
        }

        return ExpenseAssistantReminderContent(title: title, body: body)
    }

    static func nextReminderDate(
        in snapshot: ExpenseAssistantSnapshot,
        after now: Date,
        calendar: Calendar = .expenseAssistant
    ) -> Date? {
        let startOfToday = calendar.startOfDay(for: now)

        for dayOffset in 0..<scheduleWindowDays {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday),
                  let reminderDate = reminderDate(for: day, calendar: calendar) else {
                continue
            }

            guard reminderDate > now else { continue }
            if reminderContent(in: snapshot, asOf: reminderDate, calendar: calendar) != nil {
                return reminderDate
            }
        }

        return nil
    }

    static func reminderDate(for day: Date, calendar: Calendar = .expenseAssistant) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = reminderHour
        components.minute = reminderMinute
        return calendar.date(from: components)
    }

    private static func representativeItems(
        overdueMonthly: [MonthlyExpenseClaim],
        overdueTravel: [TravelExpenseClaim],
        calendar: Calendar
    ) -> [String] {
        let monthlyExamples = overdueMonthly.prefix(2).map {
            "\(ExpenseAssistantTextFormatter.monthText($0.monthStart, calendar: calendar)) 月度报销"
        }
        let remainingSlots = max(0, 2 - monthlyExamples.count)
        let travelExamples = overdueTravel.prefix(remainingSlots).map {
            $0.resolvedTitle(calendar: calendar)
        }
        return monthlyExamples + travelExamples
    }

    private static func travelSort(lhs: TravelExpenseClaim, rhs: TravelExpenseClaim) -> Bool {
        if lhs.startDate == rhs.startDate {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.startDate > rhs.startDate
    }
}

extension Calendar {
    static let expenseAssistant: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .autoupdatingCurrent
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }()

    var expenseStartMonth: Date {
        let components = DateComponents(year: 2026, month: 1, day: 1)
        return date(from: components).map(startOfDay(for:)) ?? startOfDay(for: Date())
    }

    func expenseMonthStart(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: DateComponents(year: components.year, month: components.month, day: 1))
            .map(startOfDay(for:))
            ?? startOfDay(for: date)
    }
}

private enum ExpenseAssistantTextFormatter {
    static func monthText(_ date: Date, calendar: Calendar) -> String {
        formatter(
            dateFormat: "y年M月",
            calendar: calendar
        ).string(from: date)
    }

    static func dayText(_ date: Date, calendar: Calendar) -> String {
        formatter(
            dateFormat: "M月d日",
            calendar: calendar
        ).string(from: date)
    }

    private static func formatter(dateFormat: String, calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .autoupdatingCurrent
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = dateFormat
        return formatter
    }
}
