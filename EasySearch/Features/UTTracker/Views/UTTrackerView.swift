import SwiftUI
import UIKit

public struct UTTrackerView: View {
    @StateObject private var viewModel = UTTrackerViewModel()
    @State private var selectedDate = Date()
    @State private var draftHours = UTTrackerMetrics.dailyReferenceHours
    @State private var draftNote = ""
    @State private var selectedFactory: String
    @State private var selectedMachine = ""
    @State private var newMachineName = ""
    @State private var showingMoreOptions = false
    @State private var showingSettings = false
    @State private var showingHistory = false

    public init() {
        let initialFactory = UserDefaults.standard.string(forKey: UTTrackerStorage.lastFactoryKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedFactories = UserDefaults.standard.stringArray(forKey: UTTrackerStorage.factoriesKey)?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
        let effectiveFactories = (savedFactories.count == 2 && savedFactories[0] != savedFactories[1])
            ? savedFactories
            : UTFactoryLayout.defaultFactories

        let factory: String
        if let initialFactory, effectiveFactories.contains(initialFactory) {
            factory = initialFactory
        } else {
            factory = ""
        }
        _selectedFactory = State(initialValue: factory)
        _selectedMachine = State(initialValue: UserDefaults.standard.string(forKey: UTTrackerStorage.lastMachineKey) ?? "")
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ESUI.sectionSpacing) {
                ESModuleHero(
                    title: "UT 记录",
                    subtitle: "工时追踪 · 70% 目标达成",
                    featureID: "uttracker",
                    systemImage: "chart.bar.doc.horizontal"
                )
                progressCard
                machineDurationCard
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
        .onAppear {
            if !selectedFactory.isEmpty && !viewModel.factories.contains(selectedFactory) {
                selectedFactory = viewModel.lastFactory
            }
            if selectedMachine.isEmpty && !viewModel.lastMachine.isEmpty {
                selectedMachine = viewModel.lastMachine
            }
        }

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
                        .animation(ESMotion.value, value: progress)

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

    // MARK: - Machine Duration

    private var machineDurationCard: some View {
        let totals = viewModel.machineDurationTotals
        let maxHours = totals.map(\.totalHours).max() ?? 0.0
        let grandTotal = totals.reduce(0) { $0 + $1.totalHours }

        return VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            ESSectionHeader(
                title: "机台时长",
                subtitle: "最近一年累计",
                trailing: totals.isEmpty ? nil : "共 \(hoursText(grandTotal))h"
            )

            if totals.isEmpty {
                Text("暂无机台记录")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, ESUI.Space.xs)
            } else {
                VStack(spacing: ESUI.Space.xs) {
                    ForEach(totals) { item in
                        HStack(spacing: ESUI.Space.sm) {
                            Text(item.machine)
                                .font(.subheadline.weight(.semibold))

                            Spacer(minLength: ESUI.Space.sm)

                            Text("\(hoursText(item.totalHours))h")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(item.totalHours > 0 ? Color.primary : Color.secondary)
                        }
                        .padding(.horizontal, ESUI.Space.md)
                        .padding(.vertical, ESUI.Space.sm)
                        .background(
                            GeometryReader { geo in
                                let progress = maxHours > 0 ? (item.totalHours / maxHours) : 0
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                                        .fill(ESUI.fill)

                                    if progress > 0 {
                                        RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                                            .fill(Color.accentColor.opacity(0.12))
                                            .frame(width: geo.size.width * CGFloat(progress))
                                    }
                                }
                            }
                        )
                    }
                }
            }
        }
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

            VStack(alignment: .leading, spacing: ESUI.Space.xs) {
                Text("厂区")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: ESUI.Space.xs) {
                    presetButton(
                        title: "不选",
                        isSelected: selectedFactory.isEmpty
                    ) {
                        selectedFactory = ""
                        viewModel.rememberFactory("")
                    }

                    ForEach(viewModel.factories, id: \.self) { factory in
                        presetButton(
                            title: factory,
                            isSelected: selectedFactory == factory
                        ) {
                            selectedFactory = factory
                            viewModel.rememberFactory(factory)
                            if !selectedMachine.isEmpty, !viewModel.machines(in: factory).contains(selectedMachine) {
                                selectedMachine = ""
                                viewModel.rememberMachine("")
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: ESUI.Space.xs) {
                Text("机台")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 72), spacing: ESUI.Space.xs)],
                    alignment: .leading,
                    spacing: ESUI.Space.xs
                ) {
                    presetButton(
                        title: "不选",
                        isSelected: selectedMachine.isEmpty
                    ) {
                        selectedMachine = ""
                        viewModel.rememberMachine("")
                    }

                    ForEach(viewModel.machines(in: selectedFactory), id: \.self) { machine in
                        presetButton(
                            title: machine,
                            isSelected: selectedMachine == machine
                        ) {
                            selectedMachine = machine
                            viewModel.rememberMachine(machine)
                        }
                    }
                }

                HStack(spacing: ESUI.Space.xs) {
                    TextField("新机台名称", text: $newMachineName)
                        .font(.subheadline)
                        .padding(.horizontal, ESUI.Space.sm)
                        .padding(.vertical, ESUI.Space.xs)
                        .background(
                            RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                                .fill(ESUI.fill)
                        )
                        .onSubmit(addNewMachine)

                    Button(action: addNewMachine) {
                        Text("添加")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, ESUI.Space.md)
                            .padding(.vertical, ESUI.Space.xs)
                            .background(
                                RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                                    .fill(newMachineName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? ESUI.fill : Color.accentColor.opacity(0.12))
                            )
                            .foregroundStyle(newMachineName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(newMachineName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
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
                            if !entry.machine.isEmpty {
                                Text(entry.machine)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
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
        viewModel.addEntry(date: selectedDate, hours: draftHours, note: draftNote, machine: selectedMachine)
        ESHaptics.success()
        selectedDate = Date()
        draftHours = UTTrackerMetrics.dailyReferenceHours
        draftNote = ""
        showingMoreOptions = false
    }

    private func addNewMachine() {
        let targetFactory = selectedFactory.isEmpty ? nil : selectedFactory
        if let added = viewModel.addMachine(newMachineName, factory: targetFactory) {
            selectedMachine = added
            viewModel.rememberMachine(added)
            newMachineName = ""
            ESHaptics.success()
        }
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
