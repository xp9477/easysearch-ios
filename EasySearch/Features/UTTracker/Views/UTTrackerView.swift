import SwiftUI

public struct UTTrackerView: View {
    @StateObject private var viewModel = UTTrackerViewModel()
    @State private var selectedDate = Date()
    @State private var draftHours = UTTrackerMetrics.dailyReferenceHours
    @State private var draftNote = ""

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ESUI.sectionSpacing) {
                overviewCard
                addEntryCard
                if !viewModel.currentMonthEntries.isEmpty {
                    currentMonthEntriesCard
                }
                if !viewModel.entries.isEmpty {
                    recentMonthsCard
                }
            }
            .padding(.horizontal, ESUI.screenHorizontalPadding)
            .padding(.top, ESUI.Space.md)
            .padding(.bottom, ESUI.Space.xxl)
        }
        .esScreenBackground()
        .navigationTitle("UT 记录")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Overview

    private var overviewCard: some View {
        let summary = viewModel.currentMonthSummary
        let exceededTargetHours = max(0, summary.totalHours - summary.targetHours)

        return VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            HStack(alignment: .top, spacing: ESUI.Space.sm) {
                VStack(alignment: .leading, spacing: ESUI.Space.xxs) {
                    Text("本月")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(monthRangeText(for: summary))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: ESUI.Space.xs)

                Text(percentText(for: summary.fullMonthProgress))
                    .font(.system(.title, design: .rounded).weight(.semibold))
                    .foregroundStyle(.primary)
                    .accessibilityLabel("整月进度 \(percentText(for: summary.fullMonthProgress))")
            }

            HStack(spacing: ESUI.Space.xs) {
                ESStatusBadge(
                    text: summary.isTargetMet ? "已达标" : "待补足",
                    tone: summary.isTargetMet ? .success : .warning
                )

                Text("\(hoursText(summary.totalHours)) / \(hoursText(summary.targetHours))h")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            progressBlock(
                title: "70% 目标",
                progress: summary.targetProgress,
                detail: summary.isTargetMet
                    ? "已达标，超出 \(hoursText(exceededTargetHours))h"
                    : "还差 \(hoursText(summary.remainingToTarget))h",
                isMet: summary.isTargetMet
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .esCard()
    }

    // MARK: - Quick Log

    private var addEntryCard: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.md) {
            ESSectionHeader(title: "快速记录", subtitle: "选择日期与工时后保存")

            quickDatePicker
            quickHourPresets
            hoursAdjuster
            projectedMonthProgressBanner

            TextField("备注（可选）", text: $draftNote, axis: .vertical)
                .lineLimit(3, reservesSpace: false)
                .padding(.horizontal, ESUI.Space.sm)
                .padding(.vertical, ESUI.Space.sm)
                .background(
                    RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                        .fill(ESUI.fill)
                )

            Button(action: saveEntry) {
                Label(saveButtonTitle, systemImage: "plus.circle.fill")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, ESUI.Space.xs)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(draftHours <= 0)
        }
        .esCard()
    }

    private var quickDatePicker: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            HStack {
                Text("日期")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(selectedDateTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: ESUI.Space.xs) {
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
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            Text("常用工时")
                .font(.subheadline.weight(.semibold))

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 72), spacing: ESUI.Space.xs)],
                alignment: .leading,
                spacing: ESUI.Space.xs
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
        VStack(alignment: .leading, spacing: ESUI.Space.xs) {
            HStack {
                Text("工时微调")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(hoursText(draftHours))h")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Stepper(value: $draftHours, in: 0.5...16, step: 0.5) {
                Text("每次以 0.5h 增减")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var projectedMonthProgressBanner: some View {
        let summary = selectedMonthSummary
        let isProjectedTargetMet = projectedMonthTotalHours >= summary.targetHours

        return ESStatusBanner(
            title: "\(projectedMonthLabel)预估 \(projectedMonthSummaryText)",
            message: isProjectedTargetMet ? "保存后可达到 70% 目标" : "保存后仍未达标",
            systemImage: isProjectedTargetMet ? "checkmark.seal.fill" : "scope",
            tone: isProjectedTargetMet ? .success : .warning
        )
    }

    // MARK: - Entries

    private var currentMonthEntriesCard: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.md) {
            ESSectionHeader(
                title: "本月记录",
                trailing: "\(viewModel.currentMonthEntries.count)"
            )

            VStack(spacing: ESUI.Space.xs) {
                ForEach(viewModel.currentMonthEntries) { entry in
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
        .esCard()
    }

    private var recentMonthsCard: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.md) {
            ESSectionHeader(title: "近 4 月", subtitle: "按目标进度回顾")

            VStack(spacing: ESUI.Space.md) {
                ForEach(viewModel.recentMonthSummaries(limit: 4)) { summary in
                    VStack(alignment: .leading, spacing: ESUI.Space.xs) {
                        HStack(alignment: .top, spacing: ESUI.Space.sm) {
                            VStack(alignment: .leading, spacing: ESUI.Space.xxs) {
                                Text(monthRangeText(for: summary))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)

                                Text(summary.isTargetMet ? "达标" : "差 \(hoursText(summary.remainingToTarget))h")
                                    .font(.footnote)
                                    .foregroundStyle(summary.isTargetMet ? Color.green : Color.secondary)
                            }

                            Spacer(minLength: ESUI.Space.xs)

                            VStack(alignment: .trailing, spacing: ESUI.Space.xxs) {
                                Text("\(hoursText(summary.totalHours))h")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)

                                ESStatusBadge(
                                    text: summary.isTargetMet ? "已达标" : "未达标",
                                    tone: summary.isTargetMet ? .success : .neutral
                                )
                            }
                        }

                        ProgressView(value: clamped(summary.targetProgress))
                            .tint(summary.isTargetMet ? .green : .orange)
                    }
                }
            }
        }
        .esCard()
    }

    // MARK: - Helpers

    private func progressBlock(title: String, progress: Double, detail: String, isMet: Bool) -> some View {
        VStack(alignment: .leading, spacing: ESUI.Space.xs) {
            HStack {
                Text(title)
                    .font(.footnote.weight(.semibold))
                Spacer()
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: clamped(progress))
                .tint(isMet ? .green : .orange)
        }
    }

    private var quickHourOptions: [Double] {
        [4, 6, 8, 10]
    }

    private var selectedMonthSummary: UTMonthSummary {
        viewModel.summary(for: selectedDate)
    }

    private var projectedMonthTotalHours: Double {
        selectedMonthSummary.totalHours + draftHours
    }

    private var remainingSuggestionHours: Double? {
        let remaining = roundedToHalfHour(selectedMonthSummary.remainingToTarget)
        guard remaining >= 0.5, remaining <= 16, !quickHourOptions.contains(remaining) else {
            return nil
        }
        return remaining
    }

    private var projectedMonthSummaryText: String {
        "\(hoursText(projectedMonthTotalHours)) / \(hoursText(selectedMonthSummary.targetHours))h"
    }

    private var projectedMonthLabel: String {
        viewModel.isInCurrentMonth(selectedDate) ? "本月" : "该月"
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

    private func dateShortcutButton(
        title: String,
        subtitle: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: ESUI.Space.xxs) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ESUI.Space.sm)
            .padding(.vertical, ESUI.Space.sm)
            .background(
                RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : ESUI.fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func presetButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, ESUI.Space.sm)
                .padding(.vertical, ESUI.Space.sm)
                .background(
                    RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.12) : ESUI.fill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                        .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
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

    private func monthRangeText(for summary: UTMonthSummary) -> String {
        let start = summary.monthStart.formatted(.dateTime.month().day())
        let end = summary.monthEnd.formatted(.dateTime.month().day())
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
        HStack(spacing: ESUI.Space.sm) {
            VStack(alignment: .leading, spacing: ESUI.Space.xxs) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: ESUI.Space.sm)

            VStack(alignment: .trailing, spacing: ESUI.Space.xs) {
                Text(trailing)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)

                Button(role: .destructive, action: deleteAction) {
                    Image(systemName: "trash")
                        .font(.caption.weight(.semibold))
                        .padding(ESUI.Space.xs)
                }
                .buttonStyle(.borderless)
                .background(Circle().fill(Color.red.opacity(0.12)))
                .foregroundStyle(.red)
                .accessibilityLabel("删除记录")
            }
        }
        .padding(.horizontal, ESUI.Space.md)
        .padding(.vertical, ESUI.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                .fill(ESUI.fill)
        )
    }
}

#Preview {
    NavigationStack {
        UTTrackerView()
    }
}
