import Foundation

enum QingLongCronFilter: String, CaseIterable, Identifiable {
    case all
    case running
    case disabled

    var id: Self { self }

    var title: String {
        switch self {
        case .all:
            return "全部"
        case .running:
            return "运行中"
        case .disabled:
            return "已禁用"
        }
    }
}

enum QingLongSubscriptionFilter: String, CaseIterable, Identifiable {
    case all
    case running
    case disabled

    var id: Self { self }

    var title: String {
        switch self {
        case .all:
            return "全部"
        case .running:
            return "拉取中"
        case .disabled:
            return "已禁用"
        }
    }
}

enum QingLongLinkedEnvironmentStatus: Hashable {
    case missing
    case empty
    case configured
}

struct QingLongLinkedEnvironment: Hashable {
    let scriptKey: String
    let primaryEnvironment: QingLongEnvironment?
    let auxiliaryCount: Int

    var status: QingLongLinkedEnvironmentStatus {
        guard let primaryEnvironment else { return .missing }
        return primaryEnvironment.isEmptyValue ? .empty : .configured
    }
}

struct QingLongEnvironmentEditorContext: Identifiable, Hashable {
    enum Scope: Hashable {
        case script(cronTitle: String, scriptKey: String)
        case shared
    }

    let id = UUID()
    let scope: Scope
    let environment: QingLongEnvironment?
    let suggestedName: String
    let suggestedRemarks: String

    var title: String {
        switch scope {
        case .script:
            return environment == nil ? "新建脚本变量" : "编辑脚本变量"
        case .shared:
            return environment == nil ? "新建共享变量" : "编辑共享变量"
        }
    }

    var subtitle: String? {
        switch scope {
        case let .script(cronTitle, scriptKey):
            return "\(cronTitle) · \(scriptKey)"
        case .shared:
            return nil
        }
    }

    var allowsNameEditing: Bool {
        switch scope {
        case .script:
            return false
        case .shared:
            return true
        }
    }

    var initialName: String {
        environment?.name ?? suggestedName
    }

    var initialValue: String {
        environment?.value ?? ""
    }

    var initialRemarks: String {
        environment?.remarks ?? suggestedRemarks
    }
}

struct QingLongCronEditorContext: Identifiable, Hashable {
    let id = UUID()
    let cronID: Int
    let title: String
    let initialSchedule: String
}

struct QingLongCronLog: Identifiable, Hashable {
    let id: Int
    let title: String
    let content: String
}

struct QingLongSubscriptionLog: Identifiable, Hashable {
    let id: Int
    let title: String
    let content: String
}

enum QingLongStatusTone: Hashable {
    case success
    case info
    case error
}

struct QingLongStatusState: Hashable {
    let message: String
    let tone: QingLongStatusTone
}

@MainActor
final class QingLongViewModel: ObservableObject {
    private var savedBaseURLString = ""
    private var savedClientID = ""
    private var savedClientSecret = ""
    private var deferredRefreshTask: Task<Void, Never>?

    @Published var draftBaseURL = ""
    @Published var draftClientID = ""
    @Published var draftClientSecret = ""
    @Published var cronSearchText = ""
    @Published var cronFilter: QingLongCronFilter = .all
    @Published var subscriptionSearchText = ""
    @Published var subscriptionFilter: QingLongSubscriptionFilter = .all
    @Published private(set) var profile: QingLongPanelProfile?
    @Published private(set) var environments: [QingLongEnvironment] = []
    @Published private(set) var crons: [QingLongCron] = []
    @Published private(set) var subscriptions: [QingLongSubscription] = []
    @Published private(set) var lastRefreshedAt: Date?
    @Published private(set) var isPreparing = false
    @Published private(set) var isConnecting = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var isRunningDiagnostics = false
    @Published private(set) var pendingEnvironmentIDs: Set<Int> = []
    @Published private(set) var pendingCronIDs: Set<Int> = []
    @Published private(set) var pendingSubscriptionIDs: Set<Int> = []
    @Published private(set) var loadingCronLogID: Int?
    @Published private(set) var loadingSubscriptionLogID: Int?
    @Published private(set) var statusState: QingLongStatusState?
    @Published var selectedCronLog: QingLongCronLog?
    @Published var selectedSubscriptionLog: QingLongSubscriptionLog?
    @Published var diagnosticReport: QingLongDiagnosticReport?

