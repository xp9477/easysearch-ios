import SwiftUI

public struct UTTrackerFeature: AppFeature {
    public var id: String = "uttracker"
    public var title: String = "UT 记录"
    public var summary: String = "记录每周 UT，查看目标与进度。"
    public var iconName: String = "chart.bar.doc.horizontal"
    public var color: Color = Color(red: 0.31, green: 0.40, blue: 0.95)
    public var placement: AppFeaturePlacement = .moduleList
    public var group: AppFeatureGroup? = .recordsAndProgress

    public init() {}

    public var entryView: AnyView {
        AnyView(UTTrackerView())
    }
}
