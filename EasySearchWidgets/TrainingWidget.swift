import AppIntents
import SwiftUI
import WidgetKit

struct TrainingWidgetEntry: TimelineEntry {
    let date: Date
    let todayLines: Int
    let monthDays: Int
    let hasHistory: Bool
}

struct TrainingWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TrainingWidgetEntry {
        entry(now: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (TrainingWidgetEntry) -> Void) {
        completion(entry(now: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TrainingWidgetEntry>) -> Void) {
        let now = Date()
        let nextRefresh = TrainingLogCalendar.calendar.date(byAdding: .hour, value: 1, to: now)
            ?? now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry(now: now)], policy: .after(nextRefresh)))
    }

    private func entry(now: Date) -> TrainingWidgetEntry {
        TrainingWidgetEntry(
            date: now,
            todayLines: WidgetData.trainingTodayLineCount(now: now),
            monthDays: WidgetData.trainingMonthDayCount(now: now),
            hasHistory: WidgetData.lastTrainedDay(before: now) != nil
        )
    }
}

struct TrainingWidgetView: View {
    let entry: TrainingWidgetEntry

    private var trainedToday: Bool { entry.todayLines > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: trainedToday ? "flame.fill" : "flame")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(trainedToday ? .red : .secondary)
                Text("训练")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            Text(trainedToday ? "今天 \(entry.todayLines) 组" : "今天还没练")
                .font(.footnote.weight(.semibold))

            Text("本月 \(entry.monthDays) 天")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Button(intent: RepeatLastWorkoutIntent()) {
                Text("重复上次")
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(!entry.hasHistory)
        }
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "easysearch://training"))
    }
}

struct TrainingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EasySearch.TrainingWidget", provider: TrainingWidgetProvider()) { entry in
            TrainingWidgetView(entry: entry)
        }
        .configurationDisplayName("训练打卡")
        .description("今日训练状态,一键重复上次动作。")
        .supportedFamilies([.systemSmall])
    }
}
