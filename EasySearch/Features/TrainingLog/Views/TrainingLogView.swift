import UIKit
import SwiftUI

public struct TrainingLogView: View {
    @StateObject private var viewModel = TrainingLogViewModel()
    @State private var showingAddLine = false

    private let weekdaySymbols = ["一", "二", "三", "四", "五", "六", "日"]
    private let featureID = "training-log"

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ESUI.sectionSpacing) {
                ESModuleHero(
                    title: "训练记录",
                    subtitle: "月历打卡 · 徒手动作",
                    featureID: featureID,
                    systemImage: "flame.fill"
                )

                monthCard
                dayDetailCard
            }
            .padding(.horizontal, ESUI.screenHorizontalPadding)
            .padding(.top, ESUI.Space.md)
            .padding(.bottom, ESUI.Space.xxl)
        }
        .esScreenBackground()
        .navigationTitle("训练记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    ESHaptics.tap()
                    viewModel.jumpToToday()
                } label: {
                    Text("今天")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .sheet(isPresented: $showingAddLine) {
            AddWorkoutLineSheet { exercise, amount in
                viewModel.addLine(exercise: exercise, amount: amount)
                ESHaptics.success()
            }
        }
    }

    // MARK: - Month

    private var monthCard: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.md) {
            HStack(spacing: ESUI.Space.sm) {
                Button {
                    ESHaptics.selection()
                    viewModel.shiftMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(ESUI.fill))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.monthTitle)
                        .font(.title3.weight(.semibold))
                    Text("训练 \(viewModel.monthTrainingDayCount) 天 · \(viewModel.monthLineCount) 组")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: ESUI.Space.xs)

                Button {
                    ESHaptics.selection()
                    viewModel.shiftMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(ESUI.fill))
                }
                .buttonStyle(.plain)
            }

            weekdayHeader

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: ESUI.Space.xs), count: 7),
                spacing: ESUI.Space.xs
            ) {
                ForEach(Array(viewModel.monthGridDays().enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear
                            .frame(height: 44)
                    }
                }
            }
        }
        .esCard()
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let calendar = TrainingLogCalendar.calendar
        let dayNumber = calendar.component(.day, from: date)
        let isSelected = calendar.isDate(date, inSameDayAs: viewModel.selectedDay)
        let isToday = calendar.isDateInToday(date)
        let trained = viewModel.hasTraining(on: date)
        let accent = ESUI.moduleColor(for: featureID)

        return Button {
            ESHaptics.selection()
            withAnimation(ESMotion.quick) {
                viewModel.selectDay(date)
            }
        } label: {
            VStack(spacing: 4) {
                Text("\(dayNumber)")
                    .font(.subheadline.weight(isSelected || isToday ? .bold : .medium))
                    .foregroundStyle(isSelected ? .white : .primary)

                Circle()
                    .fill(trained ? (isSelected ? Color.white.opacity(0.95) : accent) : Color.clear)
                    .frame(width: 6, height: 6)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(accent)
                    } else if isToday {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(ESUI.fill)
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.clear)
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityDayLabel(date: date, trained: trained, isToday: isToday))
    }

    private func accessibilityDayLabel(date: Date, trained: Bool, isToday: Bool) -> String {
        let day = TrainingLogCalendar.dayTitleFormatter.string(from: date)
        var parts = [day]
        if isToday { parts.append("今天") }
        if trained {
            parts.append("已训练 \(viewModel.lineCount(on: date)) 组")
        } else {
            parts.append("未训练")
        }
        return parts.joined(separator: "，")
    }

    // MARK: - Day detail

    private var dayDetailCard: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: ESUI.Space.xxs) {
                    Text(viewModel.selectedDayTitle)
                        .font(.title3.weight(.semibold))
                    Text(viewModel.selectedLines.isEmpty ? "还没有记录" : "\(viewModel.selectedLines.count) 组动作")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if viewModel.selectedLines.isEmpty {
                ESEmptyState(
                    title: "今天还没练",
                    message: "从动作库添加一组记录吧",
                    systemImage: "figure.walk",
                    minHeight: 120
                )
            } else {
                VStack(spacing: ESUI.Space.sm) {
                    ForEach(viewModel.selectedLines) { line in
                        workoutLineRow(line)
                    }
                }
            }

            HStack(spacing: ESUI.Space.sm) {
                Button {
                    ESHaptics.tap()
                    showingAddLine = true
                } label: {
                    Label("添加动作", systemImage: "plus.circle.fill")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, ESUI.Space.xs)
                }
                .buttonStyle(.glassProminent)

                if viewModel.lastTrainedDay(before: viewModel.selectedDay) != nil {
                    Button {
                        if viewModel.repeatLastWorkout() {
                            ESHaptics.success()
                        } else {
                            ESHaptics.warning()
                        }
                    } label: {
                        Label("重复上次", systemImage: "arrow.counterclockwise")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, ESUI.Space.xs)
                    }
                    .buttonStyle(.glass)
                }
            }

            if !viewModel.selectedLines.isEmpty {
                Button(role: .destructive) {
                    ESHaptics.impact(.rigid)
                    viewModel.clearSelectedDay()
                } label: {
                    Text("清空当天")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, ESUI.Space.sm)
                }
                .buttonStyle(.plain)
            }
        }
        .esCard()
    }

    private func workoutLineRow(_ line: WorkoutLine) -> some View {
        HStack(spacing: ESUI.Space.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.exerciseName)
                    .font(.body.weight(.semibold))
                Text(line.amountText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: ESUI.Space.xs)

            Button {
                ESHaptics.tap()
                viewModel.addAnotherSet(from: line)
            } label: {
                Text("再一组")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(ESUI.fill))
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                ESHaptics.impact(.rigid)
                viewModel.deleteLine(id: line.id)
            } label: {
                Image(systemName: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ESUI.danger)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(ESUI.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                .fill(ESUI.fill.opacity(0.65))
        )
    }
}

