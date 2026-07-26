import SwiftUI
import UIKit

public struct UTTrackerView: View {
    @StateObject private var viewModel = UTTrackerViewModel()
    @State private var selectedDate = Date()
    @State private var draftHours = UTTrackerMetrics.dailyReferenceHours
    @State private var draftNote = ""
    @State private var showingMoreOptions = false
    @State private var showingSettings = false
    @State private var showingHistory = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ESUI.Space.md) {
                progressCard
                quickLogCard
                if !viewModel.currentMonthEntries.isEmpty {
                    currentMonthEntriesCard
                }
                historyDisclosure
            }
            .padding(.horizontal, ESUI.screenHorizontalPadding)
            .padding(.top, ESUI.Space.md)
            .padding(.bottom, ESUI.Space.xxl)
        }
        .esScreenBackground()
        .navigationTitle("UT 记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("UT 设置")
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                UTTrackerSettingsDetailView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("完成") { showingSettings = false }
                        }
                    }
            }
        }
    }

    // MARK: - Progress

    private var progressCard: some View {
        let summary = viewModel.currentMonthSummary
        let progress = clamped(summary.targetProgress)

        return VStack(alignment: .leading, spacing: ESUI.Space.md) {
            HStack(alignment: .center, spacing: ESUI.Space.lg) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            summary.isTargetMet ? Color.green : Color.orange,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.5, dampingFraction: 0.9), value: progress)

                    VStack(spacing: 0) {
                        Text(percentText(for: summary.targetProgress))
                            .font(.title3.weight(.bold).monospacedDigit())
                        Text("70% 目标")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 108, height: 108)

                VStack(alignment: .leading, spacing: ESUI.Space.xs) {
                    Text(monthRangeText(for: summary))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("\(hoursText(summary.totalHours)) / \(hoursText(summary.targetHours))h")
                        .font(.title3.weight(.semibold).monospacedDigit())

                    if summary.isTargetMet {
                        ESStatusBadge(text: "已达标 · 超出 \(hoursText(max(0, summary.totalHours - summary.targetHours)))h", tone: .success)
                    } else {
                        ESStatusBadge(text: "还差 \(hoursText(summary.remainingToTarget))h", tone: .warning)
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .esCard()
    }

    // MARK: - Quick Log

    private var quickLogCard: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.md) {
            HStack {
                Text("快速记录")
                    .font(.headline)
                Spacer()
                DatePicker("", selection: $selectedDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }

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

            ESPrimaryCTA(
                title: saveButtonTitle,
                systemImage: "plus.circle.fill",
                enabled: draftHours > 0,
                action: saveEntry
            )

            DisclosureGroup("更多选项", isExpanded: $showingMoreOptions) {
                VStack(alignment: .leading, spacing: ESUI.Space.sm) {
                    Stepper(value: $draftHours, in: 0.5...16, step: 0.5) {
                        Text("微调:\(hoursText(draftHours))h")
                            .font(.subheadline)
                    }

                    TextField("备注(可选)", text: $draftNote, axis: .vertical)
                        .lineLimit(3, reservesSpace: false)
                        .padding(.horizontal, ESUI.Space.sm)
                        .padding(.vertical, ESUI.Space.xs)
                        .background(
                            RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                                .fill(ESUI.fill)
                        )

                    projectedBanner
                }
                .padding(.top, ESUI.Space.xs)
            }
            .font(.subheadline)
            .tint(.secondary)
        }
        .esCard()
    }

    private var projectedBanner: some View {
        let summary = selectedMonthSummary
        let isProjectedTargetMet = (summary.totalHours + draftHours) >= summary.targetHours

        return ESStatusBanner(
            title: "保存后\(projectedMonthLabel)共 \(hoursText(summary.totalHours + draftHours)) / \(hoursText(summary.targetHours))h",
            message: isProjectedTargetMet ? "可达到 70% 目标" : "仍未达标",
            systemImage: isProjectedTargetMet ? "checkmark.seal.fill" : "scope",
            tone: isProjectedTargetMet ? .success : .warning
        )
    }

    // MARK: - Entries

    private var currentMonthEntriesCard: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            ESSectionHeader(
                title: "本月记录",
                trailing: "\(viewModel.currentMonthEntries.count)"
            )

            VStack(spacing: ESUI.Space.xs) {
                ForEach(viewModel.currentMonthEntries) { entry in
                    HStack(spacing: ESUI.Space.sm) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entryTitle(for: entry))
                                .font(.subheadline.weight(.semibold))
                            if !entry.note.isEmpty {
                                Text(entry.note)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer(minLength: ESUI.Space.sm)

                        Text("\(hoursText(entry.hours))h")
                            .font(.body.weight(.semibold).monospacedDigit())

                        Menu {
                            Button("删除", systemImage: "trash", role: .destructive) {
                                viewModel.deleteEntry(entry)
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
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
        }
        .esCard()
    }

    // MARK: - History

    private var historyDisclosure: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            DisclosureGroup("历史月份", isExpanded: $showingHistory) {
                VStack(spacing: ESUI.Space.md) {
                    ForEach(viewModel.recentMonthSummaries(limit: 6).dropFirst()) { summary in
                        VStack(alignment: .leading, spacing: ESUI.Space.xs) {
                            HStack {
                                Text(monthRangeText(for: summary))
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(hoursText(summary.totalHours))h")
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
                                ESStatusBadge(
                                    text: summary.isTargetMet ? "达标" : "差 \(hoursText(summary.remainingToTarget))h",
                                    tone: summary.isTargetMet ? .success : .neutral
                                )
                            }

                            ProgressView(value: clamped(summary.targetProgress))
                                .tint(summary.isTargetMet ? .green : .orange)
                        }
                    }
                }
                .padding(.top, ESUI.Space.sm)
            }
            .font(.headline)
            .tint(.primary)
        }
        .esCard()
    }

    // MARK: - Helpers

    private var quickHourOptions: [Double] {
        [4, 6, 8, 10]
    }

    private var selectedMonthSummary: UTMonthSummary {
        viewModel.summary(for: selectedDate)
    }

    private var remainingSuggestionHours: Double? {
        let remaining = roundedToHalfHour(selectedMonthSummary.remainingToTarget)
        guard remaining >= 0.5, remaining <= 16, !quickHourOptions.contains(remaining) else {
            return nil
        }
        return remaining
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

    private func presetButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            ESHaptics.selection()
            action()
        } label: {
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
                .animation(ESMotion.quick, value: isSelected)
        }
        .buttonStyle(.plain)
    }

    private func saveEntry() {
        viewModel.addEntry(date: selectedDate, hours: draftHours, note: draftNote)
        ESHaptics.success()
        selectedDate = Date()
        draftHours = UTTrackerMetrics.dailyReferenceHours
        draftNote = ""
        showingMoreOptions = false
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

    private func percentText(for progress: Double) -> String {
        let percent = progress * 100
        return percent.formatted(.number.precision(.fractionLength(0))) + "%"
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private func roundedToHalfHour(_ hours: Double) -> Double {
        (hours * 2).rounded() / 2
    }
}

#Preview {
    NavigationStack {
        UTTrackerView()
    }
}
