import Foundation

enum QingLongWorkspaceSection: String, CaseIterable, Identifiable {
    case environments
    case crons

    var id: Self { self }

    var title: String {
        switch self {
        case .environments:
            return "环境变量"
        case .crons:
            return "定时任务"
        }
    }
}

enum QingLongEnvironmentFilter: String, CaseIterable, Identifiable {
    case all
    case enabled
    case disabled
    case pinned

    var id: Self { self }

    var title: String {
        switch self {
        case .all:
            return "全部"
        case .enabled:
            return "已启用"
        case .disabled:
            return "已禁用"
        case .pinned:
            return "Pinned"
        }
    }
}

enum QingLongCronFilter: String, CaseIterable, Identifiable {
    case all
    case running
    case disabled
    case hasLog

    var id: Self { self }

    var title: String {
        switch self {
        case .all:
            return "全部"
        case .running:
            return "运行中"
        case .disabled:
            return "已禁用"
        case .hasLog:
            return "有日志"
        }
    }
}

struct QingLongCronLog: Identifiable, Hashable {
    let id = UUID()
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
    @Published var selectedSection: QingLongWorkspaceSection = .environments
    @Published var environmentSearchText = ""
    @Published var cronSearchText = ""
    @Published var environmentFilter: QingLongEnvironmentFilter = .all
    @Published var cronFilter: QingLongCronFilter = .all
    @Published private(set) var profile: QingLongPanelProfile?
    @Published private(set) var environments: [QingLongEnvironment] = []
    @Published private(set) var crons: [QingLongCron] = []
    @Published private(set) var lastRefreshedAt: Date?
    @Published private(set) var isPreparing = false
    @Published private(set) var isConnecting = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var isRunningDiagnostics = false
    @Published private(set) var pendingEnvironmentIDs: Set<Int> = []
    @Published private(set) var pendingCronIDs: Set<Int> = []
    @Published private(set) var loadingCronLogID: Int?
    @Published private(set) var statusState: QingLongStatusState?
    @Published var selectedCronLog: QingLongCronLog?
    @Published var diagnosticReport: QingLongDiagnosticReport?

    var isBusy: Bool {
        isPreparing ||
            isConnecting ||
            isRefreshing ||
            isRunningDiagnostics ||
            loadingCronLogID != nil ||
            !pendingEnvironmentIDs.isEmpty ||
            !pendingCronIDs.isEmpty
    }

    var filteredEnvironments: [QingLongEnvironment] {
        let query = normalizedQuery(environmentSearchText)

        return environments.filter { environment in
            let matchesFilter: Bool
            switch environmentFilter {
            case .all:
                matchesFilter = true
            case .enabled:
                matchesFilter = environment.isEnabled
            case .disabled:
                matchesFilter = !environment.isEnabled
            case .pinned:
                matchesFilter = environment.isPinned
            }

            guard matchesFilter else { return false }
            guard !query.isEmpty else { return true }

            return [
                environment.titleText,
                environment.remarks
            ]
            .joined(separator: " ")
            .localizedCaseInsensitiveContains(query)
        }
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
            case .hasLog:
                matchesFilter = cron.hasLog
            }

            guard matchesFilter else { return false }
            guard !query.isEmpty else { return true }

            return [
                cron.primaryTitle,
                cron.secondaryTitle,
                cron.command,
                cron.schedule,
                cron.labels.joined(separator: " ")
            ]
            .joined(separator: " ")
            .localizedCaseInsensitiveContains(query)
        }
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
            setStatus(
                "已连接 \(snapshot.profile.displayName)，已同步 \(snapshot.environments.count) 个变量和 \(snapshot.crons.count) 个任务。",
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
        await QingLongService.shared.disconnect()
        profile = nil
        environments = []
        crons = []
        lastRefreshedAt = nil
        draftBaseURL = ""
        draftClientID = ""
        draftClientSecret = ""
        savedBaseURLString = ""
        savedClientID = ""
        savedClientSecret = ""
        pendingEnvironmentIDs = []
        pendingCronIDs = []
        loadingCronLogID = nil
        selectedCronLog = nil
        diagnosticReport = nil
        environmentSearchText = ""
        cronSearchText = ""
        environmentFilter = .all
        cronFilter = .all
        selectedSection = .environments
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

    func loadCronLog(_ cron: QingLongCron) async {
        loadingCronLogID = cron.id
        selectedCronLog = QingLongCronLog(title: cron.primaryTitle, content: "日志加载中...")
        defer {
            if loadingCronLogID == cron.id {
                loadingCronLogID = nil
            }
        }

        do {
            let logText = try await QingLongService.shared.fetchCronLog(id: cron.id)
            selectedCronLog = QingLongCronLog(
                title: cron.primaryTitle,
                content: logText.isEmpty ? "当前没有可显示的日志内容。" : logText
            )
        } catch {
            selectedCronLog = QingLongCronLog(title: cron.primaryTitle, content: error.localizedDescription)
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

    private func replaceCron(_ id: Int, transform: (QingLongCron) -> QingLongCron) {
        crons = crons
            .map { $0.id == id ? transform($0) : $0 }
            .sorted(by: QingLongCron.sort(lhs:rhs:))
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
}
