import SwiftUI

public struct UtilitiesFeature: AppFeature {
    public var id: String = "utilities"
    public var title: String = "实用工具" // Utilities
    public var iconName: String = "hammer.fill"
    public var color: Color = .orange
    
    public init() {}
    
    public var entryView: AnyView {
        AnyView(UtilitiesView())
    }
}
