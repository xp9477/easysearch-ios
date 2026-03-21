import BackgroundTasks
import SwiftUI

enum AppTab: Hashable {
    case search
    case dashboard
    case settings
}

enum SettingsRoute: Hashable {
    case cloudSync
    case utTracker
    case gitHubUpdates
    case imageTranslate
    case emailAssistant
    case qingLong
}

@MainActor
final class AppNavigationState: ObservableObject {
    @Published var selectedTab: AppTab = .search
    @Published var pendingSettingsRoute: SettingsRoute?

    func openSettings(_ route: SettingsRoute? = nil) {
        pendingSettingsRoute = route
        selectedTab = .settings
    }
}

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
    @StateObject private var searchViewModel = SearchViewModel()
    @StateObject private var navigationState = AppNavigationState()

    var body: some View {
        TabView(selection: $navigationState.selectedTab) {
            EasySearchView(viewModel: searchViewModel)
                .tag(AppTab.search)
                .tabItem {
                    Label("搜索", systemImage: "magnifyingglass")
                }

            DashboardView(isTabActive: navigationState.selectedTab == .dashboard)
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
        .environmentObject(navigationState)
        .task {
            await searchViewModel.refreshConfigIfNeededOnLaunch()
        }
    }
}
