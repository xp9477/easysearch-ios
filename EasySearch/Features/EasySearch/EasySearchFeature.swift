import SwiftUI

public struct EasySearchFeature: AppFeature {
    public var id: String = "easysearch"
    public var title: String = "EasySearch"
    public var summary: String = "输入一次关键词，快速跳转到常用搜索平台。"
    public var iconName: String = "magnifyingglass"
    public var color: Color = .blue
    public var placement: AppFeaturePlacement = .primaryTab
    public var group: AppFeatureGroup? = nil
    
    public init() {}
    
    public var entryView: AnyView {
        AnyView(EasySearchView(viewModel: SearchViewModel()))
    }
}