    var isBusy: Bool {
        isPreparing ||
            isConnecting ||
            isRefreshing ||
            isRunningDiagnostics ||
            loadingCronLogID != nil ||
            loadingSubscriptionLogID != nil ||
            !pendingEnvironmentIDs.isEmpty ||
            !pendingCronIDs.isEmpty ||
            !pendingSubscriptionIDs.isEmpty
    }

    var filteredCrons: [QingLongCron] {
        let query = normalizedQuery(cronSearchText)

        return crons.filter { cron in
            let matchesFilter: Bool
            switch cronFilter {
            case .all:
                matchesFilter = true
            case .running:
                matchesFilter = cron.isRunning
            case .disabled:
                matchesFilter = !cron.isEnabled
            }

            guard matchesFilter else { return false }
            guard !query.isEmpty else { return true }

            let linkedEnvironment = linkedEnvironment(for: cron)
            return [
                cron.primaryTitle,
                cron.secondaryTitle,
                cron.command,
                cron.schedule,
                cron.labels.joined(separator: " "),
                cron.scriptEnvironmentKey ?? "",
                linkedEnvironment?.primaryEnvironment?.remarks ?? ""
            ]
            .joined(separator: " ")
            .localizedCaseInsensitiveContains(query)
        }
    }

    var filteredSubscriptions: [QingLongSubscription] {
        let query = normalizedQuery(subscriptionSearchText)

        return subscriptions.filter { subscription in
            let matchesFilter: Bool
            switch subscriptionFilter {
            case .all:
                matchesFilter = true
            case .running:
                matchesFilter = subscription.isRunning || subscription.isQueued
            case .disabled:
                matchesFilter = !subscription.isEnabled
            }

            guard matchesFilter else { return false }
            guard !query.isEmpty else { return true }

            return [
                subscription.titleText,
                subscription.alias,
                subscription.typeText,
                subscription.url,
                subscription.branch,
                subscription.scheduleText
            ]
            .joined(separator: " ")
            .localizedCaseInsensitiveContains(query)
        }
    }

    var sharedEnvironments: [QingLongEnvironment] {
        environments.filter(isSharedEnvironment(_:))
    }

    var sharedEnvironmentCount: Int {
        sharedEnvironments.count
    }

    func prepare() async {
        isPreparing = true
        defer { isPreparing = false }

        let storedConfiguration = await QingLongService.shared.loadStoredConfiguration()
        applyStoredConfiguration(storedConfiguration)

        guard storedConfiguration.profile != nil else { return }
        await refresh(showStatus: false)
    }

    func connect() async {
        isConnecting = true
        defer { isConnecting = false }

        do {
            let snapshot = try await QingLongService.shared.connect(
                baseURLString: draftBaseURL,
                clientID: draftClientID,
                clientSecret: draftClientSecret
            )
            applySnapshot(snapshot)
            rememberCurrentDraftsAsSaved()
            await CloudSyncViewModel.shared.syncQingLongProfileUpsertIfPossible(snapshot.profile)
            setStatus(
                "已连接 \(snapshot.profile.displayName)，已同步 \(snapshot.environments.count) 个变量、\(snapshot.crons.count) 个任务和 \(snapshot.subscriptions.count) 个订阅。",
                tone: .success
            )
        } catch {
            presentError(error)
        }
    }

