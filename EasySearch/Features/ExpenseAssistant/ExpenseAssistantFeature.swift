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

    @MainActor
    public func statusSummary() async -> FeatureStatusSummary {
        let expenseSnapshot = ExpenseAssistantLocalStore().loadSnapshot()
        let expenseAuth = ExpenseAssistantNotificationManager.shared.authorizationStatus
        let overdueMonthly = ExpenseAssistantReminderEngine.overdueMonthlyClaims(in: expenseSnapshot, asOf: Date())
        let overdueTravel = ExpenseAssistantReminderEngine.overdueTravelClaims(in: expenseSnapshot, asOf: Date())
        if expenseAuth == .denied {
            return FeatureStatusSummary(kind: .needsAuthorization, text: "通知未授权")
        }
        if expenseSnapshot.monthlyClaims.isEmpty && expenseSnapshot.travelClaims.isEmpty {
            return FeatureStatusSummary(kind: .empty, text: "暂无单据")
        }
        if !overdueMonthly.isEmpty || !overdueTravel.isEmpty {
            return FeatureStatusSummary(kind: .attentionNeeded, text: "有待处理")
        }
        return FeatureStatusSummary(kind: .ready, text: "跟踪中")
    }

}
