import AppIntents
import SwiftUI
import WidgetKit

struct UTWidgetEntry: TimelineEntry {
    let date: Date
    let totalHours: Double
    let targetHours: Double
    let remaining: Double
    let progress: Double
    let isTargetMet: Bool
    let loggedToday: Bool
}

struct UTWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> UTWidgetEntry {
        entry(now: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (UTWidgetEntry) -> Void) {
        completion(entry(now: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UTWidgetEntry>) -> Void) {
        let now = Date()
        let calendar = Calendar.utTracker
        let nextRefresh = calendar.date(byAdding: .hour, value: 1, to: now) ?? now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry(now: now)], policy: .after(nextRefresh)))
    }

    private func entry(now: Date) -> UTWidgetEntry {
        let summary = WidgetData.utSummary(now: now)
        return UTWidgetEntry(
            date: now,
            totalHours: summary.totalHours,
            targetHours: summary.targetHours,
            remaining: summary.remainingToTarget,
            progress: min(max(summary.targetProgress, 0), 1),
            isTargetMet: summary.isTargetMet,
            loggedToday: WidgetData.utLoggedToday(now: now)
        )
    }
}

struct UTProgressWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: UTWidgetEntry

    var body: some View {
        content
            .containerBackground(.background, for: .widget)
            .widgetURL(URL(string: "easysearch://ut"))
    }

    @ViewBuilder
    private var content: some View {
        HStack(spacing: 12) {
            progressRing

            VStack(alignment: .leading, spacing: 4) {
                Text("UT 记录")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(statusText)
                    .font(.footnote.weight(.semibold))
                    .minimumScaleFactor(0.8)

                Button(intent: LogUTHoursIntent()) {
                    Text(entry.loggedToday ? "已记录" : "+8h")
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
                .disabled(entry.loggedToday)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 7)
            Circle()
                .trim(from: 0, to: entry.progress)
                .stroke(
                    entry.isTargetMet ? Color.green : Color.orange,
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text("\(Int((entry.progress * 100).rounded()))%")
                .font(.caption2.weight(.bold).monospacedDigit())
        }
        .frame(width: 56, height: 56)
    }

    private var statusText: String {
        if entry.isTargetMet {
            return "已达标 \(WidgetData.hoursText(entry.totalHours))h"
        }
        return "还差 \(WidgetData.hoursText(entry.remaining))h"
    }
}

struct UTProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EasySearch.UTProgressWidget", provider: UTWidgetProvider()) { entry in
            UTProgressWidgetView(entry: entry)
        }
        .configurationDisplayName("UT 进度")
        .description("本月工时进度,一键补记今天 8 小时。")
        .supportedFamilies([.systemSmall])
    }
}
