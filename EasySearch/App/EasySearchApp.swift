import SwiftUI

@main
struct EasySearchApp: App {
    @StateObject private var registry = FeatureRegistry()
    @StateObject private var router = AppRouter(initialDestination: "easysearch")

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(registry)
                .environmentObject(router)
                .tint(Color(red: 0.24, green: 0.47, blue: 0.96)) // EasySearch 蓝色主题
        }
    }
}
