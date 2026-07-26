import SwiftUI
import WidgetKit

struct SearchWidgetEntry: TimelineEntry {
    let date: Date
}

struct SearchWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SearchWidgetEntry {
        SearchWidgetEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (SearchWidgetEntry) -> Void) {
        completion(SearchWidgetEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SearchWidgetEntry>) -> Void) {
        completion(Timeline(entries: [SearchWidgetEntry(date: Date())], policy: .never))
    }
}

struct SearchWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.blue)
                Text("EasySearch")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("搜索…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(Color.secondary.opacity(0.12))
            )

            if family == .systemMedium {
                Text("点击立即开始搜索,回车直达常用引擎")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "easysearch://search"))
    }
}

struct SearchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EasySearch.SearchWidget", provider: SearchWidgetProvider()) { _ in
            SearchWidgetView()
        }
        .configurationDisplayName("快速搜索")
        .description("一键进入搜索,键盘直接弹起。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
