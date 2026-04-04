import Foundation
import UserNotifications

@MainActor
final class ExpenseAssistantNotificationManager: ObservableObject {
    static let shared = ExpenseAssistantNotificationManager()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let center: UNUserNotificationCenter
    private let store: any ExpenseAssistantStore
    private let calendar: Calendar
    private let dailyReminderPrefix = "expense-assistant.daily."

    private init(
        center: UNUserNotificationCenter = .current(),
        store: any ExpenseAssistantStore = ExpenseAssistantLocalStore(),
        calendar: Calendar = .expenseAssistant
    ) {
        self.center = center
        self.store = store
        self.calendar = calendar
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
            return "已开启报销提醒"
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
        authorizationStatus = await notificationSettings().authorizationStatus
    }

    func refreshSchedulesIfAuthorized() async {
        guard notificationsEnabled else {
            await removeManagedPendingRequests()
            return
        }

        await removeManagedPendingRequests()

        let snapshot = ExpenseAssistantReminderEngine.normalized(
            snapshot: store.loadSnapshot(),
            now: Date(),
            calendar: calendar
        )
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)

        for dayOffset in 0..<ExpenseAssistantReminderEngine.scheduleWindowDays {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday),
                  let reminderDate = ExpenseAssistantReminderEngine.reminderDate(for: day, calendar: calendar) else {
                continue
            }

            guard reminderDate > now,
                  let content = ExpenseAssistantReminderEngine.reminderContent(
                    in: snapshot,
                    asOf: reminderDate,
                    calendar: calendar
                  ) else {
                continue
            }

            let notificationContent = UNMutableNotificationContent()
            notificationContent.title = content.title
            notificationContent.body = content.body
            notificationContent.sound = .default

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)
            let request = UNNotificationRequest(
                identifier: dailyIdentifier(for: day),
                content: notificationContent,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )

            await add(request)
        }
    }

    private func dailyIdentifier(for day: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return "\(dailyReminderPrefix)\(year)-\(month)-\(day)"
    }

    private func removeManagedPendingRequests() async {
        let pendingRequests = await pendingNotificationRequests()
        let identifiers = pendingRequests
            .map(\.identifier)
            .filter { $0.hasPrefix(dailyReminderPrefix) }

        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
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
