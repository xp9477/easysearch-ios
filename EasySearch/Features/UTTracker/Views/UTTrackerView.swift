import SwiftUI

public struct UTTrackerView: View {
    @StateObject private var viewModel = UTTrackerViewModel()
    @StateObject private var notificationManager = UTNotificationManager.shared
    @Environment(\.openURL) private var openURL
    @State private var selectedDate = Date()
    @State private var draftHours = UTTrackerMetrics.dailyReferenceHours
    @State private var draftNote = ""

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                overviewCard
                addEntryCard
                currentWeekEntriesCard
                recentWeeksCard
                notificationCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("UT 记录")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await notificationManager.configure()
        }
    }

    private var overviewCard: some View {
        let summary = viewModel.currentWeekSummary
        let exceededTargetHours = max(0, summary.totalHours - UTTrackerMetrics.targetHours)
        let weeklyProgressPercent = summary.totalHours / UTTrackerMetrics.fullWeekHours

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("UT Tracker")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("本周 UT 进度")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.primary)

                Text(weekRangeText(for: summary))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(percentText(for: weeklyProgressPercent))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(summary.isTargetMet ? "已达标" : "待补足")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                metricBlock(title: "本周已记", value: "\(hoursText(summary.totalHours))h")
                metricBlock(title: "70%目标", value: "\(hoursText(UTTrackerMetrics.targetHours))h")
                metricBlock(
                    title: summary.isTargetMet ? "超出目标" : "还差目标",
                    value: "\(hoursText(summary.isTargetMet ? exceededTargetHours : summary.remainingToTarget))h"
                )
            }

            progressBlock(
                title: "70% 目标",
                progress: summary.targetProgress,
                detail: summary.isTargetMet
                    ? "已达标，超出 \(hoursText(exceededTargetHours))h"
                    : "还差 \(hoursText(summary.remainingToTarget))h"
            )

            Text("按每周 40h = 100% 计算，公司要求 70%，也就是 28h。")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
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
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
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

    private var notificationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                eyebrow: "Notifications",
                title: "提醒通知",
                description: "每天 20:00 提醒填写当天 UT；每周四 20:00 若本周还没到 60%，再提醒一次。"
            )

            HStack(spacing: 12) {
                Image(systemName: notificationManager.notificationsEnabled ? "bell.badge.fill" : "bell.slash")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(notificationManager.notificationsEnabled ? .green : .secondary)

                Text(notificationManager.statusText)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()
            }

            switch notificationManager.authorizationStatus {
            case .notDetermined:
                Button {
                    Task {
                        await notificationManager.requestAuthorization()
                    }
                } label: {
                    Label("开启通知", systemImage: "bell.badge")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

            case .denied:
                Button {
                    guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(settingsURL)
                } label: {
                    Label("前往系统设置", systemImage: "gearshape")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)

            case .authorized, .provisional, .ephemeral:
                Button {
                    Task {
                        await notificationManager.refreshStateAndSchedules()
                    }
                } label: {
                    Label("重新整理提醒", systemImage: "arrow.clockwise")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
                .tint(.green)

            @unknown default:
                EmptyView()
            }
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

                                Text(summary.isTargetMet ? "已达标" : "未达标")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(summary.isTargetMet ? .green : .secondary)
                            }
                        }

                        ProgressView(value: clamped(summary.targetProgress))
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
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.42))
        )
    }

    private func progressBlock(title: String, progress: Double, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
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
