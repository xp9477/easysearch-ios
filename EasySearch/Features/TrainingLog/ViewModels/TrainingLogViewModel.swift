import Foundation
import Combine

@MainActor
final class TrainingLogViewModel: ObservableObject {
    @Published private(set) var snapshot = TrainingLogSnapshot()
    @Published var visibleMonth: Date
    @Published var selectedDay: Date

    private let store: TrainingLogStore
    private var observer: NSObjectProtocol?

    init(store: TrainingLogStore = TrainingLogLocalStore()) {
        self.store = store
        let today = TrainingLogCalendar.startOfDay(Date())
        self.visibleMonth = TrainingLogCalendar.startOfMonth(today)
        self.selectedDay = today
        reload()
        observer = NotificationCenter.default.addObserver(
            forName: .trainingLogDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reload()
            }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func reload() {
        snapshot = store.loadSnapshot()
    }

    // MARK: - Queries

    var selectedDayKey: String {
        TrainingLogCalendar.dayKey(for: selectedDay)
    }

    var selectedWorkoutDay: WorkoutDay? {
        snapshot.days[selectedDayKey]
    }

    var selectedLines: [WorkoutLine] {
        selectedWorkoutDay?.lines ?? []
    }

    var monthTitle: String {
        TrainingLogCalendar.monthTitleFormatter.string(from: visibleMonth)
    }

    var selectedDayTitle: String {
        TrainingLogCalendar.dayTitleFormatter.string(from: selectedDay)
    }

    var monthTrainingDayCount: Int {
        let keys = monthDayKeys(for: visibleMonth)
        return keys.reduce(into: 0) { count, key in
            if let day = snapshot.days[key], day.hasTraining {
                count += 1
            }
        }
    }

    var monthLineCount: Int {
        let keys = monthDayKeys(for: visibleMonth)
        return keys.reduce(into: 0) { total, key in
            total += snapshot.days[key]?.totalLines ?? 0
        }
    }

    func hasTraining(on date: Date) -> Bool {
        let key = TrainingLogCalendar.dayKey(for: date)
        return snapshot.days[key]?.hasTraining == true
    }

    func lineCount(on date: Date) -> Int {
        let key = TrainingLogCalendar.dayKey(for: date)
        return snapshot.days[key]?.totalLines ?? 0
    }

    func monthGridDays() -> [Date?] {
        TrainingLogCalendar.monthGridDays(for: visibleMonth)
    }

    // MARK: - Navigation

    func shiftMonth(by value: Int) {
        if let next = TrainingLogCalendar.calendar.date(byAdding: .month, value: value, to: visibleMonth) {
            visibleMonth = TrainingLogCalendar.startOfMonth(next)
        }
    }

    func selectDay(_ date: Date) {
        let day = TrainingLogCalendar.startOfDay(date)
        selectedDay = day
        visibleMonth = TrainingLogCalendar.startOfMonth(day)
    }

    func jumpToToday() {
        selectDay(Date())
    }

    // MARK: - Mutations

    func addLine(exercise: ExerciseDefinition, amount: Int) {
        guard amount > 0 else { return }
        let key = selectedDayKey
        var day = snapshot.days[key] ?? WorkoutDay(
            id: key,
            dayStart: TrainingLogCalendar.startOfDay(selectedDay),
            lines: [],
            note: nil
        )
        let line = WorkoutLine(
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            amount: amount,
            unit: exercise.unit
        )
        day.lines.append(line)
        day.updatedAt = .now
        snapshot.days[key] = day
        persist(changedDayID: key)
    }

    func addAnotherSet(from line: WorkoutLine) {
        guard let exercise = TrainingExerciseLibrary.exercise(id: line.exerciseID) else {
            // Keep denormalized data if library entry missing.
            let key = selectedDayKey
            var day = snapshot.days[key] ?? WorkoutDay(
                id: key,
                dayStart: TrainingLogCalendar.startOfDay(selectedDay),
                lines: [],
                note: nil
            )
            day.lines.append(
                WorkoutLine(
                    exerciseID: line.exerciseID,
                    exerciseName: line.exerciseName,
                    amount: line.amount,
                    unit: line.unit
                )
            )
            day.updatedAt = .now
            snapshot.days[key] = day
            persist(changedDayID: key)
            return
        }
        addLine(exercise: exercise, amount: line.amount)
    }

    func deleteLine(id: UUID) {
        let key = selectedDayKey
        guard var day = snapshot.days[key] else { return }
        day.lines.removeAll { $0.id == id }
        day.updatedAt = .now
        snapshot.days[key] = day
        persist(changedDayID: key)
    }

    func clearSelectedDay() {
        let key = selectedDayKey
        guard var day = snapshot.days[key], !day.isTombstone else { return }
        day.lines.removeAll()
        day.note = nil
        day.updatedAt = .now
        snapshot.days[key] = day
        persist(changedDayID: key)
    }

    /// 找到选中日之前最近的一个训练日,把整组动作复制到选中日。
    @discardableResult
    func repeatLastWorkout() -> Bool {
        guard let source = lastTrainedDay(before: selectedDay) else { return false }
        let key = selectedDayKey
        var day = snapshot.days[key] ?? WorkoutDay(
            id: key,
            dayStart: TrainingLogCalendar.startOfDay(selectedDay),
            lines: [],
            note: nil
        )
        for line in source.lines {
            day.lines.append(
                WorkoutLine(
                    exerciseID: line.exerciseID,
                    exerciseName: line.exerciseName,
                    amount: line.amount,
                    unit: line.unit
                )
            )
        }
        day.updatedAt = .now
        snapshot.days[key] = day
        persist(changedDayID: key)
        return true
    }

    /// 选中日之前最近的训练日(不含选中日),用于"重复上次"。
    func lastTrainedDay(before date: Date) -> WorkoutDay? {
        let dayStart = TrainingLogCalendar.startOfDay(date)
        return snapshot.days.values
            .filter { $0.hasTraining && $0.dayStart < dayStart }
            .max(by: { $0.dayStart < $1.dayStart })
    }

    // MARK: - Private

    private func persist(changedDayID: String) {
        store.saveSnapshot(snapshot)
        guard let changedDay = snapshot.days[changedDayID] else { return }

        Task {
            await CloudSyncViewModel.shared.syncTrainingDayUpsertIfPossible(changedDay)
        }
    }

    private func monthDayKeys(for month: Date) -> [String] {
        let start = TrainingLogCalendar.startOfMonth(month)
        let days = TrainingLogCalendar.calendar.range(of: .day, in: .month, for: start)?.count ?? 0
        return (0..<days).compactMap { offset in
            guard let date = TrainingLogCalendar.calendar.date(byAdding: .day, value: offset, to: start) else {
                return nil
            }
            return TrainingLogCalendar.dayKey(for: date)
        }
    }
}
