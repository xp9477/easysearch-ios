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
    case qingLong
    case webDAV
    case hiddenSpace
}

@MainActor
final class AppNavigationState: ObservableObject {
    @Published var selectedTab: AppTab = .search
    @Published var pendingSettingsRoute: SettingsRoute?
    /// 递增即触发搜索框聚焦(切到搜索 Tab / 深链进入时)。
    @Published var searchActivationToken = 0
    /// 深链带入的搜索词。
    @Published var pendingSearchQuery: String?
    /// 深链请求打开的工作台模块(feature id)。
    @Published var pendingWorkbenchFeatureID: String?

    func openSettings(_ route: SettingsRoute? = nil) {
        pendingSettingsRoute = route
        selectedTab = .settings
    }

    func activateSearch(query: String? = nil) {
        selectedTab = .search
        if let query, !query.isEmpty {
            pendingSearchQuery = query
        } else {
            searchActivationToken += 1
        }
    }

    func openWorkbenchModule(_ featureID: String) {
        selectedTab = .workbench
        pendingWorkbenchFeatureID = featureID
    }

    /// 统一处理 easysearch:// 深链(Widget / Quick Actions / 分享)。
    func handleDeepLink(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "easysearch" else { return false }
        switch url.host?.lowercased() {
        case "search":
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "q" })?.value
            activateSearch(query: query)
            return true
        case "ut":
            openWorkbenchModule("uttracker")
            return true
        case "training":
            openWorkbenchModule("training-log")
            return true
        case "expense":
            openWorkbenchModule("expense-assistant")
            return true
        default:
            return false
        }
    }
}

@main
struct EasySearchApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var registry = FeatureRegistry()
    @StateObject private var statusCenter = FeatureStatusCenter.shared

    init() {
        AppGroupStorage.rollbackToStandardIfNeeded()
        RemovedFeatureData.cleanup()
    }

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
                .onChange(of: scenePhase) { _, phase in
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

private enum RemovedFeatureData {
    static func cleanup(
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        [
            "search.history.v1",
            "email-assistant.persisted-state.v1",
            "email-assistant.persisted-state.v2",
            "email-assistant.persisted-state.v3",
            "imageTranslate.targetLanguage",
            "imageTranslate.ai.baseURL",
            "imageTranslate.deepseek.model"
        ].forEach { userDefaults.removeObject(forKey: $0) }

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let imageTranslateDirectory = appSupport
            .appendingPathComponent("EasySearch/ImageTranslate", isDirectory: true)
        try? fileManager.removeItem(at: imageTranslateDirectory)

        KeychainStore(service: "com.easysearch.image-translate")
            .delete(account: "ai.api-key.v1")
    }
}

private struct AppShellView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var searchViewModel = SearchViewModel()
    @StateObject private var navigationState = AppNavigationState()
    @StateObject private var shareInboxCoordinator = ShareInboxCoordinator()
    @ObservedObject private var shortcutRouter = AppShortcutRouter.shared

    var body: some View {
        TabView(selection: $navigationState.selectedTab) {
            Tab("搜索", systemImage: "magnifyingglass", value: AppTab.search) {
                EasySearchView(viewModel: searchViewModel)
            }

            Tab("工作台", systemImage: "square.grid.2x2", value: AppTab.workbench) {
                DashboardView(isTabActive: navigationState.selectedTab == .workbench)
            }

            Tab("设置", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
        .appTabBarBehavior()
        .environmentObject(navigationState)
        .task {
            shareInboxCoordinator.refreshIfNeeded()
            shortcutRouter.consume(into: navigationState)
            await searchViewModel.refreshConfigIfNeededOnLaunch()
        }
        .onChange(of: shortcutRouter.pendingShortcutType) { _, newValue in
            guard newValue != nil else { return }
            shortcutRouter.consume(into: navigationState)
        }
        .onOpenURL { url in
            if navigationState.handleDeepLink(url) { return }
            shareInboxCoordinator.handleIncomingURL(url)
        }
        .onChange(of: scenePhase) { _, phase in
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
