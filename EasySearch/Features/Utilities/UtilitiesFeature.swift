import SwiftUI

public struct UtilitiesFeature: AppFeature {
    public var id: String = "utilities"
    public var title: String = "实用工具"
    public var summary: String = "收纳后续扩展的小工具，保持主搜索体验足够专注。"
    public var iconName: String = "hammer.fill"
    public var color: Color = .orange
    public var placement: AppFeaturePlacement = .moduleList
    
    public init() {}
    
    public var entryView: AnyView {
        AnyView(UtilitiesView())
    }
}
