import Foundation
import UserNotifications

@MainActor
final class UTNotificationManager: NSObject, ObservableObject {
    static let shared = UTNotificationManager()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let center: UNUserNotificationCenter
    private let userDefaults: UserDefaults
    private let calendar: Calendar
    private let holidayStore: UTHolidayCalendarStore
    private var holidayCalendar: UTHolidayCalendar
    private let thresholdReminderPrefix = "ut.threshold."
    private let schedulingWindowDays = 60

    private override init() {
        center = .current()
        userDefaults = .standard
        calendar = .utTracker
        holidayStore = UTHolidayCalendarStore()
        let currentYear = Calendar.utTracker.component(.year, from: Date())
        holidayCalendar = holidayStore.cachedCalendar(
            for: [currentYear, currentYear + 1],
            calendar: .utTracker
        )
        super.init()
    }

    var notificationsEnabled: Bool {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }

    var statusText: String {
        switch authorizationStatus {
        case .authorized:
            return "已开启提醒"
        case .provisional, .ephemeral:
            return "提醒已启用"
        case .denied:
            return "通知权限已关闭"
        case .notDetermined:
            return "尚未开启通知"
        @unknown default:
            return "通知状态未知"
        }
    }

    func configure() async {
        center.delegate = self
        await refreshAuthorizationStatus()
    }

    func requestAuthorization() async {
        do {
            let granted = try await requestAuthorization(options: [.alert, .sound])
            await refreshAuthorizationStatus()

            if granted {
                await refreshSchedulesIfAuthorized()
            }
        } catch {
            await refreshAuthorizationStatus()
        }
    }

    func refreshStateAndSchedules() async {
        await refreshAuthorizationStatus()
        await refreshSchedulesIfAuthorized()
    }

    func refreshAuthorizationStatus() async {
        let settings = await notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func refreshSchedulesIfAuthorized() async {
        guard notificationsEnabled else {
            await removeManagedPendingRequests()
            return
        }

        await removeManagedPendingRequests()
        holidayCalendar = await holidayStore.refreshCalendar(
            for: relevantHolidayYears(),
            calendar: calendar
        )
        await scheduleFridayAndSaturdayReminders(using: loadEntries())
    }

    private func scheduleFridayAndSaturdayReminders(using entries: [UTEntry]) async {
        let now = Date()
        let today = calendar.startOfDay(for: now)

        for dayOffset in 0..<schedulingWindowDays {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today) else {
                continue
            }

            let weekday = calendar.component(.weekday, from: day)
            guard weekday == 6 || weekday == 7 else {
                continue
            }

            let summary = monthSummary(for: day, entries: entries)
            guard !summary.isTargetMet else {
                continue
            }

            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = 20
            components.minute = 0

            guard let triggerDate = calendar.date(from: components), triggerDate > now else {
                continue
            }

            let content = UNMutableNotificationContent()
            content.title = weekday == 6 ? "周五检查本月 UT" : "周六补录本月 UT"
            content.body = "截至目前还差 \(hoursText(summary.remainingToTarget))h 达到本月阶段目标。"
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: thresholdIdentifier(for: day),
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )

            await add(request)
        }
    }

    private func monthSummary(for date: Date, entries: [UTEntry]) -> UTMonthSummary {
        let monthInterval = calendar.dateInterval(of: .month, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 31 * 24 * 60 * 60)
        let monthStart = monthInterval.start
        let monthEnd = calendar.date(byAdding: .day, value: -1, to: monthInterval.end) ?? monthStart
        let elapsedInterval = DateInterval(start: monthStart, end: min(monthInterval.end, date.addingTimeInterval(1)))
        let totalWorkingDays = calendar.utWorkingDays(in: monthInterval, holidayCalendar: holidayCalendar)
        let elapsedWorkingDays = calendar.utWorkingDays(in: elapsedInterval, holidayCalendar: holidayCalendar)
        let totalHours = entries
            .filter { monthInterval.contains($0.date) && calendar.isUTWorkingDay($0.date, holidayCalendar: holidayCalendar) }
            .reduce(0) { $0 + $1.hours }

        return UTMonthSummary(
            monthStart: monthStart,
            monthEnd: monthEnd,
            totalHours: totalHours,
            elapsedWorkingDays: elapsedWorkingDays.count,
            totalWorkingDays: totalWorkingDays.count
        )
    }

    private func loadEntries() -> [UTEntry] {
        guard let data = userDefaults.data(forKey: UTTrackerStorage.entriesKey),
              let storedEntries = try? JSONDecoder().decode([UTEntry].self, from: data) else {
            return []
        }

        return storedEntries
    }

    private func thresholdIdentifier(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return thresholdReminderPrefix + "\(year)-\(month)-\(day)"
    }

    private func hoursText(_ hours: Double) -> String {
        hours.formatted(.number.precision(.fractionLength(0 ... 1)))
    }

    private func relevantHolidayYears(now: Date = Date()) -> Set<Int> {
        let currentYear = calendar.component(.year, from: now)
        return [currentYear, currentYear + 1]
    }

    private func removeManagedPendingRequests() async {
        let pendingRequests = await pendingNotificationRequests()
        let managedIdentifiers = pendingRequests
            .map(\.identifier)
            .filter { $0.hasPrefix(thresholdReminderPrefix) }

        guard !managedIdentifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: managedIdentifiers)
    }

    private func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            center.requestAuthorization(options: options) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func notificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    private func pendingNotificationRequests() async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        }
    }

    private func add(_ request: UNNotificationRequest) async {
        await withCheckedContinuation { continuation in
            center.add(request) { _ in
                continuation.resume()
            }
        }
    }
}

extension UTNotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
