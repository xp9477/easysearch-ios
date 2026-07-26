import Foundation
import XCTest
@testable import EasySearch

@MainActor
final class TrainingLogRepeatWorkoutTests: XCTestCase {
    private final class InMemoryTrainingLogStore: TrainingLogStore {
        var snapshot = TrainingLogSnapshot()

        func loadSnapshot() -> TrainingLogSnapshot {
            snapshot
        }

        func saveSnapshot(_ snapshot: TrainingLogSnapshot) {
            self.snapshot = snapshot
        }
    }

    func testRepeatLastWorkoutCopiesMostRecentDayLines() {
        let store = InMemoryTrainingLogStore()
        let calendar = TrainingLogCalendar.calendar
        let today = TrainingLogCalendar.startOfDay(Date())
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today)!
        let fiveDaysAgo = calendar.date(byAdding: .day, value: -5, to: today)!

        store.snapshot = TrainingLogSnapshot(days: [
            TrainingLogCalendar.dayKey(for: twoDaysAgo): WorkoutDay(
                id: TrainingLogCalendar.dayKey(for: twoDaysAgo),
                dayStart: twoDaysAgo,
                lines: [
                    WorkoutLine(exerciseID: "pushup", exerciseName: "俯卧撑", amount: 20, unit: .reps),
                    WorkoutLine(exerciseID: "plank", exerciseName: "平板支撑", amount: 60, unit: .seconds)
                ],
                note: nil
            ),
            TrainingLogCalendar.dayKey(for: fiveDaysAgo): WorkoutDay(
                id: TrainingLogCalendar.dayKey(for: fiveDaysAgo),
                dayStart: fiveDaysAgo,
                lines: [
                    WorkoutLine(exerciseID: "squat", exerciseName: "深蹲", amount: 30, unit: .reps)
                ],
                note: nil
            )
        ])

        let viewModel = TrainingLogViewModel(store: store)
        XCTAssertTrue(viewModel.repeatLastWorkout())

        let todayLines = viewModel.selectedLines
        XCTAssertEqual(todayLines.map(\.exerciseID), ["pushup", "plank"])
        XCTAssertEqual(todayLines.map(\.amount), [20, 60])
        // 复制出的是新 line,不共享 id
        XCTAssertNotEqual(
            Set(todayLines.map(\.id)),
            Set(store.snapshot.days[TrainingLogCalendar.dayKey(for: twoDaysAgo)]!.lines.map(\.id))
        )
    }

    func testRepeatLastWorkoutAppendsToExistingDay() {
        let store = InMemoryTrainingLogStore()
        let calendar = TrainingLogCalendar.calendar
        let today = TrainingLogCalendar.startOfDay(Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        store.snapshot = TrainingLogSnapshot(days: [
            TrainingLogCalendar.dayKey(for: yesterday): WorkoutDay(
                id: TrainingLogCalendar.dayKey(for: yesterday),
                dayStart: yesterday,
                lines: [WorkoutLine(exerciseID: "pushup", exerciseName: "俯卧撑", amount: 15, unit: .reps)],
                note: nil
            ),
            TrainingLogCalendar.dayKey(for: today): WorkoutDay(
                id: TrainingLogCalendar.dayKey(for: today),
                dayStart: today,
                lines: [WorkoutLine(exerciseID: "squat", exerciseName: "深蹲", amount: 25, unit: .reps)],
                note: nil
            )
        ])

        let viewModel = TrainingLogViewModel(store: store)
        XCTAssertTrue(viewModel.repeatLastWorkout())
        XCTAssertEqual(viewModel.selectedLines.map(\.exerciseID), ["squat", "pushup"])
    }

    func testRepeatLastWorkoutReturnsFalseWithoutHistory() {
        let viewModel = TrainingLogViewModel(store: InMemoryTrainingLogStore())
        XCTAssertFalse(viewModel.repeatLastWorkout())
        XCTAssertTrue(viewModel.selectedLines.isEmpty)
    }
}
