import Foundation

enum TrainingLogStorage {
    static let snapshotKey = "training_log.snapshot.v1"
}

extension Notification.Name {
    static let trainingLogDidChange = Notification.Name("trainingLogDidChange")
}

enum ExerciseUnit: String, Codable, Hashable, CaseIterable {
    case reps
    case seconds

    var shortLabel: String {
        switch self {
        case .reps: return "次"
        case .seconds: return "秒"
        }
    }
}

struct ExerciseCategory: Identifiable, Hashable {
    let id: String
    let name: String
    let systemImage: String
}

struct ExerciseDefinition: Identifiable, Hashable {
    let id: String
    let name: String
    let categoryID: String
    let unit: ExerciseUnit
    let defaultAmount: Int
    let suggestedAmounts: [Int]
}

struct WorkoutLine: Identifiable, Codable, Hashable {
    var id: UUID
    var exerciseID: String
    var exerciseName: String
    var amount: Int
    var unit: ExerciseUnit
    var createdAt: Date

    init(
        id: UUID = UUID(),
        exerciseID: String,
        exerciseName: String,
        amount: Int,
        unit: ExerciseUnit,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.amount = amount
        self.unit = unit
        self.createdAt = createdAt
    }

    var amountText: String {
        "\(amount)\(unit.shortLabel)"
    }

    var displayText: String {
        "\(exerciseName) \(amountText)"
    }
}

struct WorkoutDay: Identifiable, Codable, Hashable {
    /// yyyy-MM-dd key
    var id: String
    var dayStart: Date
    var lines: [WorkoutLine]
    var note: String?

    var hasTraining: Bool { !lines.isEmpty }

    var totalLines: Int { lines.count }

    var uniqueExerciseCount: Int {
        Set(lines.map(\.exerciseID)).count
    }
}

struct TrainingLogSnapshot: Codable, Hashable {
    var days: [String: WorkoutDay]

    init(days: [String: WorkoutDay] = [:]) {
        self.days = days
    }
}

enum TrainingExerciseLibrary {
    static let categories: [ExerciseCategory] = [
        .init(id: "push", name: "上肢推", systemImage: "arrow.up.circle.fill"),
        .init(id: "pull", name: "上肢拉", systemImage: "arrow.down.circle.fill"),
        .init(id: "legs", name: "下肢", systemImage: "figure.walk"),
        .init(id: "core", name: "核心", systemImage: "circle.grid.cross.fill"),
        .init(id: "cardio", name: "有氧", systemImage: "figure.run"),
        .init(id: "mobility", name: "柔韧", systemImage: "leaf.fill")
    ]

