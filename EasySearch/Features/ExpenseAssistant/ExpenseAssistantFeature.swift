import SwiftUI

public struct ExpenseAssistantFeature: AppFeature {
    public var id: String = "expense-assistant"
    public var title: String = "报销助手"
    public var summary: String = "跟踪月度与出差报销，逾期提醒。"
    public var iconName: String = "receipt"
    public var color: Color = Color(red: 0.98, green: 0.55, blue: 0.20)
    public var placement: AppFeaturePlacement = .moduleList
    public var group: AppFeatureGroup? = .recordsAndProgress

    public init() {}

    public var entryView: AnyView {
        AnyView(ExpenseAssistantView())
    }
}
