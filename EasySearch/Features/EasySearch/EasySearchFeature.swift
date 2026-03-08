import SwiftUI

public struct EasySearchFeature: AppFeature {
    public var id: String = "easysearch"
    public var title: String = "EasySearch"
    public var iconName: String = "magnifyingglass"
    public var color: Color = Color(red: 0.24, green: 0.47, blue: 0.96)
    
    public init() {}
    
    public var entryView: AnyView {
        AnyView(EasySearchView())
    }
}