    func refresh(showStatus: Bool = true, tracksActivity: Bool = true) async {
        if tracksActivity {
            isRefreshing = true
        }
        defer {
            if tracksActivity {
                isRefreshing = false
            }
        }

        do {
            let snapshot = try await QingLongService.shared.refreshDashboard()
            applySnapshot(snapshot)
            await CloudSyncViewModel.shared.syncQingLongProfileUpsertIfPossible(snapshot.profile)
            if showStatus {
                setStatus("已刷新 \(snapshot.profile.displayName)。", tone: .info)
            }
        } catch {
            if showStatus {
                presentError(error)
            }
        }
    }

    func disconnect() async {
        deferredRefreshTask?.cancel()
        let disconnectedProfile = profile
        await QingLongService.shared.disconnect()
        profile = nil
        environments = []
        crons = []
        subscriptions = []
        lastRefreshedAt = nil
        draftBaseURL = ""
        draftClientID = ""
        draftClientSecret = ""
        savedBaseURLString = ""
        savedClientID = ""
        savedClientSecret = ""
        pendingEnvironmentIDs = []
        pendingCronIDs = []
        pendingSubscriptionIDs = []
        loadingCronLogID = nil
        loadingSubscriptionLogID = nil
        selectedCronLog = nil
        selectedSubscriptionLog = nil
        diagnosticReport = nil
        cronSearchText = ""
        cronFilter = .all
        subscriptionSearchText = ""
        subscriptionFilter = .all
        if let disconnectedProfile {
            await CloudSyncViewModel.shared.syncQingLongProfileDeletionIfPossible(profileID: disconnectedProfile.id)
        }
        setStatus("已移除青龙面板配置。", tone: .info)
    }

    func runDiagnostics() async {
        isRunningDiagnostics = true
        defer { isRunningDiagnostics = false }

        do {
            diagnosticReport = try await QingLongService.shared.diagnoseConnection(
                baseURLString: draftBaseURL,
                clientID: draftClientID,
                clientSecret: draftClientSecret
            )
            setStatus("已生成连接诊断。", tone: .info)
        } catch {
            presentError(error)
        }
    }

    func setEnvironmentEnabled(_ environment: QingLongEnvironment, enabled: Bool) async {
        pendingEnvironmentIDs.insert(environment.id)
        defer { pendingEnvironmentIDs.remove(environment.id) }

        do {
            try await QingLongService.shared.setEnvironmentEnabled(id: environment.id, enabled: enabled)
            replaceEnvironment(environment.id) { $0.updatingEnabled(enabled) }
            setStatus(enabled ? "已启用 \(environment.titleText)" : "已禁用 \(environment.titleText)", tone: .success)
            scheduleBackgroundRefresh()
        } catch {
            presentError(error)
        }
    }

    func linkedEnvironment(for cron: QingLongCron) -> QingLongLinkedEnvironment? {
        guard let scriptKey = cron.scriptEnvironmentKey else { return nil }

        let primaryEnvironment = environments.first { $0.matches(scriptKey: scriptKey) }
        let auxiliaryCount = environments.filter { $0.hasScriptPrefix(scriptKey) }.count
        return QingLongLinkedEnvironment(
            scriptKey: scriptKey,
            primaryEnvironment: primaryEnvironment,
            auxiliaryCount: auxiliaryCount
        )
    }

    func makeScriptEnvironmentEditor(for cron: QingLongCron) -> QingLongEnvironmentEditorContext? {
        guard let linkedEnvironment = linkedEnvironment(for: cron) else { return nil }
        return QingLongEnvironmentEditorContext(
            scope: .script(cronTitle: cron.primaryTitle, scriptKey: linkedEnvironment.scriptKey),
            environment: linkedEnvironment.primaryEnvironment,
            suggestedName: linkedEnvironment.scriptKey,
            suggestedRemarks: cron.primaryTitle
        )
    }

    func makeSharedEnvironmentEditor(for environment: QingLongEnvironment? = nil) -> QingLongEnvironmentEditorContext {
        QingLongEnvironmentEditorContext(
            scope: .shared,
            environment: environment,
            suggestedName: environment?.name ?? "",
            suggestedRemarks: environment?.remarks ?? ""
        )
    }

