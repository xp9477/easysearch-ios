import SwiftUI

public struct ExpenseAssistantFeature: AppFeature {
    public var id: String = "expense-assistant"
    public var title: String = "报销助手"
    public var summary: String = "跟踪月度报销和出差报销状态，并为逾期单据安排每日提醒。"
    public var iconName: String = "receipt"
    public var color: Color = .orange
    public var placement: AppFeaturePlacement = .moduleList

    public init() {}

    public var entryView: AnyView {
        AnyView(ExpenseAssistantView())
    }
}
