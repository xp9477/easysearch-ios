import SwiftUI

public struct UTTrackerFeature: AppFeature {
    public var id: String = "uttracker"
    public var title: String = "UT 记录"
    public var iconName: String = "chart.bar.doc.horizontal"
    public var color: Color = .green

    public init() {}

    public var entryView: AnyView {
        AnyView(UTTrackerView())
    }
}
