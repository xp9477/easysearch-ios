import BackgroundTasks
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
                    await GitHubUpdatesNotificationManager.shared.configure()
                    await HiddenCloudSyncViewModel.shared.prepareIfNeeded()
                    await GitHubUpdatesBackgroundRefreshManager.scheduleNextRefresh()
                }
                .onChange(of: scenePhase) { phase in
                    guard phase == .active else { return }
                    Task {
                        await UTNotificationManager.shared.refreshStateAndSchedules()
                        await GitHubUpdatesNotificationManager.shared.refreshAuthorizationStatus()
                        let summary = await GitHubUpdatesService.shared.refreshRepositories(trigger: .foreground)
                        if summary.didPersistChanges {
                            let repositories = await GitHubUpdatesService.shared.loadRepositories()
                            if !repositories.isEmpty {
                                await HiddenCloudSyncViewModel.shared.syncGitHubRepoWatchesIfPossible(repositories)
                            }
                        }
                        await HiddenCloudSyncViewModel.shared.syncIfPossible()
                        await GitHubUpdatesBackgroundRefreshManager.scheduleNextRefresh()
                    }
                }
        }
        .backgroundTask(.appRefresh(GitHubUpdatesBackgroundRefreshManager.taskIdentifier)) {
            await GitHubUpdatesBackgroundRefreshManager.handleBackgroundRefresh()
        }
    }
}

private struct AppShellView: View {
    private enum AppTab: Hashable {
        case search
        case dashboard
        case settings
    }

    @StateObject private var searchViewModel = SearchViewModel()
    @State private var selectedTab: AppTab = .search

    var body: some View {
        TabView(selection: $selectedTab) {
            EasySearchView(viewModel: searchViewModel)
                .tag(AppTab.search)
                .tabItem {
                    Label("搜索", systemImage: "magnifyingglass")
                }

            DashboardView(isTabActive: selectedTab == .dashboard)
                .tag(AppTab.dashboard)
                .tabItem {
                    Label("模块", systemImage: "square.grid.2x2")
                }

            SettingsView()
                .tag(AppTab.settings)
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
        }
        .appTabBarBehavior()
        .task {
            await searchViewModel.refreshConfigIfNeededOnLaunch()
        }
    }
}
