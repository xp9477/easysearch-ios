import SwiftUI

public struct TrainingLogFeature: AppFeature {
    public var id: String = "training-log"
    public var title: String = "训练记录"
    public var summary: String = "月历查看与徒手动作训练打卡。"
    public var iconName: String = "flame.fill"
    public var color: Color = Color(red: 0.95, green: 0.38, blue: 0.48)
    public var placement: AppFeaturePlacement = .moduleList
    public var group: AppFeatureGroup? = .recordsAndProgress

    public init() {}

    public var entryView: AnyView {
        AnyView(TrainingLogView())
    }
}
