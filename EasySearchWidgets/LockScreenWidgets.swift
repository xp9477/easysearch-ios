import SwiftUI
import WidgetKit

struct LockStatusEntry: TimelineEntry {
    let date: Date
    let utProgress: Double
    let utRemaining: Double
    let utTargetMet: Bool
    let trainingTodayLines: Int
    let overdueExpenses: Int
}

struct LockStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> LockStatusEntry {
        entry(now: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (LockStatusEntry) -> Void) {
        completion(entry(now: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LockStatusEntry>) -> Void) {
        let now = Date()
        let nextRefresh = now.addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry(now: now)], policy: .after(nextRefresh)))
    }

    private func entry(now: Date) -> LockStatusEntry {
        let summary = WidgetData.utSummary(now: now)
        return LockStatusEntry(
            date: now,
            utProgress: min(max(summary.targetProgress, 0), 1),
            utRemaining: summary.remainingToTarget,
            utTargetMet: summary.isTargetMet,
            trainingTodayLines: WidgetData.trainingTodayLineCount(now: now),
            overdueExpenses: WidgetData.overdueExpenseCount(now: now)
        )
    }
}

struct LockScreenStatusView: View {
    @Environment(\.widgetFamily) private var family

    let entry: LockStatusEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: entry.utProgress) {
                Text("UT")
            } currentValueLabel: {
                Text("\(Int((entry.utProgress * 100).rounded()))")
            }
            .gaugeStyle(.accessoryCircular)
            .containerBackground(.background, for: .widget)
            .widgetURL(URL(string: "easysearch://ut"))
        case .accessoryInline:
            (entry.overdueExpenses > 0
             ? Text("报销逾期 \(entry.overdueExpenses) 项")
             : Text("报销无逾期"))
                .containerBackground(.background, for: .widget)
                .widgetURL(URL(string: "easysearch://expense"))
        default:
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.utTargetMet
                     ? "UT 已达标"
                     : "UT 还差 \(WidgetData.hoursText(entry.utRemaining))h")
                    .font(.headline)
                Text(entry.trainingTodayLines > 0
                     ? "今天已练 \(entry.trainingTodayLines) 组"
                     : "今天还没训练")
                    .font(.caption)
                if entry.overdueExpenses > 0 {
                    Text("报销逾期 \(entry.overdueExpenses) 项")
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(.background, for: .widget)
            .widgetURL(URL(string: "easysearch://ut"))
        }
    }
}

struct LockScreenStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EasySearch.LockStatusWidget", provider: LockStatusProvider()) { entry in
            LockScreenStatusView(entry: entry)
        }
        .configurationDisplayName("今日状态")
        .description("锁屏查看 UT 进度、训练与报销状态。")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
