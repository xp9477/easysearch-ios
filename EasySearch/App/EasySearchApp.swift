import SwiftUI

enum AppTab: Hashable {
    case search
    case workbench
    case settings
}

enum SettingsRoute: Hashable {
    case cloudSync
    case utTracker
    case expenseAssistant
    case imageTranslate
    case emailAssistant
    case qingLong
    case webDAV
    case hiddenSpace
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
    @StateObject private var statusCenter = FeatureStatusCenter.shared

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .environmentObject(registry)
                .environmentObject(statusCenter)
                .environmentObject(CloudSyncViewModel.shared)
                .tint(.blue)
                .onAppear {
                    statusCenter.attach(registry: registry)
                    ShareActionRegistry.register(WebDAVStoreShareAction())
                }
                .task {
                    statusCenter.attach(registry: registry)
                    ShareActionRegistry.register(WebDAVStoreShareAction())
                    await UTNotificationManager.shared.configure()
                    await UTNotificationManager.shared.refreshSchedulesIfAuthorized()
                    await ExpenseAssistantNotificationManager.shared.configure()
                    await ExpenseAssistantNotificationManager.shared.refreshSchedulesIfAuthorized()
                    await CloudSyncViewModel.shared.prepareIfNeeded()
                    await statusCenter.refresh()
                }
                .onChange(of: scenePhase) { phase in
                    guard phase == .active else { return }
                    Task {
                        await UTNotificationManager.shared.refreshStateAndSchedules()
                        await ExpenseAssistantNotificationManager.shared.refreshStateAndSchedules()
                        await CloudSyncViewModel.shared.syncIfPossible()
                        await statusCenter.refresh()
                    }
                }
        }
    }
}

private struct AppShellView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var searchViewModel = SearchViewModel()
    @StateObject private var navigationState = AppNavigationState()
    @StateObject private var shareInboxCoordinator = ShareInboxCoordinator()

    var body: some View {
        TabView(selection: $navigationState.selectedTab) {
            EasySearchView(viewModel: searchViewModel)
                .tag(AppTab.search)
                .tabItem {
                    Label("搜索", systemImage: "magnifyingglass")
                }

            DashboardView(isTabActive: navigationState.selectedTab == .workbench)
                .tag(AppTab.workbench)
                .tabItem {
                    Label("工作台", systemImage: "square.grid.2x2")
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
            shareInboxCoordinator.refreshIfNeeded()
            await searchViewModel.refreshConfigIfNeededOnLaunch()
        }
        .onOpenURL { url in
            shareInboxCoordinator.handleIncomingURL(url)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                shareInboxCoordinator.refreshIfNeeded()
            }
        }
        .sheet(item: $shareInboxCoordinator.presentedBatch) { batch in
            IncomingShareActionsView(items: batch.items) { _ in
                shareInboxCoordinator.consume(batch)
            }
        }
    }
}