// MARK: - Add line sheet

private struct AddWorkoutLineSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onAdd: (ExerciseDefinition, Int) -> Void

    @State private var selectedCategoryID: String = TrainingExerciseLibrary.categories.first?.id ?? "push"
    @State private var selectedExerciseID: String?
    @State private var amount: Int = 10

    private var exercisesInCategory: [ExerciseDefinition] {
        TrainingExerciseLibrary.exercises(in: selectedCategoryID)
    }

    private var selectedExercise: ExerciseDefinition? {
        if let selectedExerciseID {
            return TrainingExerciseLibrary.exercise(id: selectedExerciseID)
        }
        return exercisesInCategory.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ESUI.sectionSpacing) {
                    categorySection
                    exerciseSection
                    if let exercise = selectedExercise {
                        amountSection(exercise)
                    }
                }
                .padding(.horizontal, ESUI.screenHorizontalPadding)
                .padding(.top, ESUI.Space.md)
                .padding(.bottom, ESUI.Space.xxl)
            }
            .esScreenBackground()
            .navigationTitle("添加动作")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        guard let exercise = selectedExercise, amount > 0 else { return }
                        onAdd(exercise, amount)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedExercise == nil || amount <= 0)
                }
            }
            .onAppear {
                syncSelectionDefaults()
            }
            .onChange(of: selectedCategoryID) { _ in
                syncSelectionDefaults(forceExercise: true)
            }
            .onChange(of: selectedExerciseID) { _ in
                if let exercise = selectedExercise {
                    amount = exercise.defaultAmount
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            Text("分类")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: ESUI.Space.sm), GridItem(.flexible(), spacing: ESUI.Space.sm)],
                spacing: ESUI.Space.sm
            ) {
                ForEach(TrainingExerciseLibrary.categories) { category in
                    let selected = category.id == selectedCategoryID
                    Button {
                        selectedCategoryID = category.id
                    } label: {
                        HStack(spacing: ESUI.Space.xs) {
                            Image(systemName: category.systemImage)
                            Text(category.name)
                                .font(.subheadline.weight(.semibold))
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, ESUI.Space.sm)
                        .padding(.vertical, ESUI.Space.sm)
                        .background(
                            RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                                .fill(selected ? Color.accentColor.opacity(0.12) : ESUI.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                                .stroke(selected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var exerciseSection: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            Text("动作")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: ESUI.Space.xs) {
                ForEach(exercisesInCategory) { exercise in
                    let selected = exercise.id == selectedExercise?.id
                    Button {
                        selectedExerciseID = exercise.id
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.name)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("默认 \(exercise.defaultAmount)\(exercise.unit.shortLabel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(ESUI.Space.sm)
                        .background(
                            RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                                .fill(selected ? Color.accentColor.opacity(0.1) : ESUI.surface)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func amountSection(_ exercise: ExerciseDefinition) -> some View {
        VStack(alignment: .leading, spacing: ESUI.Space.md) {
            Text("数量（\(exercise.unit.shortLabel)）")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: ESUI.Space.md) {
                Button {
                    amount = max(1, amount - step(for: exercise.unit))
                } label: {
                    Image(systemName: "minus")
                        .font(.body.weight(.bold))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(ESUI.fill))
                }
                .buttonStyle(.plain)

                Text("\(amount)")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .frame(maxWidth: .infinity)

                Button {
                    amount = min(999, amount + step(for: exercise.unit))
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.bold))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(ESUI.fill))
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ESUI.Space.xs) {
                    ForEach(exercise.suggestedAmounts, id: \.self) { value in
                        Button {
                            amount = value
                        } label: {
                            Text("\(value)\(exercise.unit.shortLabel)")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule().fill(amount == value ? Color.accentColor.opacity(0.15) : ESUI.fill)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text("将添加：\(exercise.name) \(amount)\(exercise.unit.shortLabel)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .esCard()
    }

    private func step(for unit: ExerciseUnit) -> Int {
        unit == .seconds ? 5 : 1
    }

    private func syncSelectionDefaults(forceExercise: Bool = false) {
        if forceExercise || selectedExerciseID == nil || !(exercisesInCategory.contains { $0.id == selectedExerciseID }) {
            selectedExerciseID = exercisesInCategory.first?.id
        }
        if let exercise = selectedExercise {
            amount = exercise.defaultAmount
        }
    }
}
