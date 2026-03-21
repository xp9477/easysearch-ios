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
                addEntryCard
                if !viewModel.currentWeekEntries.isEmpty {
                    currentWeekEntriesCard
                }
                if !viewModel.entries.isEmpty {
                    recentWeeksCard
                }
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
        let exceededTargetHours = max(0, summary.totalHours - UTTrackerMetrics.targetHours)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("本周")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.primary)

                    Text(weekRangeText(for: summary))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(percentText(for: summary.fullWeekProgress))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }

            HStack(spacing: 8) {
                Text(summary.isTargetMet ? "已达标" : "待补足")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("\(hoursText(summary.totalHours)) / \(hoursText(UTTrackerMetrics.targetHours))h")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            progressBlock(
                title: "70% 目标",
                progress: summary.targetProgress,
                detail: summary.isTargetMet
                    ? "已达标，超出 \(hoursText(exceededTargetHours))h"
                    : "还差 \(hoursText(summary.remainingToTarget))h"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
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
            sectionHeader(title: "快速记录")

            quickDatePicker
            quickHourPresets
            hoursAdjuster
            projectedWeekProgressBanner

            TextField("备注（可选）", text: $draftNote, axis: .vertical)
                .lineLimit(3, reservesSpace: false)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                )

            Button(action: saveEntry) {
                Label(saveButtonTitle, systemImage: "plus.circle.fill")
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

    private var quickDatePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("日期")
                    .font(.system(size: 15, weight: .semibold))

                Spacer()

                Text(selectedDateTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                dateShortcutButton(
                    title: "今天",
                    subtitle: dateShortcutSubtitle(for: Date()),
                    isSelected: Calendar.utTracker.isDateInToday(selectedDate)
                ) {
                    selectedDate = Date()
                }

                if let yesterday = Calendar.utTracker.date(byAdding: .day, value: -1, to: Date()) {
                    dateShortcutButton(
                        title: "昨天",
                        subtitle: dateShortcutSubtitle(for: yesterday),
                        isSelected: Calendar.utTracker.isDateInYesterday(selectedDate)
                    ) {
                        selectedDate = yesterday
                    }
                }
            }

            DatePicker("手动选择", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.compact)
        }
    }

    private var quickHourPresets: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("常用工时")
                .font(.system(size: 15, weight: .semibold))

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 72), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(quickHourOptions, id: \.self) { hours in
                    presetButton(
                        title: "\(hoursText(hours))h",
                        isSelected: draftHours == hours
                    ) {
                        draftHours = hours
                    }
                }

                if let remainingSuggestion = remainingSuggestionHours {
                    presetButton(
                        title: "补齐 \(hoursText(remainingSuggestion))h",
                        isSelected: draftHours == remainingSuggestion
                    ) {
                        draftHours = remainingSuggestion
                    }
                }
            }
        }
    }

    private var hoursAdjuster: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("工时微调")
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
    }

    private var projectedWeekProgressBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: projectedWeekTotalHours >= UTTrackerMetrics.targetHours ? "checkmark.seal.fill" : "scope")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(projectedWeekTotalHours >= UTTrackerMetrics.targetHours ? .green : .orange)

            Text(projectedWeekLabel)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Text(projectedWeekSummaryText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    (projectedWeekTotalHours >= UTTrackerMetrics.targetHours ? Color.green : Color.orange)
                        .opacity(0.12)
                )
        )
    }

    private var currentWeekEntriesCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "本周记录", detail: "\(viewModel.currentWeekEntries.count) 条")

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
        .padding(24)
        .cardStyle()
    }

    private var recentWeeksCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "近 4 周")

            VStack(spacing: 14) {
                ForEach(viewModel.recentWeekSummaries(limit: 4)) { summary in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(weekRangeText(for: summary))
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.primary)

                                Text(summary.isTargetMet ? "达标" : "差 \(hoursText(summary.remainingToTarget))h")
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

    private var quickHourOptions: [Double] {
        [4, 6, 8, 10]
    }

    private var selectedWeekSummary: UTWeekSummary {
        viewModel.summary(for: selectedDate)
    }

    private var projectedWeekTotalHours: Double {
        selectedWeekSummary.totalHours + draftHours
    }

    private var remainingSuggestionHours: Double? {
        let remaining = roundedToHalfHour(selectedWeekSummary.remainingToTarget)
        guard remaining >= 0.5, remaining <= 16, !quickHourOptions.contains(remaining) else {
            return nil
        }
        return remaining
    }

    private var projectedWeekSummaryText: String {
        "\(hoursText(projectedWeekTotalHours)) / \(hoursText(UTTrackerMetrics.targetHours))h"
    }

    private var projectedWeekLabel: String {
        viewModel.isInCurrentWeek(selectedDate) ? "本周" : "该周"
    }

    private var saveButtonTitle: String {
        "保存\(selectedDateTitle) \(hoursText(draftHours))h"
    }

    private var selectedDateTitle: String {
        if Calendar.utTracker.isDateInToday(selectedDate) {
            return "今天"
        }

        if Calendar.utTracker.isDateInYesterday(selectedDate) {
            return "昨天"
        }

        return selectedDate.formatted(.dateTime.month().day())
    }

    private func sectionHeader(title: String, detail: String? = nil) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)

            Spacer()

            if let detail {
                Text(detail)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func dateShortcutButton(
        title: String,
        subtitle: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? .green : .primary)

                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? Color.green.opacity(0.12) : Color(.tertiarySystemFill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? Color.green.opacity(0.35) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func presetButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? .green : .primary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isSelected ? Color.green.opacity(0.12) : Color(.tertiarySystemFill))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isSelected ? Color.green.opacity(0.35) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
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

    private func dateShortcutSubtitle(for date: Date) -> String {
        date.formatted(.dateTime.month().day().weekday(.abbreviated))
    }

    private func percentText(for progress: Double) -> String {
        let percent = progress * 100
        return percent.formatted(.number.precision(.fractionLength(0 ... 1))) + "%"
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private func roundedToHalfHour(_ hours: Double) -> Double {
        (hours * 2).rounded() / 2
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

#Preview {
    NavigationStack {
        UTTrackerView()
    }
}
