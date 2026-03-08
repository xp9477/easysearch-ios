import SwiftUI

public struct UTTrackerView: View {
    @StateObject private var viewModel = UTTrackerViewModel()
    @State private var selectedDate = Date()
    @State private var draftHours = UTTrackerMetrics.dailyReferenceHours
    @State private var draftNote = ""

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                overviewCard
                dailyDistributionCard
                addEntryCard
                currentWeekEntriesCard
                recentWeeksCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("UT 记录")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var overviewCard: some View {
        let summary = viewModel.currentWeekSummary

        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("UT Tracker")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("本周 UT 进度")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.primary)

                Text(weekRangeText(for: summary))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(percentText(for: summary.fullProgress))
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("UT")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                metricBlock(title: "本周已记", value: "\(hoursText(summary.totalHours))h")
                metricBlock(title: "目标线", value: "\(hoursText(UTTrackerMetrics.targetHours))h")
                metricBlock(title: "满额线", value: "\(hoursText(UTTrackerMetrics.fullWeekHours))h")
            }

            VStack(spacing: 12) {
                progressBlock(
                    title: "70% 目标",
                    progress: summary.targetProgress,
                    detail: summary.isTargetMet
                        ? "已达标"
                        : "还差 \(hoursText(summary.remainingToTarget))h"
                )

                progressBlock(
                    title: "100% 满额",
                    progress: summary.fullProgress,
                    detail: summary.extraBeyondFull > 0
                        ? "超出 \(hoursText(summary.extraBeyondFull))h"
                        : "还差 \(hoursText(summary.remainingToFull))h"
                )
            }

            Text("按每周 40h = 100% 计算，公司要求 70%，也就是 28h。")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(.secondarySystemGroupedBackground),
                            Color.green.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var dailyDistributionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                eyebrow: "Week Breakdown",
                title: "本周每日分布",
                description: "按周一到周日汇总，单日参考值按 8h 展示。"
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.currentWeekDaySummaries) { summary in
                        UTDayColumn(
                            title: viewModel.weekdaySymbol(for: summary.date),
                            subtitle: dayLabel(for: summary.date),
                            hoursText: "\(hoursText(summary.hours))h",
                            progress: clamped(summary.hours / UTTrackerMetrics.dailyReferenceHours),
                            isToday: viewModel.isToday(summary.date)
                        )
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(24)
        .cardStyle()
    }

    private var addEntryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                eyebrow: "Add Entry",
                title: "新增记录",
                description: "按条目记录当天的 UT，允许同一天记录多条。"
            )

            DatePicker("日期", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.compact)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("工时")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text("\(hoursText(draftHours))h")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Stepper(value: $draftHours, in: 0.5...16, step: 0.5) {
                    Text("每次以 0.5h 增减")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("备注")
                    .font(.system(size: 15, weight: .semibold))

                TextField("项目 / 事项（可选）", text: $draftNote, axis: .vertical)
                    .lineLimit(3, reservesSpace: false)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.tertiarySystemFill))
                    )
            }

            Button(action: saveEntry) {
                Label("保存记录", systemImage: "plus.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(draftHours <= 0)
        }
        .padding(24)
        .cardStyle()
    }

    private var currentWeekEntriesCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                eyebrow: "This Week",
                title: "本周记录",
                description: viewModel.currentWeekEntries.isEmpty
                    ? "还没有记录，先补一条今天的 UT。"
                    : "共 \(viewModel.currentWeekEntries.count) 条记录。"
            )

            if viewModel.currentWeekEntries.isEmpty {
                emptyState(
                    icon: "doc.text.magnifyingglass",
                    title: "暂无本周记录",
                    description: "记录后会按周自动汇总，并同步更新目标进度。"
                )
            } else {
                VStack(spacing: 12) {
                    ForEach(viewModel.currentWeekEntries) { entry in
                        UTEntryRow(
                            title: entryTitle(for: entry),
                            subtitle: entry.note.isEmpty ? "未填写备注" : entry.note,
                            trailing: "\(hoursText(entry.hours))h",
                            deleteAction: {
                                viewModel.deleteEntry(entry)
                            }
                        )
                    }
                }
            }
        }
        .padding(24)
        .cardStyle()
    }

    private var recentWeeksCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                eyebrow: "Recent Weeks",
                title: "最近 6 周",
                description: "快速查看每周累计 UT，判断哪些周没有达标。"
            )

            VStack(spacing: 14) {
                ForEach(viewModel.recentWeekSummaries()) { summary in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(weekRangeText(for: summary))
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.primary)

                                Text(summary.isTargetMet ? "达到 70% 目标" : "距离目标还差 \(hoursText(summary.remainingToTarget))h")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(summary.isTargetMet ? .green : .secondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 4) {
                                Text("\(hoursText(summary.totalHours))h")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundStyle(.primary)

                                Text(percentText(for: summary.fullProgress))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        ProgressView(value: clamped(summary.fullProgress))
                            .tint(summary.isTargetMet ? .green : .orange)
                    }
                    .padding(.bottom, 2)
                }
            }
        }
        .padding(24)
        .cardStyle()
    }

    private func metricBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.42))
        )
    }

    private func progressBlock(title: String, progress: Double, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(detail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: clamped(progress))
                .tint(.green)
        }
    }

    private func sectionHeader(eyebrow: String, title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.primary)

            Text(description)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func emptyState(icon: String, title: String, description: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)

            Text(description)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.tertiarySystemFill))
        )
    }

    private func saveEntry() {
        viewModel.addEntry(date: selectedDate, hours: draftHours, note: draftNote)
        selectedDate = Date()
        draftHours = UTTrackerMetrics.dailyReferenceHours
        draftNote = ""
    }

    private func weekRangeText(for summary: UTWeekSummary) -> String {
        let start = summary.weekStart.formatted(.dateTime.month().day())
        let end = summary.weekEnd.formatted(.dateTime.month().day())
        return "\(start) - \(end)"
    }

    private func dayLabel(for date: Date) -> String {
        if viewModel.isToday(date) {
            return "今天"
        }

        return date.formatted(.dateTime.day())
    }

    private func entryTitle(for entry: UTEntry) -> String {
        if viewModel.isToday(entry.date) {
            return "今天"
        }

        return entry.date.formatted(.dateTime.month().day().weekday(.abbreviated))
    }

    private func hoursText(_ hours: Double) -> String {
        hours.formatted(.number.precision(.fractionLength(0 ... 1)))
    }

    private func percentText(for progress: Double) -> String {
        let percent = progress * 100
        return percent.formatted(.number.precision(.fractionLength(0 ... 1))) + "%"
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

private struct UTDayColumn: View {
    let title: String
    let subtitle: String
    let hoursText: String
    let progress: Double
    let isToday: Bool

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isToday ? .green : .primary)

                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 16, height: 64)

                if progress > 0 {
                    Capsule()
                        .fill(isToday ? Color.green : Color.green.opacity(0.72))
                        .frame(width: 16, height: max(8, 64 * progress))
                }
            }

            Text(hoursText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .frame(width: 68)
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isToday ? Color.green.opacity(0.08) : Color(.tertiarySystemFill))
        )
    }
}

private struct UTEntryRow: View {
    let title: String
    let subtitle: String
    let trailing: String
    let deleteAction: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 8) {
                Text(trailing)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.primary)

                Button(role: .destructive, action: deleteAction) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .bold))
                        .padding(8)
                }
                .buttonStyle(.borderless)
                .background(
                    Circle()
                        .fill(Color.red.opacity(0.12))
                )
                .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.tertiarySystemFill))
        )
    }
}

private extension View {
    func cardStyle() -> some View {
        background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

#Preview {
    NavigationStack {
        UTTrackerView()
    }
}
