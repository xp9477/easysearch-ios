import SwiftUI

@main
struct EasySearchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var registry = FeatureRegistry()
    @StateObject private var router = AppRouter(initialDestination: "easysearch")

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(registry)
                .environmentObject(router)
                .tint(Color(red: 0.24, green: 0.47, blue: 0.96)) // EasySearch 蓝色主题
                .task {
                    await UTNotificationManager.shared.configure()
                    await UTNotificationManager.shared.refreshSchedulesIfAuthorized()
                }
                .onChange(of: scenePhase) { phase in
                    guard phase == .active else { return }
                    Task {
                        await UTNotificationManager.shared.refreshStateAndSchedules()
                    }
                }
        }
    }
}
