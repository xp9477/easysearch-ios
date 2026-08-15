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

    func testCloudMergeKeepsNewestWholeDaySoDeletedLinesDoNotReturn() {
        let dayStart = TrainingLogCalendar.startOfDay(Date())
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)
        let keptLine = WorkoutLine(
            id: UUID(),
            exerciseID: "pushup",
            exerciseName: "俯卧撑",
            amount: 20,
            unit: .reps,
            createdAt: older
        )
        let deletedLine = WorkoutLine(
            id: UUID(),
            exerciseID: "plank",
            exerciseName: "平板支撑",
            amount: 60,
            unit: .seconds,
            createdAt: older
        )
        let remote = WorkoutDay(
            id: "2026-08-15",
            dayStart: dayStart,
            lines: [keptLine, deletedLine],
            note: nil,
            updatedAt: older
        )
        let local = WorkoutDay(
            id: remote.id,
            dayStart: dayStart,
            lines: [keptLine],
            note: nil,
            updatedAt: newer
        )

        let merged = HiddenCloudMerge.workoutDays(primary: [remote], secondary: [local])

        XCTAssertEqual(merged, [local])
    }

    func testWorkoutDayDecodesLegacyValueWithoutUpdatedAt() throws {
        struct LegacyWorkoutDay: Encodable {
            let id: String
            let dayStart: Date
            let lines: [WorkoutLine]
            let note: String?
        }

        let createdAt = Date(timeIntervalSince1970: 123)
        let legacy = LegacyWorkoutDay(
            id: "2026-08-15",
            dayStart: Date(timeIntervalSince1970: 100),
            lines: [
                WorkoutLine(
                    exerciseID: "squat",
                    exerciseName: "深蹲",
                    amount: 20,
                    unit: .reps,
                    createdAt: createdAt
                )
            ],
            note: nil
        )

        let decoded = try JSONDecoder().decode(
            WorkoutDay.self,
            from: JSONEncoder().encode(legacy)
        )

        XCTAssertEqual(decoded.updatedAt, createdAt)
    }

    func testCloudMergeKeepsNewerTombstoneOverOlderRemoteDay() {
        let dayStart = Date(timeIntervalSince1970: 100)
        let remote = WorkoutDay(
            id: "2026-08-15",
            dayStart: dayStart,
            lines: [
                WorkoutLine(
                    exerciseID: "squat",
                    exerciseName: "深蹲",
                    amount: 20,
                    unit: .reps,
                    createdAt: Date(timeIntervalSince1970: 150)
                )
            ],
            note: nil,
            updatedAt: Date(timeIntervalSince1970: 150)
        )
        let tombstone = WorkoutDay(
            id: remote.id,
            dayStart: dayStart,
            lines: [],
            note: nil,
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        let merged = HiddenCloudMerge.workoutDays(primary: [remote], secondary: [tombstone])

        XCTAssertEqual(merged, [tombstone])
        XCTAssertTrue(merged[0].isTombstone)
    }

    func testCloudMergePrefersTombstoneWhenClocksAreEqual() {
        let dayStart = Date(timeIntervalSince1970: 100)
        let updatedAt = Date(timeIntervalSince1970: 200)
        let liveDay = WorkoutDay(
            id: "2026-08-15",
            dayStart: dayStart,
            lines: [
                WorkoutLine(
                    exerciseID: "squat",
                    exerciseName: "深蹲",
                    amount: 20,
                    unit: .reps,
                    createdAt: updatedAt
                )
            ],
            note: nil,
            updatedAt: updatedAt
        )
        let tombstone = WorkoutDay(
            id: liveDay.id,
            dayStart: dayStart,
            lines: [],
            note: nil,
            updatedAt: updatedAt
        )

        XCTAssertEqual(
            HiddenCloudMerge.workoutDays(primary: [tombstone], secondary: [liveDay]),
            [tombstone]
        )
        XCTAssertEqual(
            HiddenCloudMerge.workoutDays(primary: [liveDay], secondary: [tombstone]),
            [tombstone]
        )
    }

    func testDeletingLastLinePersistsNewerTombstone() throws {
        let store = InMemoryTrainingLogStore()
        let today = TrainingLogCalendar.startOfDay(Date())
        let key = TrainingLogCalendar.dayKey(for: today)
        let line = WorkoutLine(
            exerciseID: "pushup",
            exerciseName: "俯卧撑",
            amount: 10,
            unit: .reps
        )
        store.snapshot = TrainingLogSnapshot(days: [
            key: WorkoutDay(
                id: key,
                dayStart: today,
                lines: [line],
                note: nil,
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        ])
        let viewModel = TrainingLogViewModel(store: store)

        viewModel.deleteLine(id: line.id)

        let tombstone = try XCTUnwrap(store.snapshot.days[key])
        XCTAssertTrue(tombstone.isTombstone)
        XCTAssertGreaterThan(tombstone.updatedAt, Date(timeIntervalSince1970: 100))
    }
}