    func saveEnvironment(
        using context: QingLongEnvironmentEditorContext,
        name: String,
        value: String,
        remarks: String
    ) async -> Bool {
        let resolvedName = context.allowsNameEditing ? normalizedQuery(name) : context.suggestedName
        guard !resolvedName.isEmpty else {
            setStatus("变量名不能为空。", tone: .error)
            return false
        }

        guard isValidEnvironmentName(resolvedName) else {
            setStatus("变量名只支持字母、数字和下划线，且不能以数字开头。", tone: .error)
            return false
        }

        let resolvedRemarks = remarks.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let environment: QingLongEnvironment

            if let existingEnvironment = context.environment {
                pendingEnvironmentIDs.insert(existingEnvironment.id)
                defer { pendingEnvironmentIDs.remove(existingEnvironment.id) }

                environment = try await QingLongService.shared.updateEnvironment(
                    id: existingEnvironment.id,
                    name: resolvedName,
                    value: value,
                    remarks: resolvedRemarks
                )
            } else {
                environment = try await QingLongService.shared.createEnvironment(
                    name: resolvedName,
                    value: value,
                    remarks: resolvedRemarks
                )
            }

            upsertEnvironment(environment)
            setStatus(context.environment == nil ? "已创建 \(resolvedName)" : "已更新 \(resolvedName)", tone: .success)
            scheduleBackgroundRefresh()
            return true
        } catch {
            presentError(error)
            return false
        }
    }

    func runCron(_ cron: QingLongCron) async {
        pendingCronIDs.insert(cron.id)
        defer { pendingCronIDs.remove(cron.id) }

        do {
            try await QingLongService.shared.runCron(id: cron.id)
            replaceCron(cron.id) { $0.updatingRunning(true) }
            setStatus("已触发 \(cron.primaryTitle)", tone: .success)
            scheduleBackgroundRefresh()
        } catch {
            presentError(error)
        }
    }

    func stopCron(_ cron: QingLongCron) async {
        pendingCronIDs.insert(cron.id)
        defer { pendingCronIDs.remove(cron.id) }

        do {
            try await QingLongService.shared.stopCron(id: cron.id)
            replaceCron(cron.id) { $0.updatingRunning(false) }
            setStatus("已停止 \(cron.primaryTitle)", tone: .success)
            scheduleBackgroundRefresh()
        } catch {
            presentError(error)
        }
    }

    func setCronEnabled(_ cron: QingLongCron, enabled: Bool) async {
        pendingCronIDs.insert(cron.id)
        defer { pendingCronIDs.remove(cron.id) }

        do {
            try await QingLongService.shared.setCronEnabled(id: cron.id, enabled: enabled)
            replaceCron(cron.id) { $0.updatingEnabled(enabled) }
            setStatus(enabled ? "已启用 \(cron.primaryTitle)" : "已禁用 \(cron.primaryTitle)", tone: .success)
            scheduleBackgroundRefresh()
        } catch {
            presentError(error)
        }
    }

    func runSubscription(_ subscription: QingLongSubscription) async {
        pendingSubscriptionIDs.insert(subscription.id)
        defer { pendingSubscriptionIDs.remove(subscription.id) }

        do {
            try await QingLongService.shared.runSubscription(id: subscription.id)
            replaceSubscription(subscription.id) { $0.updatingRunning(true) }
            setStatus("已触发 \(subscription.titleText) 拉取。", tone: .success)
            scheduleBackgroundRefresh()
        } catch {
            presentError(error)
        }
    }

    func stopSubscription(_ subscription: QingLongSubscription) async {
        pendingSubscriptionIDs.insert(subscription.id)
        defer { pendingSubscriptionIDs.remove(subscription.id) }

        do {
            try await QingLongService.shared.stopSubscription(id: subscription.id)
            replaceSubscription(subscription.id) { $0.updatingRunning(false) }
            setStatus("已停止 \(subscription.titleText) 拉取。", tone: .success)
            scheduleBackgroundRefresh()
        } catch {
            presentError(error)
        }
    }

    func setSubscriptionEnabled(_ subscription: QingLongSubscription, enabled: Bool) async {
        pendingSubscriptionIDs.insert(subscription.id)
        defer { pendingSubscriptionIDs.remove(subscription.id) }

        do {
            try await QingLongService.shared.setSubscriptionEnabled(id: subscription.id, enabled: enabled)
            replaceSubscription(subscription.id) { $0.updatingEnabled(enabled) }
            setStatus(enabled ? "已启用 \(subscription.titleText)" : "已禁用 \(subscription.titleText)", tone: .success)
            scheduleBackgroundRefresh()
        } catch {
            presentError(error)
        }
    }

    func loadCronLog(_ cron: QingLongCron) async {
        loadingCronLogID = cron.id
        selectedCronLog = QingLongCronLog(id: cron.id, title: cron.primaryTitle, content: "日志加载中...")
        defer {
            if loadingCronLogID == cron.id {
                loadingCronLogID = nil
            }
        }

        do {
            let logText = try await QingLongService.shared.fetchCronLog(id: cron.id)
            selectedCronLog = QingLongCronLog(
                id: cron.id,
                title: cron.primaryTitle,
                content: logText.isEmpty ? "当前没有可显示的日志内容。" : logText
            )
        } catch {
            selectedCronLog = QingLongCronLog(id: cron.id, title: cron.primaryTitle, content: error.localizedDescription)
        }
    }

    func loadScriptFile(for cron: QingLongCron) async throws -> QingLongScriptFile {
        guard let scriptLocation = cron.scriptLocation else {
            throw QingLongError.missingScriptReference
        }

        return try await QingLongService.shared.fetchScriptFile(
            path: scriptLocation.path,
            fileName: scriptLocation.fileName
        )
    }

    func loadSubscriptionLog(_ subscription: QingLongSubscription) async {
        loadingSubscriptionLogID = subscription.id
        selectedSubscriptionLog = QingLongSubscriptionLog(id: subscription.id, title: subscription.titleText, content: "日志加载中...")
        defer {
            if loadingSubscriptionLogID == subscription.id {
                loadingSubscriptionLogID = nil
            }
        }

        do {
            let logText = try await QingLongService.shared.fetchSubscriptionLog(id: subscription.id)
            selectedSubscriptionLog = QingLongSubscriptionLog(
                id: subscription.id,
                title: subscription.titleText,
                content: logText.isEmpty ? "当前没有可显示的日志内容。" : logText
            )
        } catch {
            selectedSubscriptionLog = QingLongSubscriptionLog(
                id: subscription.id,
                title: subscription.titleText,
                content: error.localizedDescription
            )
        }
    }

    func makeCronEditor(for cron: QingLongCron) -> QingLongCronEditorContext {
        QingLongCronEditorContext(
            cronID: cron.id,
            title: cron.primaryTitle,
            initialSchedule: cron.schedule
        )
    }

    func saveCronSchedule(for cron: QingLongCron, schedule: String) async -> Bool {
        let trimmedSchedule = schedule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSchedule.isEmpty else {
            setStatus("Cron 表达式不能为空。", tone: .error)
            return false
        }

        pendingCronIDs.insert(cron.id)
        defer { pendingCronIDs.remove(cron.id) }

        do {
            try await QingLongService.shared.updateCron(cron, schedule: trimmedSchedule)
            replaceCron(cron.id) { $0.updatingSchedule(trimmedSchedule) }
            setStatus("已更新 \(cron.primaryTitle) 的 cron。", tone: .success)
            scheduleBackgroundRefresh()
            return true
        } catch {
            presentError(error)
            return false
        }
    }

    func isEnvironmentPending(_ environmentID: Int) -> Bool {
        pendingEnvironmentIDs.contains(environmentID)
    }

    func isCronPending(_ cronID: Int) -> Bool {
        pendingCronIDs.contains(cronID)
    }

    func isLoadingLog(for cronID: Int) -> Bool {
        loadingCronLogID == cronID
    }

    func isSubscriptionPending(_ subscriptionID: Int) -> Bool {
        pendingSubscriptionIDs.contains(subscriptionID)
    }

    func isLoadingSubscriptionLog(for subscriptionID: Int) -> Bool {
        loadingSubscriptionLogID == subscriptionID
    }

    func discardDraftChanges() {
        draftBaseURL = savedBaseURLString
        draftClientID = savedClientID
        draftClientSecret = savedClientSecret
    }

    private func scheduleBackgroundRefresh() {
        deferredRefreshTask?.cancel()
        deferredRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await self?.refresh(showStatus: false, tracksActivity: false)
        }
    }

    private func replaceEnvironment(_ id: Int, transform: (QingLongEnvironment) -> QingLongEnvironment) {
        environments = environments
            .map { $0.id == id ? transform($0) : $0 }
            .sorted(by: QingLongEnvironment.sort(lhs:rhs:))
    }

    private func upsertEnvironment(_ environment: QingLongEnvironment) {
        if environments.contains(where: { $0.id == environment.id }) {
            replaceEnvironment(environment.id) { _ in environment }
            return
        }

        environments = (environments + [environment]).sorted(by: QingLongEnvironment.sort(lhs:rhs:))
    }

    private func replaceCron(_ id: Int, transform: (QingLongCron) -> QingLongCron) {
        crons = crons
            .map { $0.id == id ? transform($0) : $0 }
            .sorted(by: QingLongCron.sort(lhs:rhs:))
    }

    private func replaceSubscription(_ id: Int, transform: (QingLongSubscription) -> QingLongSubscription) {
        subscriptions = subscriptions
            .map { $0.id == id ? transform($0) : $0 }
            .sorted(by: QingLongSubscription.sort(lhs:rhs:))
    }

    private func applyStoredConfiguration(_ configuration: QingLongStoredConfiguration) {
        profile = configuration.profile
        draftBaseURL = configuration.profile?.baseURL.absoluteString ?? ""
        draftClientID = configuration.clientID
        draftClientSecret = configuration.clientSecret
        savedBaseURLString = draftBaseURL
        savedClientID = draftClientID
        savedClientSecret = draftClientSecret
    }

    private func applySnapshot(_ snapshot: QingLongDashboardSnapshot) {
        profile = snapshot.profile
        draftBaseURL = snapshot.profile.baseURL.absoluteString
        environments = snapshot.environments
        crons = snapshot.crons
        subscriptions = snapshot.subscriptions
        lastRefreshedAt = snapshot.fetchedAt
    }

    private func rememberCurrentDraftsAsSaved() {
        savedBaseURLString = draftBaseURL
        savedClientID = draftClientID
        savedClientSecret = draftClientSecret
    }

    private func setStatus(_ message: String, tone: QingLongStatusTone) {
        statusState = QingLongStatusState(message: message, tone: tone)
    }

    private func presentError(_ error: Error) {
        setStatus(error.localizedDescription, tone: .error)
    }

    private func normalizedQuery(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isSharedEnvironment(_ environment: QingLongEnvironment) -> Bool {
        let scriptKeys = Set(crons.compactMap(\.scriptEnvironmentKey))

        for scriptKey in scriptKeys {
            if environment.matches(scriptKey: scriptKey) || environment.hasScriptPrefix(scriptKey) {
                return false
            }
        }

        return true
    }

    private func isValidEnvironmentName(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }

        if let firstScalar = name.unicodeScalars.first,
           CharacterSet.decimalDigits.contains(firstScalar) {
            return false
        }

        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        return name.unicodeScalars.allSatisfy(allowedCharacters.contains)
    }
}