    static let exercises: [ExerciseDefinition] = [
        // 上肢推
        .init(id: "pushup", name: "俯卧撑", categoryID: "push", unit: .reps, defaultAmount: 10, suggestedAmounts: [5, 10, 15, 20]),
        .init(id: "knee-pushup", name: "跪姿俯卧撑", categoryID: "push", unit: .reps, defaultAmount: 12, suggestedAmounts: [8, 12, 15, 20]),
        .init(id: "diamond-pushup", name: "钻石俯卧撑", categoryID: "push", unit: .reps, defaultAmount: 8, suggestedAmounts: [5, 8, 10, 12]),
        .init(id: "pike-pushup", name: "派克俯卧撑", categoryID: "push", unit: .reps, defaultAmount: 8, suggestedAmounts: [5, 8, 10, 12]),
        .init(id: "shoulder-tap", name: "肩碰触", categoryID: "push", unit: .reps, defaultAmount: 16, suggestedAmounts: [10, 16, 20, 30]),

        // 上肢拉 / 背
        .init(id: "superman", name: "超人式", categoryID: "pull", unit: .reps, defaultAmount: 12, suggestedAmounts: [8, 12, 15, 20]),
        .init(id: "reverse-snow-angel", name: "反向雪天使", categoryID: "pull", unit: .reps, defaultAmount: 12, suggestedAmounts: [8, 12, 15, 20]),
        .init(id: "doorway-row", name: "门框划船", categoryID: "pull", unit: .reps, defaultAmount: 10, suggestedAmounts: [8, 10, 12, 15]),
        .init(id: "scapular-retract", name: "肩胛后缩", categoryID: "pull", unit: .reps, defaultAmount: 15, suggestedAmounts: [10, 15, 20, 25]),

        // 下肢
        .init(id: "squat", name: "深蹲", categoryID: "legs", unit: .reps, defaultAmount: 15, suggestedAmounts: [10, 15, 20, 25]),
        .init(id: "lunge", name: "弓步蹲", categoryID: "legs", unit: .reps, defaultAmount: 12, suggestedAmounts: [8, 12, 16, 20]),
        .init(id: "glute-bridge", name: "臀桥", categoryID: "legs", unit: .reps, defaultAmount: 15, suggestedAmounts: [10, 15, 20, 25]),
        .init(id: "calf-raise", name: "提踵", categoryID: "legs", unit: .reps, defaultAmount: 20, suggestedAmounts: [15, 20, 25, 30]),
        .init(id: "wall-sit", name: "靠墙静蹲", categoryID: "legs", unit: .seconds, defaultAmount: 40, suggestedAmounts: [20, 30, 40, 60]),

        // 核心
        .init(id: "plank", name: "平板支撑", categoryID: "core", unit: .seconds, defaultAmount: 40, suggestedAmounts: [20, 30, 40, 60]),
        .init(id: "side-plank", name: "侧平板", categoryID: "core", unit: .seconds, defaultAmount: 25, suggestedAmounts: [15, 20, 25, 40]),
        .init(id: "crunch", name: "卷腹", categoryID: "core", unit: .reps, defaultAmount: 15, suggestedAmounts: [10, 15, 20, 30]),
        .init(id: "leg-raise", name: "仰卧举腿", categoryID: "core", unit: .reps, defaultAmount: 12, suggestedAmounts: [8, 12, 15, 20]),
        .init(id: "dead-bug", name: "死虫", categoryID: "core", unit: .reps, defaultAmount: 12, suggestedAmounts: [8, 12, 16, 20]),
        .init(id: "mountain-climber", name: "登山者", categoryID: "core", unit: .reps, defaultAmount: 20, suggestedAmounts: [16, 20, 30, 40]),

        // 有氧
        .init(id: "jumping-jack", name: "开合跳", categoryID: "cardio", unit: .reps, defaultAmount: 30, suggestedAmounts: [20, 30, 40, 50]),
        .init(id: "high-knees", name: "高抬腿", categoryID: "cardio", unit: .seconds, defaultAmount: 30, suggestedAmounts: [20, 30, 40, 60]),
        .init(id: "burpee", name: "波比跳", categoryID: "cardio", unit: .reps, defaultAmount: 8, suggestedAmounts: [5, 8, 10, 12]),
        .init(id: "shadow-boxing", name: "空击", categoryID: "cardio", unit: .seconds, defaultAmount: 45, suggestedAmounts: [30, 45, 60, 90]),
        .init(id: "march-in-place", name: "原地踏步", categoryID: "cardio", unit: .seconds, defaultAmount: 60, suggestedAmounts: [30, 60, 90, 120]),

        // 柔韧
        .init(id: "forward-fold", name: "站立体前屈", categoryID: "mobility", unit: .seconds, defaultAmount: 30, suggestedAmounts: [20, 30, 45, 60]),
        .init(id: "hip-opener", name: "髋部开合", categoryID: "mobility", unit: .seconds, defaultAmount: 30, suggestedAmounts: [20, 30, 45, 60]),
        .init(id: "cat-cow", name: "猫牛式", categoryID: "mobility", unit: .reps, defaultAmount: 10, suggestedAmounts: [8, 10, 12, 15]),
        .init(id: "world-greatest-stretch", name: "世界最伟大拉伸", categoryID: "mobility", unit: .reps, defaultAmount: 6, suggestedAmounts: [4, 6, 8, 10]),
        .init(id: "shoulder-opener", name: "肩部环绕", categoryID: "mobility", unit: .reps, defaultAmount: 12, suggestedAmounts: [8, 12, 15, 20])
    ]

    static func category(id: String) -> ExerciseCategory? {
        categories.first { $0.id == id }
    }

    static func exercise(id: String) -> ExerciseDefinition? {
        exercises.first { $0.id == id }
    }

    static func exercises(in categoryID: String) -> [ExerciseDefinition] {
        exercises.filter { $0.categoryID == categoryID }
    }
}

enum TrainingLogCalendar {
    static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "zh_CN")
        cal.firstWeekday = 2 // Monday
        return cal
    }()

    static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let monthTitleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月"
        return f
    }()

    static let dayTitleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEEE"
        return f
    }()

    static func dayKey(for date: Date) -> String {
        dayKeyFormatter.string(from: startOfDay(date))
    }

    static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    static func startOfMonth(_ date: Date) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: comps) ?? startOfDay(date)
    }

    static func endOfMonth(_ date: Date) -> Date {
        guard let next = calendar.date(byAdding: .month, value: 1, to: startOfMonth(date)) else {
            return startOfDay(date)
        }
        return calendar.date(byAdding: .second, value: -1, to: next) ?? next
    }

    /// Leading placeholders + days in month for a 7-column grid.
    static func monthGridDays(for month: Date) -> [Date?] {
        let monthStart = startOfMonth(month)
        let daysInMonth = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let weekday = calendar.component(.weekday, from: monthStart)
        // Convert to Monday-first index 0...6
        let leading = (weekday - calendar.firstWeekday + 7) % 7

        var result: [Date?] = Array(repeating: nil, count: leading)
        for day in 1...daysInMonth {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) {
                result.append(date)
            }
        }
        while result.count % 7 != 0 {
            result.append(nil)
        }
        return result
    }
}
