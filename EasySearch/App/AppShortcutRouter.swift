import SwiftUI
import UIKit

/// Quick Actions(图标长按)→ 深链路由。
@MainActor
final class AppShortcutRouter: ObservableObject {
    static let shared = AppShortcutRouter()

    @Published var pendingShortcutType: String?

    func handle(_ shortcutItem: UIApplicationShortcutItem) {
        pendingShortcutType = shortcutItem.type
    }

    func consume(into navigationState: AppNavigationState) {
        guard let type = pendingShortcutType else { return }
        pendingShortcutType = nil
        switch type {
        case "com.easysearch.shortcut.search":
            navigationState.activateSearch()
        case "com.easysearch.shortcut.ut":
            navigationState.openWorkbenchModule("uttracker")
        case "com.easysearch.shortcut.training":
            navigationState.openWorkbenchModule("training-log")
        case "com.easysearch.shortcut.expense":
            navigationState.openWorkbenchModule("expense-assistant")
        default:
            break
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if let shortcutItem = options.shortcutItem {
            Task { @MainActor in
                AppShortcutRouter.shared.handle(shortcutItem)
            }
        }
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        Task { @MainActor in
            AppShortcutRouter.shared.handle(shortcutItem)
            completionHandler(true)
        }
    }
}
