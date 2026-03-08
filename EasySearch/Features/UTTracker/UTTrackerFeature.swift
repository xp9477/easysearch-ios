import SwiftUI

public struct UTTrackerFeature: AppFeature {
    public var id: String = "uttracker"
    public var title: String = "UT 记录"
    public var summary: String = "记录每周 UT，查看 70% 目标和 100% 满额进度。"
    public var iconName: String = "chart.bar.doc.horizontal"
    public var color: Color = .green
    public var placement: AppFeaturePlacement = .moduleList

    public init() {}

    public var entryView: AnyView {
        AnyView(UTTrackerView())
    }
}
