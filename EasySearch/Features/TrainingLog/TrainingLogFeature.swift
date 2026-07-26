import SwiftUI

public struct TrainingLogFeature: AppFeature {
    public var id: String = "training-log"
    public var title: String = "训练记录"
    public var summary: String = "月历查看与徒手动作训练打卡。"
    public var iconName: String = "flame.fill"
    public var color: Color = .red
    public var placement: AppFeaturePlacement = .moduleList
    public var group: AppFeatureGroup? = .recordsAndProgress

    public init() {}

    public var entryView: AnyView {
        AnyView(TrainingLogView())
    }

    @MainActor
    public func statusSummary() async -> FeatureStatusSummary {
        let trainingSnapshot = TrainingLogLocalStore().loadSnapshot()
        let trainingMonthStart = TrainingLogCalendar.startOfMonth(Date())
        let trainingDaysThisMonth = trainingSnapshot.days.values.filter { day in
            day.hasTraining && TrainingLogCalendar.calendar.isDate(day.dayStart, equalTo: trainingMonthStart, toGranularity: .month)
        }.count
        if trainingSnapshot.days.values.contains(where: \.hasTraining) {
            return FeatureStatusSummary(
                kind: .ready,
                text: trainingDaysThisMonth > 0 ? "本月 \(trainingDaysThisMonth) 天" : "有历史"
            )
        }
        return FeatureStatusSummary(kind: .empty, text: "暂无训练")
    }

}
