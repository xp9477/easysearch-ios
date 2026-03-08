import Foundation
import UserNotifications

@MainActor
final class UTNotificationManager: NSObject, ObservableObject {
    static let shared = UTNotificationManager()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let center: UNUserNotificationCenter
    private let userDefaults: UserDefaults
    private let calendar: Calendar
    private let dailyReminderPrefix = "ut.daily."
    private let weeklyReminderIdentifier = "ut.weekly.threshold"
    private let schedulingWindowDays = 30

    private override init() {
        center = .current()
        userDefaults = .standard
        calendar = .utTracker
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

        let entries = loadEntries()
        await scheduleDailyReminders(using: entries)
        await scheduleWeeklyThresholdReminder(using: entries)
    }

    private func scheduleDailyReminders(using entries: [UTEntry]) async {
        let now = Date()
        let today = calendar.startOfDay(for: now)

        for dayOffset in 0..<schedulingWindowDays {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today) else {
                continue
            }

            guard !hasEntry(on: day, within: entries) else {
                continue
            }

            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = 20
            components.minute = 0

            guard let triggerDate = calendar.date(from: components), triggerDate > now else {
                continue
            }

            let content = UNMutableNotificationContent()
            content.title = "填写今天的 UT"
            content.body = "今天的工作 UT 还没确认，记得补一下。"
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: dailyIdentifier(for: day),
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )

            await add(request)
        }
    }

    private func scheduleWeeklyThresholdReminder(using entries: [UTEntry]) async {
        let now = Date()
        let nextThursdayAtEight = nextThursdayReminderDate(after: now)

        guard let reminderDate = nextThursdayAtEight else {
            return
        }

        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: reminderDate)
            ?? DateInterval(start: calendar.startOfDay(for: reminderDate), duration: 7 * 24 * 60 * 60)

        let totalHours = entries
            .filter { weekInterval.contains($0.date) }
            .reduce(0) { $0 + $1.hours }

        guard totalHours < UTTrackerMetrics.weeklyWarningHours else {
            return
        }

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)

        let content = UNMutableNotificationContent()
        content.title = "本周 UT 还没到 60%"
        content.body = "现在还没达到 24h，记得检查并补录本周 UT。"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: weeklyReminderIdentifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )

        await add(request)
    }

    private func nextThursdayReminderDate(after now: Date) -> Date? {
        let components = DateComponents(hour: 20, minute: 0, weekday: 5)
        return calendar.nextDate(
            after: now,
            matching: components,
            matchingPolicy: .nextTime,
            direction: .forward
        )
    }

    private func hasEntry(on date: Date, within entries: [UTEntry]) -> Bool {
        entries.contains { calendar.isDate($0.date, inSameDayAs: date) }
    }

    private func loadEntries() -> [UTEntry] {
        guard let data = userDefaults.data(forKey: UTTrackerStorage.entriesKey),
              let storedEntries = try? JSONDecoder().decode([UTEntry].self, from: data) else {
            return []
        }

        return storedEntries
    }

    private func dailyIdentifier(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return "\(dailyReminderPrefix)\(year)-\(month)-\(day)"
    }

    private func removeManagedPendingRequests() async {
        let pendingRequests = await pendingNotificationRequests()
        let managedIdentifiers = pendingRequests
            .map(\.identifier)
            .filter { $0.hasPrefix(dailyReminderPrefix) || $0 == weeklyReminderIdentifier }

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
