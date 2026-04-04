import Foundation

enum QingLongStorage {
    static let panelProfileKey = "qinglong.panel_profile.v1"
}

struct QingLongPanelProfile: Codable, Hashable {
    let id: String
    let baseURL: URL
    let displayName: String
    let savedAt: Date
    let lastConnectedAt: Date?

    init(
        id: String = "default",
        baseURL: URL,
        displayName: String,
        savedAt: Date,
        lastConnectedAt: Date?
    ) {
        self.id = id
        self.baseURL = baseURL
        self.displayName = displayName
        self.savedAt = savedAt
        self.lastConnectedAt = lastConnectedAt
    }

    var hostLabel: String {
        if let host = baseURL.host {
            if let port = baseURL.port {
                return "\(host):\(port)"
            }
            return host
        }

        return baseURL.absoluteString
    }

    var syncActivityAt: Date {
        max(savedAt, lastConnectedAt ?? .distantPast)
    }

    func updatingConnection(at date: Date) -> QingLongPanelProfile {
        QingLongPanelProfile(
            id: id,
            baseURL: baseURL,
            displayName: displayName,
            savedAt: savedAt,
            lastConnectedAt: date
        )
    }
}

struct QingLongEnvironment: Identifiable, Hashable, Decodable {
    let id: Int
    let name: String
    let value: String
    let remarks: String
    let status: Int?
    let isPinnedValue: Int?
    let position: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case value
        case remarks
        case status
        case isPinnedValue = "isPinned"
        case position
    }

    init(
        id: Int,
        name: String,
        value: String,
        remarks: String,
        status: Int?,
        isPinnedValue: Int?,
        position: Int?
    ) {
        self.id = id
        self.name = name
        self.value = value
        self.remarks = remarks
        self.status = status
        self.isPinnedValue = isPinnedValue
        self.position = position
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeLossyInt(forKey: .id)
        name = (try container.decodeIfPresent(String.self, forKey: .name) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        value = try container.decodeIfPresent(String.self, forKey: .value) ?? ""
        remarks = (try container.decodeIfPresent(String.self, forKey: .remarks) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        status = try container.decodeLossyIntIfPresent(forKey: .status)
        isPinnedValue = try container.decodeLossyIntIfPresent(forKey: .isPinnedValue)
        position = try container.decodeLossyIntIfPresent(forKey: .position)
    }

    var isEnabled: Bool {
        status != 1
    }

    var isPinned: Bool {
        isPinnedValue == 1
    }

    var titleText: String {
        name.isEmpty ? "未命名变量" : name
    }

    var maskedValue: String {
        guard !value.isEmpty else { return "空值" }
        guard value.count > 12 else { return String(repeating: "•", count: max(value.count, 4)) }
        return "\(value.prefix(4))••••\(value.suffix(4))"
    }

    var isEmptyValue: Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func matches(scriptKey: String) -> Bool {
        name.compare(scriptKey, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    func hasScriptPrefix(_ scriptKey: String) -> Bool {
        name.lowercased().hasPrefix(scriptKey.lowercased() + "__")
    }

    static func sort(lhs: QingLongEnvironment, rhs: QingLongEnvironment) -> Bool {
        if lhs.isPinned != rhs.isPinned {
            return lhs.isPinned && !rhs.isPinned
        }

        if lhs.isEnabled != rhs.isEnabled {
            return lhs.isEnabled && !rhs.isEnabled
        }

        if lhs.position != rhs.position {
            return (lhs.position ?? .max) < (rhs.position ?? .max)
        }

        return lhs.titleText.localizedCaseInsensitiveCompare(rhs.titleText) == .orderedAscending
    }

    func updatingEnabled(_ enabled: Bool) -> QingLongEnvironment {
        QingLongEnvironment(
            id: id,
            name: name,
            value: value,
            remarks: remarks,
            status: enabled ? 0 : 1,
            isPinnedValue: isPinnedValue,
            position: position
        )
    }

    func updatingContent(name: String, value: String, remarks: String) -> QingLongEnvironment {
        QingLongEnvironment(
            id: id,
            name: name,
            value: value,
            remarks: remarks,
            status: status,
            isPinnedValue: isPinnedValue,
            position: position
        )
    }
}

struct QingLongCron: Identifiable, Hashable, Decodable {
    struct ExtraSchedule: Hashable, Codable {
        let schedule: String
    }

    struct ScriptLocation: Hashable {
        let path: String?
        let fileName: String
        let reference: String
    }

    let id: Int
    let name: String
    let command: String
    let schedule: String
    let statusValue: Double?
    let isDisabledValue: Int?
    let isPinnedValue: Int?
    let labels: [String]
    let lastRunningTime: Int64?
    let lastExecutionTime: Int64?
    let logPath: String
    let extraSchedules: [ExtraSchedule]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case command
        case schedule
        case statusValue = "status"
        case isDisabledValue = "isDisabled"
        case isPinnedValue = "isPinned"
        case labels
        case lastRunningTime = "last_running_time"
        case lastExecutionTime = "last_execution_time"
        case logPath = "log_path"
        case extraSchedules = "extra_schedules"
    }

    init(
        id: Int,
        name: String,
        command: String,
        schedule: String,
        statusValue: Double?,
        isDisabledValue: Int?,
        isPinnedValue: Int?,
        labels: [String],
        lastRunningTime: Int64?,
        lastExecutionTime: Int64?,
        logPath: String,
        extraSchedules: [ExtraSchedule]
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.schedule = schedule
        self.statusValue = statusValue
        self.isDisabledValue = isDisabledValue
        self.isPinnedValue = isPinnedValue
        self.labels = labels
        self.lastRunningTime = lastRunningTime
        self.lastExecutionTime = lastExecutionTime
        self.logPath = logPath
        self.extraSchedules = extraSchedules
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeLossyInt(forKey: .id)
        name = (try container.decodeIfPresent(String.self, forKey: .name) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        command = (try container.decodeIfPresent(String.self, forKey: .command) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        schedule = (try container.decodeIfPresent(String.self, forKey: .schedule) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        statusValue = try container.decodeLossyDoubleIfPresent(forKey: .statusValue)
        isDisabledValue = try container.decodeLossyIntIfPresent(forKey: .isDisabledValue)
        isPinnedValue = try container.decodeLossyIntIfPresent(forKey: .isPinnedValue)
        labels = try container.decodeIfPresent([String].self, forKey: .labels) ?? []
        lastRunningTime = try container.decodeLossyInt64IfPresent(forKey: .lastRunningTime)
        lastExecutionTime = try container.decodeLossyInt64IfPresent(forKey: .lastExecutionTime)
        logPath = try container.decodeIfPresent(String.self, forKey: .logPath) ?? ""
        extraSchedules = try container.decodeIfPresent([ExtraSchedule].self, forKey: .extraSchedules) ?? []
    }

    var primaryTitle: String {
        name.isEmpty ? command : name
    }

    var scriptReference: String? {
        Self.scriptReference(from: command)
    }

    var scriptLocation: ScriptLocation? {
        guard let reference = scriptReference else { return nil }

        let normalizedReference = reference
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedReference.isEmpty else { return nil }

        let fileName = (normalizedReference as NSString).lastPathComponent
        guard !fileName.isEmpty else { return nil }

        let parentPath = (normalizedReference as NSString).deletingLastPathComponent
        let resolvedPath: String?
        if parentPath.isEmpty || parentPath == "." {
            resolvedPath = nil
        } else {
            resolvedPath = parentPath
        }

        return ScriptLocation(path: resolvedPath, fileName: fileName, reference: normalizedReference)
    }

    var scriptEnvironmentKey: String? {
        if let scriptReference {
            return Self.environmentKey(from: scriptReference)
        }

        guard !name.isEmpty else { return nil }
        return Self.environmentKey(from: name)
    }

    var secondaryTitle: String {
        name.isEmpty ? "" : command
    }

    var isEnabled: Bool {
        isDisabledValue != 1
    }

    var isPinned: Bool {
        isPinnedValue == 1
    }

    var isRunning: Bool {
        (statusValue ?? 1) == 0
    }

    var isQueued: Bool {
        statusValue == 0.5
    }

    var statusText: String {
        if !isEnabled {
            return "已禁用"
        }

        if isRunning {
            return "运行中"
        }

        if isQueued {
            return "排队中"
        }

        return "空闲"
    }

    var lastRunningAt: Date? {
        Self.date(from: lastRunningTime)
    }

    var lastExecutedAt: Date? {
        Self.date(from: lastExecutionTime) ?? lastRunningAt
    }

    var hasLog: Bool {
        !logPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func sort(lhs: QingLongCron, rhs: QingLongCron) -> Bool {
        if lhs.isPinned != rhs.isPinned {
            return lhs.isPinned && !rhs.isPinned
        }

        if lhs.isRunning != rhs.isRunning {
            return lhs.isRunning && !rhs.isRunning
        }

        if lhs.isEnabled != rhs.isEnabled {
            return lhs.isEnabled && !rhs.isEnabled
        }

        if lhs.lastExecutedAt != rhs.lastExecutedAt {
            return (lhs.lastExecutedAt ?? .distantPast) > (rhs.lastExecutedAt ?? .distantPast)
        }

        return lhs.primaryTitle.localizedCaseInsensitiveCompare(rhs.primaryTitle) == .orderedAscending
    }

    func updatingEnabled(_ enabled: Bool) -> QingLongCron {
        QingLongCron(
            id: id,
            name: name,
            command: command,
            schedule: schedule,
            statusValue: statusValue,
            isDisabledValue: enabled ? 0 : 1,
            isPinnedValue: isPinnedValue,
            labels: labels,
            lastRunningTime: lastRunningTime,
            lastExecutionTime: lastExecutionTime,
            logPath: logPath,
            extraSchedules: extraSchedules
        )
    }

    func updatingRunning(_ running: Bool, at date: Date = Date()) -> QingLongCron {
        QingLongCron(
            id: id,
            name: name,
            command: command,
            schedule: schedule,
            statusValue: running ? 0 : 1,
            isDisabledValue: isDisabledValue,
            isPinnedValue: isPinnedValue,
            labels: labels,
            lastRunningTime: running ? Int64(date.timeIntervalSince1970 * 1000) : lastRunningTime,
            lastExecutionTime: lastExecutionTime,
            logPath: logPath,
            extraSchedules: extraSchedules
        )
    }

    func updatingSchedule(_ schedule: String) -> QingLongCron {
        QingLongCron(
            id: id,
            name: name,
            command: command,
            schedule: schedule,
            statusValue: statusValue,
            isDisabledValue: isDisabledValue,
            isPinnedValue: isPinnedValue,
            labels: labels,
            lastRunningTime: lastRunningTime,
            lastExecutionTime: lastExecutionTime,
            logPath: logPath,
            extraSchedules: extraSchedules
        )
    }

    private static func date(from rawValue: Int64?) -> Date? {
        guard let rawValue, rawValue > 0 else { return nil }
        let timeInterval: TimeInterval
        if rawValue > 1_000_000_000_000 {
            timeInterval = TimeInterval(rawValue) / 1000
        } else {
            timeInterval = TimeInterval(rawValue)
        }
        return Date(timeIntervalSince1970: timeInterval)
    }

    private static func scriptReference(from command: String) -> String? {
        let scriptExtensions = Set(["js", "mjs", "cjs", "py", "sh", "ts", "bash", "zsh", "ps1"])
        let tokens = command
            .split(whereSeparator: \.isWhitespace)
            .map {
                String($0)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`()[]{};,"))
            }
            .filter { !$0.isEmpty }

        for token in tokens {
            let normalizedToken = token
                .replacingOccurrences(of: "\\", with: "/")
                .components(separatedBy: "?")
                .first?
                .components(separatedBy: "#")
                .first ?? token
            let extensionName = URL(fileURLWithPath: normalizedToken).pathExtension.lowercased()
            if scriptExtensions.contains(extensionName) {
                return normalizedToken
            }
        }

        return nil
    }

    private static func environmentKey(from source: String) -> String? {
        let normalizedSource = source
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSource.isEmpty else { return nil }

        let fileName = URL(fileURLWithPath: normalizedSource).deletingPathExtension().lastPathComponent
        guard !fileName.isEmpty else { return nil }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        let mappedScalars = fileName.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }

        var result = String(mappedScalars)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        guard !result.isEmpty else { return nil }

        if let firstScalar = result.unicodeScalars.first, CharacterSet.decimalDigits.contains(firstScalar) {
            result = "_" + result
        }

        return result
    }
}

struct QingLongSubscriptionIntervalSchedule: Hashable, Codable {
    let type: String
    let value: Int
}

struct QingLongSubscription: Identifiable, Hashable, Decodable {
    let id: Int
    let name: String
    let type: String
    let scheduleType: String
    let schedule: String
    let intervalSchedule: QingLongSubscriptionIntervalSchedule?
    let url: String
    let branch: String
    let statusValue: Int?
    let pid: Int?
    let isDisabledValue: Int?
    let logPath: String
    let alias: String
    let autoAddCronValue: Int?
    let autoDelCronValue: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case scheduleType = "schedule_type"
        case schedule
        case intervalSchedule = "interval_schedule"
        case url
        case branch
        case statusValue = "status"
        case pid
        case isDisabledValue = "is_disabled"
        case logPath = "log_path"
        case alias
        case autoAddCronValue = "autoAddCron"
        case autoDelCronValue = "autoDelCron"
    }

    init(
        id: Int,
        name: String,
        type: String,
        scheduleType: String,
        schedule: String,
        intervalSchedule: QingLongSubscriptionIntervalSchedule?,
        url: String,
        branch: String,
        statusValue: Int?,
        pid: Int?,
        isDisabledValue: Int?,
        logPath: String,
        alias: String,
        autoAddCronValue: Int?,
        autoDelCronValue: Int?
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.scheduleType = scheduleType
        self.schedule = schedule
        self.intervalSchedule = intervalSchedule
        self.url = url
        self.branch = branch
        self.statusValue = statusValue
        self.pid = pid
        self.isDisabledValue = isDisabledValue
        self.logPath = logPath
        self.alias = alias
        self.autoAddCronValue = autoAddCronValue
        self.autoDelCronValue = autoDelCronValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeLossyInt(forKey: .id)
        name = (try container.decodeIfPresent(String.self, forKey: .name) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        type = (try container.decodeIfPresent(String.self, forKey: .type) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        scheduleType = (try container.decodeIfPresent(String.self, forKey: .scheduleType) ?? "crontab")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        schedule = (try container.decodeIfPresent(String.self, forKey: .schedule) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        intervalSchedule = try container.decodeIfPresent(QingLongSubscriptionIntervalSchedule.self, forKey: .intervalSchedule)
        url = (try container.decodeIfPresent(String.self, forKey: .url) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        branch = (try container.decodeIfPresent(String.self, forKey: .branch) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        statusValue = try container.decodeLossyIntIfPresent(forKey: .statusValue)
        pid = try container.decodeLossyIntIfPresent(forKey: .pid)
        isDisabledValue = try container.decodeLossyIntIfPresent(forKey: .isDisabledValue)
        logPath = (try container.decodeIfPresent(String.self, forKey: .logPath) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        alias = (try container.decodeIfPresent(String.self, forKey: .alias) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        autoAddCronValue = try container.decodeLossyIntIfPresent(forKey: .autoAddCronValue)
        autoDelCronValue = try container.decodeLossyIntIfPresent(forKey: .autoDelCronValue)
    }

    var titleText: String {
        if !name.isEmpty {
            return name
        }

        if !alias.isEmpty {
            return alias
        }

        return url.isEmpty ? "未命名订阅" : url
    }

    var detailText: String {
        let parts = [typeText, branch.isEmpty ? nil : branch].compactMap { $0 }
        return parts.isEmpty ? "未设置" : parts.joined(separator: " · ")
    }

    var scheduleText: String {
        guard scheduleType == "interval" else {
            return schedule.isEmpty ? "未设置" : schedule
        }

        guard let intervalSchedule else { return "未设置" }
        return "每\(intervalSchedule.value)\(intervalUnitText)"
    }

    var typeText: String {
        switch type {
        case "private-repo":
            return "私有仓库"
        case "public-repo":
            return "公开仓库"
        case "file":
            return "单文件"
        default:
            return type.isEmpty ? "未知类型" : type
        }
    }

    var isEnabled: Bool {
        isDisabledValue != 1
    }

    var isRunning: Bool {
        statusValue == 0
    }

    var isQueued: Bool {
        statusValue == 3
    }

    var statusText: String {
        if isRunning {
            return "拉取中"
        }

        if isQueued {
            return "排队中"
        }

        if !isEnabled {
            return "已禁用"
        }

        return "空闲"
    }

    var hasLog: Bool {
        !logPath.isEmpty
    }

    var autoAddCron: Bool {
        autoAddCronValue == 1
    }

    var autoDelCron: Bool {
        autoDelCronValue == 1
    }

    static func sort(lhs: QingLongSubscription, rhs: QingLongSubscription) -> Bool {
        if lhs.isRunning != rhs.isRunning {
            return lhs.isRunning && !rhs.isRunning
        }

        if lhs.isQueued != rhs.isQueued {
            return lhs.isQueued && !rhs.isQueued
        }

        if lhs.isEnabled != rhs.isEnabled {
            return lhs.isEnabled && !rhs.isEnabled
        }

        return lhs.titleText.localizedCaseInsensitiveCompare(rhs.titleText) == .orderedAscending
    }

    func updatingEnabled(_ enabled: Bool) -> QingLongSubscription {
        QingLongSubscription(
            id: id,
            name: name,
            type: type,
            scheduleType: scheduleType,
            schedule: schedule,
            intervalSchedule: intervalSchedule,
            url: url,
            branch: branch,
            statusValue: statusValue,
            pid: pid,
            isDisabledValue: enabled ? 0 : 1,
            logPath: logPath,
            alias: alias,
            autoAddCronValue: autoAddCronValue,
            autoDelCronValue: autoDelCronValue
        )
    }

    func updatingRunning(_ running: Bool) -> QingLongSubscription {
        QingLongSubscription(
            id: id,
            name: name,
            type: type,
            scheduleType: scheduleType,
            schedule: schedule,
            intervalSchedule: intervalSchedule,
            url: url,
            branch: branch,
            statusValue: running ? 0 : 1,
            pid: running ? (pid ?? 1) : nil,
            isDisabledValue: isDisabledValue,
            logPath: logPath,
            alias: alias,
            autoAddCronValue: autoAddCronValue,
            autoDelCronValue: autoDelCronValue
        )
    }

    private var intervalUnitText: String {
        switch intervalSchedule?.type {
        case "days":
            return "天"
        case "hours":
            return "小时"
        case "minutes":
            return "分钟"
        case "seconds":
            return "秒"
        default:
            return "次"
        }
    }
}

struct QingLongDashboardSnapshot: Hashable {
    let profile: QingLongPanelProfile
    let environments: [QingLongEnvironment]
    let crons: [QingLongCron]
    let subscriptions: [QingLongSubscription]
    let fetchedAt: Date
}

extension KeyedDecodingContainer {
    func decodeLossyInt(forKey key: Key) throws -> Int {
        if let value = try decodeLossyIntIfPresent(forKey: key) {
            return value
        }

        throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Expected Int-compatible value.")
    }

    func decodeLossyIntIfPresent(forKey key: Key) throws -> Int? {
        if let intValue = try decodeIfPresent(Int.self, forKey: key) {
            return intValue
        }

        if let int64Value = try decodeIfPresent(Int64.self, forKey: key) {
            return Int(int64Value)
        }

        if let doubleValue = try decodeIfPresent(Double.self, forKey: key) {
            return Int(doubleValue)
        }

        if let stringValue = try decodeIfPresent(String.self, forKey: key) {
            return Int(stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return nil
    }

    func decodeLossyInt64IfPresent(forKey key: Key) throws -> Int64? {
        if let int64Value = try decodeIfPresent(Int64.self, forKey: key) {
            return int64Value
        }

        if let intValue = try decodeIfPresent(Int.self, forKey: key) {
            return Int64(intValue)
        }

        if let doubleValue = try decodeIfPresent(Double.self, forKey: key) {
            return Int64(doubleValue)
        }

        if let stringValue = try decodeIfPresent(String.self, forKey: key) {
            return Int64(stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return nil
    }

    func decodeLossyDoubleIfPresent(forKey key: Key) throws -> Double? {
        if let doubleValue = try decodeIfPresent(Double.self, forKey: key) {
            return doubleValue
        }

        if let intValue = try decodeIfPresent(Int.self, forKey: key) {
            return Double(intValue)
        }

        if let stringValue = try decodeIfPresent(String.self, forKey: key) {
            return Double(stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return nil
    }
}
