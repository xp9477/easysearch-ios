import SwiftUI

public enum AppFeaturePlacement: String {
    case primaryTab
    case moduleList
    case hiddenModule
}

/// Represents a distinct feature or "mini-app" within the super app.
public protocol AppFeature: Identifiable {
    var id: String { get }
    var title: String { get }
    var summary: String { get }
    var iconName: String { get }
    var color: Color { get }
    var placement: AppFeaturePlacement { get }
    
    @MainActor
    @ViewBuilder
    var entryView: AnyView { get }
}

extension View {
    @ViewBuilder
    func appTabBarBehavior() -> some View {
        if #available(iOS 26.0, *) {
            tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
}
