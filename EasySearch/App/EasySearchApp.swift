import SwiftUI

@main
struct EasySearchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var registry = FeatureRegistry()

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .environmentObject(registry)
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

private struct AppShellView: View {
    @StateObject private var searchViewModel = SearchViewModel()

    var body: some View {
        TabView {
            EasySearchView(viewModel: searchViewModel)
                .tabItem {
                    Label("搜索", systemImage: "magnifyingglass")
                }

            DashboardView()
                .tabItem {
                    Label("模块", systemImage: "square.grid.2x2")
                }

            SettingsView(viewModel: searchViewModel)
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
        }
        .appTabBarBehavior()
    }
}
