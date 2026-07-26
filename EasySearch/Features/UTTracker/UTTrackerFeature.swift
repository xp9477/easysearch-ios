import SwiftUI

public struct UTTrackerFeature: AppFeature {
    public var id: String = "uttracker"
    public var title: String = "UT 记录"
    public var summary: String = "记录每周 UT，查看目标与进度。"
    public var iconName: String = "chart.bar.doc.horizontal"
    public var color: Color = .indigo
    public var placement: AppFeaturePlacement = .moduleList
    public var group: AppFeatureGroup? = .recordsAndProgress

    public init() {}

    public var entryView: AnyView {
        AnyView(UTTrackerView())
    }

    @MainActor
    public func statusSummary() async -> FeatureStatusSummary {
        let utEntries = UTTrackerLocalStore().loadEntries()
        let utAuth = UTNotificationManager.shared.authorizationStatus
        if utAuth == .denied {
            return FeatureStatusSummary(kind: .needsAuthorization, text: "通知未授权")
        }
        if utEntries.isEmpty {
            return FeatureStatusSummary(kind: .empty, text: "暂无记录")
        }
        return FeatureStatusSummary(kind: .ready, text: "本月可记录")
    }

}
