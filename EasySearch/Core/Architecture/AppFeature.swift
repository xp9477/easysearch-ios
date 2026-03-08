import SwiftUI

/// Represents a distinct feature or "mini-app" within the super app.
public protocol AppFeature: Identifiable {
    var id: String { get }
    var title: String { get }
    var iconName: String { get }
    var color: Color { get }
    
    @ViewBuilder
    var entryView: AnyView { get }
}
