import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var navigationState: AppNavigationState
    @EnvironmentObject private var registry: FeatureRegistry
    @EnvironmentObject private var statusCenter: FeatureStatusCenter
    @StateObject private var cloudViewModel = HiddenCloudSyncViewModel.shared
    @StateObject private var utNotificationManager = UTNotificationManager.shared
    @StateObject private var expenseAssistantNotificationManager = ExpenseAssistantNotificationManager.shared
    @StateObject private var gitHubNotificationManager = GitHubUpdatesNotificationManager.shared
    @State private var path = NavigationPath()

    private var appVersionText: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (shortVersion, buildVersion) {
        case let (shortVersion?, buildVersion?) where !shortVersion.isEmpty && !buildVersion.isEmpty:
            return "\(shortVersion) (\(buildVersion))"
        case let (shortVersion?, _) where !shortVersion.isEmpty:
            return shortVersion
        case let (_, buildVersion?) where !buildVersion.isEmpty:
            return buildVersion
        default:
            return "未知"
        }
    }

    private var orderedModuleSettingsItems: [ModuleSettingsItem] {
        registry.moduleListFeatures.compactMap(moduleSettingsItem(for:))
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: ESUI.sectionSpacing) {
                    accountSyncSection
                    permissionsSection
                    servicesSection
                    if !orderedModuleSettingsItems.isEmpty {
                        moduleSettingsSection
                    }
                    aboutSection
                }
                .padding(.horizontal, ESUI.screenHorizontalPadding)
                .padding(.top, ESUI.Space.md)
                .padding(.bottom, ESUI.Space.lg)
            }
            .esBottomTabPadding()
            .esScreenBackground()
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: SettingsRoute.self) { route in
                settingsDestination(for: route)
            }
            .task {
                await cloudViewModel.prepareIfNeeded()
                await utNotificationManager.configure()
                await expenseAssistantNotificationManager.configure()
                await gitHubNotificationManager.configure()
                await statusCenter.refresh()
                handlePendingRouteIfNeeded()
            }
            .onChange(of: navigationState.pendingSettingsRoute) { _ in
                handlePendingRouteIfNeeded()
            }
            .onChange(of: navigationState.selectedTab) { tab in
                if tab == .settings {
                    Task { await statusCenter.refresh() }
                    handlePendingRouteIfNeeded()
                }
            }
        }
    }

    // MARK: - Sections

    private var accountSyncSection: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            ESSectionHeader(title: "账户与同步", subtitle: "云端连接与同步状态")

            NavigationLink(value: SettingsRoute.cloudSync) {
                ESSettingsRow(
                    title: "云端同步",
                    subtitle: statusCenter.cloudSummary.text,
                    systemImage: "icloud",
                    iconColor: .blue,
                    statusText: statusCenter.cloudSummary.text,
                    statusTone: .from(kind: statusCenter.cloudSummary.kind)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            ESSectionHeader(title: "权限与通知", subtitle: "系统授权状态摘要")

            VStack(spacing: ESUI.Space.xs) {
                notificationSummaryRow(
                    title: "UT 记录",
                    status: utNotificationManager.authorizationStatus
                )
                notificationSummaryRow(
                    title: "报销助手",
                    status: expenseAssistantNotificationManager.authorizationStatus
                )
                notificationSummaryRow(
                    title: "GitHub 更新",
                    status: gitHubNotificationManager.authorizationStatus
                )
            }
        }
    }

    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            ESSectionHeader(title: "服务连接", subtitle: "跨模块依赖的服务配置")

            VStack(spacing: ESUI.Space.xs) {
                NavigationLink(value: SettingsRoute.imageTranslate) {
                    ESSettingsRow(
                        title: "AI 服务",
                        subtitle: "DeepSeek / 翻译与邮件共用",
                        systemImage: "sparkles",
                        iconColor: .cyan,
                        statusText: statusCenter.deepSeekSummary.text,
                        statusTone: .from(kind: statusCenter.deepSeekSummary.kind)
                    )
                }
                .buttonStyle(.plain)

                NavigationLink(value: SettingsRoute.qingLong) {
                    ESSettingsRow(
                        title: "青龙面板",
                        subtitle: "自建面板连接",
                        systemImage: "server.rack",
                        iconColor: .green,
                        statusText: statusCenter.qingLongSummary.text,
                        statusTone: .from(kind: statusCenter.qingLongSummary.kind)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var moduleSettingsSection: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            ESSectionHeader(title: "模块配置", trailing: "\(orderedModuleSettingsItems.count)")

            VStack(spacing: ESUI.Space.xs) {
                ForEach(orderedModuleSettingsItems) { item in
                    NavigationLink(value: item.route) {
                        ESSettingsRow(
                            title: item.title,
                            subtitle: item.subtitle,
                            systemImage: item.systemImage,
                            iconColor: item.color,
                            statusText: item.status.text,
                            statusTone: .from(kind: item.status.kind)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            ESSectionHeader(title: "关于")

            VStack(alignment: .leading, spacing: ESUI.Space.xs) {
                Text("EasySearch")
                    .font(.body.weight(.semibold))
                Text("版本 \(appVersionText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("轻量多功能个人工作台")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(ESUI.Space.md)
            .esSurface()
        }
    }

    private func notificationSummaryRow(title: String, status: UNAuthorizationStatus) -> some View {
        let summary = notificationSummary(for: status)
        return ESSettingsRow(
            title: title,
            systemImage: "bell.badge",
            iconColor: .orange,
            statusText: summary.text,
            statusTone: .from(kind: summary.kind),
            showsChevron: false
        )
    }

    private func notificationSummary(for status: UNAuthorizationStatus) -> FeatureStatusSummary {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return FeatureStatusSummary(kind: .ready, text: "已授权")
        case .denied:
            return FeatureStatusSummary(kind: .needsAuthorization, text: "未授权")
        case .notDetermined:
            return FeatureStatusSummary(kind: .needsAuthorization, text: "未请求")
        @unknown default:
            return FeatureStatusSummary(kind: .empty, text: "未知")
        }
    }

    // MARK: - Navigation

    @ViewBuilder
    private func settingsDestination(for route: SettingsRoute) -> some View {
        switch route {
        case .cloudSync:
            CloudSyncSettingsDetailView()
        case .utTracker:
            UTTrackerSettingsDetailView()
        case .expenseAssistant:
            ExpenseAssistantSettingsDetailView()
        case .gitHubUpdates:
            GitHubUpdatesSettingsDetailView()
        case .imageTranslate:
            AISettingsDetailView(entry: .imageTranslate)
        case .emailAssistant:
            AISettingsDetailView(entry: .emailAssistant)
        case .qingLong:
            QingLongSettingsDetailView()
        }
    }

    private func handlePendingRouteIfNeeded() {
        guard let route = navigationState.pendingSettingsRoute else { return }
        path.append(route)
        navigationState.pendingSettingsRoute = nil
    }

    private func moduleSettingsItem(for feature: any AppFeature) -> ModuleSettingsItem? {
        let status = statusCenter.summary(for: feature.id)
        switch feature.id {
        case "uttracker":
            return ModuleSettingsItem(
                id: feature.id,
                title: feature.title,
                subtitle: "通知与提醒",
                systemImage: feature.iconName,
                color: feature.color,
                status: status,
                route: .utTracker
            )
        case "expense-assistant":
            return ModuleSettingsItem(
                id: feature.id,
                title: feature.title,
                subtitle: "通知与提醒",
                systemImage: feature.iconName,
                color: feature.color,
                status: status,
                route: .expenseAssistant
            )
        case "github-updates":
            return ModuleSettingsItem(
                id: feature.id,
                title: feature.title,
                subtitle: "通知与检查",
                systemImage: feature.iconName,
                color: feature.color,
                status: status,
                route: .gitHubUpdates
            )
        case "qinglong-management":
            return ModuleSettingsItem(
                id: feature.id,
                title: feature.title,
                subtitle: "面板连接",
                systemImage: feature.iconName,
                color: feature.color,
                status: status,
                route: .qingLong
            )
        case "image-translate":
            return ModuleSettingsItem(
                id: feature.id,
                title: feature.title,
                subtitle: "AI 与目标语言",
                systemImage: feature.iconName,
                color: feature.color,
                status: status,
                route: .imageTranslate
            )
        case "email-assistant":
            return ModuleSettingsItem(
                id: feature.id,
                title: feature.title,
                subtitle: "AI 配置",
                systemImage: feature.iconName,
                color: feature.color,
                status: status,
                route: .emailAssistant
            )
        default:
            return nil
        }
    }
}

private struct ModuleSettingsItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let color: Color
    let status: FeatureStatusSummary
    let route: SettingsRoute
}

private struct CloudSyncSettingsDetailView: View {
    @StateObject private var cloudViewModel = HiddenCloudSyncViewModel.shared
    @State private var cloudEmail = ""
    @State private var cloudPassword = ""

    private var cloudInlineMessage: String? {
        guard let message = cloudViewModel.cloudStatusMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty else {
            return nil
        }

        return message
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Label("状态", systemImage: cloudViewModel.isCloudAuthenticated ? "icloud.fill" : "icloud")
                    Spacer()
                    Text(statusText)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }

                if cloudViewModel.isCloudConfigured {
                    if cloudViewModel.isCloudAuthenticated {
                        HStack {
                            Label("账号", systemImage: "person.crop.circle")
                            Spacer()
                            Text(currentAccountText)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }

                        Button {
                            Task {
                                await cloudViewModel.syncNow()
                            }
                        } label: {
                            HStack {
                                Label("同步", systemImage: "arrow.clockwise")
                                Spacer()
                                if cloudViewModel.isCloudBusy {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(cloudViewModel.isCloudBusy)

                        Button(role: .destructive) {
                            Task {
                                await cloudViewModel.signOut()
                            }
                        } label: {
                            Label("退出云端登录", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                        .disabled(cloudViewModel.isCloudBusy)
                    } else {
                        TextField("邮箱", text: $cloudEmail)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()

                        SecureField("密码", text: $cloudPassword)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Button {
                            Task {
                                await cloudViewModel.signIn(email: cloudEmail, password: cloudPassword)
                                if cloudViewModel.isCloudAuthenticated {
                                    cloudPassword = ""
                                }
                            }
                        } label: {
                            HStack {
                                Label("登录", systemImage: "person.crop.circle.badge.checkmark")
                                Spacer()
                                if cloudViewModel.isCloudBusy {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(
                            cloudViewModel.isCloudBusy ||
                            cloudEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            cloudPassword.isEmpty
                        )

                        Button {
                            Task {
                                await cloudViewModel.signUp(email: cloudEmail, password: cloudPassword)
                                if cloudViewModel.isCloudAuthenticated {
                                    cloudPassword = ""
                                }
                            }
                        } label: {
                            Label("注册", systemImage: "person.crop.circle.badge.plus")
                        }
                        .disabled(
                            cloudViewModel.isCloudBusy ||
                            cloudEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            cloudPassword.isEmpty
                        )
                    }
                }

                if let cloudInlineMessage {
                    Text(cloudInlineMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("云端同步")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await cloudViewModel.prepareIfNeeded()
        }
    }

    private var statusText: String {
        if !cloudViewModel.isCloudConfigured {
            return "仅本地"
        }
        return cloudViewModel.isCloudAuthenticated ? "已登录" : "未登录"
    }

    private var currentAccountText: String {
        let email = cloudViewModel.cloudUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return email.isEmpty ? "已登录" : email
    }
}

private struct UTTrackerSettingsDetailView: View {
    @StateObject private var notificationManager = UTNotificationManager.shared
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                SettingsValueRow(title: "状态", value: notificationManager.statusText)

                switch notificationManager.authorizationStatus {
                case .notDetermined:
                    Button {
                        Task {
                            await notificationManager.requestAuthorization()
                        }
                    } label: {
                        Label("开启通知", systemImage: "bell.badge")
                    }

                case .denied:
                    Button {
                        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
                        openURL(settingsURL)
                    } label: {
                        Label("前往系统设置", systemImage: "gearshape")
                    }

                case .authorized, .provisional, .ephemeral:
                    Button {
                        Task {
                            await notificationManager.refreshStateAndSchedules()
                        }
                    } label: {
                        Label("刷新提醒", systemImage: "arrow.clockwise")
                    }

                @unknown default:
                    EmptyView()
                }
            }
        }
        .navigationTitle("UT 记录")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await notificationManager.configure()
        }
    }
}

private struct ExpenseAssistantSettingsDetailView: View {
    @StateObject private var notificationManager = ExpenseAssistantNotificationManager.shared
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                SettingsValueRow(title: "状态", value: notificationManager.statusText)

                switch notificationManager.authorizationStatus {
                case .notDetermined:
                    Button {
                        Task {
                            await notificationManager.requestAuthorization()
                        }
                    } label: {
                        Label("开启通知", systemImage: "bell.badge")
                    }

                case .denied:
                    Button {
                        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
                        openURL(settingsURL)
                    } label: {
                        Label("前往系统设置", systemImage: "gearshape")
                    }

                case .authorized, .provisional, .ephemeral:
                    Button {
                        Task {
                            await notificationManager.refreshStateAndSchedules()
                        }
                    } label: {
                        Label("刷新提醒", systemImage: "arrow.clockwise")
                    }

                @unknown default:
                    EmptyView()
                }
            }
        }
        .navigationTitle("报销助手")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await notificationManager.configure()
        }
    }
}

private struct GitHubUpdatesSettingsDetailView: View {
    @StateObject private var notificationManager = GitHubUpdatesNotificationManager.shared
    @Environment(\.openURL) private var openURL
    @State private var repositoryCount = 0

    var body: some View {
        List {
            Section {
                SettingsValueRow(title: "状态", value: notificationManager.statusText)
                SettingsValueRow(title: "仓库", value: "\(repositoryCount) 个")

                switch notificationManager.authorizationStatus {
                case .notDetermined:
                    Button {
                        Task {
                            await notificationManager.requestAuthorization()
                        }
                    } label: {
                        Label("开启通知", systemImage: "bell.badge")
                    }

                case .denied:
                    Button {
                        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
                        openURL(settingsURL)
                    } label: {
                        Label("前往系统设置", systemImage: "gearshape")
                    }

                case .authorized, .provisional, .ephemeral:
                    Button {
                        Task {
                            await notificationManager.refreshAuthorizationStatus()
                        }
                    } label: {
                        Label("刷新状态", systemImage: "arrow.clockwise")
                    }

                @unknown default:
                    EmptyView()
                }
            }
        }
        .navigationTitle("GitHub 更新")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await notificationManager.configure()
            reloadRepositoryCount()
        }
        .onReceive(NotificationCenter.default.publisher(for: .gitHubWatchedRepositoriesDidChange)) { _ in
            reloadRepositoryCount()
        }
    }

    private func reloadRepositoryCount() {
        repositoryCount = GitHubWatchedRepositoryLocalStore().loadRepositories().count
    }
}

private enum AISettingsEntry {
    case imageTranslate
    case emailAssistant

    var title: String {
        switch self {
        case .imageTranslate:
            return "翻译"
        case .emailAssistant:
            return "邮件助手"
        }
    }

    var showsTargetLanguage: Bool {
        self == .imageTranslate
    }
}

private struct AISettingsDetailView: View {
    let entry: AISettingsEntry

    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var model = ""
    @State private var targetLanguage: ImageTranslateTargetLanguage = .simplifiedChinese
    @State private var statusMessage: String?

    private var configurationStatusText: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未配置" : "已配置"
    }

    var body: some View {
        List {
            Section {
                SettingsValueRow(title: "状态", value: configurationStatusText)

                TextField("Base URL", text: $baseURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()

                SecureField("AI API Key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField("模型 ID", text: $model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    saveConfiguration()
                } label: {
                    Label("保存", systemImage: "tray.and.arrow.down")
                }

                if let statusMessage,
                   !statusMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("支持 OpenAI 兼容接口。CLIProxyAPI 可填写为你的服务地址，例如 http://127.0.0.1:8080/v1，模型填写你在代理里要转发的模型 ID。")
            }

            if entry.showsTargetLanguage {
                Section {
                    Picker("默认目标语言", selection: $targetLanguage) {
                        ForEach(ImageTranslateTargetLanguage.allCases) { language in
                            Text(language.title).tag(language)
                        }
                    }
                }
            }
        }
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadConfiguration()
        }
    }

    private func loadConfiguration() {
        let configuration = ImageTranslateConfigurationStore.shared.loadConfiguration()
        baseURL = configuration.baseURL
        apiKey = configuration.apiKey
        model = configuration.model
        targetLanguage = configuration.targetLanguage
    }

    private func saveConfiguration() {
        do {
            try ImageTranslateConfigurationStore.shared.saveConfiguration(
                baseURL: baseURL,
                apiKey: apiKey,
                model: model,
                targetLanguage: targetLanguage
            )
            loadConfiguration()
            statusMessage = apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "已清除本地 AI API Key。"
                : "AI 配置已保存，翻译和邮件助手都会同步使用。"
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}

private struct QingLongSettingsDetailView: View {
    @StateObject private var viewModel = QingLongViewModel()
    @State private var isEditingConnection = false

    var body: some View {
        List {
            if let statusState = viewModel.statusState {
                Section {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: iconName(for: statusState.tone))
                            .foregroundStyle(color(for: statusState.tone))
                        Text(statusState.message)
                            .foregroundStyle(.primary)
                    }
                }
            }

            if let profile = viewModel.profile {
                Section("当前连接") {
                    SettingsValueRow(title: "面板地址", value: profile.baseURL.absoluteString)
                    SettingsValueRow(title: "主机标识", value: profile.hostLabel)
                    SettingsValueRow(title: "最近连接", value: profile.lastConnectedAt.map(absoluteDateText) ?? "暂无记录")

                    Button(isEditingConnection ? "收起编辑" : "编辑连接") {
                        isEditingConnection.toggle()
                    }

                    Button {
                        Task {
                            await viewModel.runDiagnostics()
                        }
                    } label: {
                        HStack {
                            Label("连接诊断", systemImage: "stethoscope")
                            Spacer()
                            if viewModel.isRunningDiagnostics {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(viewModel.isRunningDiagnostics || viewModel.isConnecting)

                    Button(role: .destructive) {
                        Task {
                            await viewModel.disconnect()
                            isEditingConnection = true
                        }
                    } label: {
                        Label("断开连接", systemImage: "trash")
                    }
                }
            }

            if viewModel.profile == nil || isEditingConnection {
                Section {
                    TextField("面板地址，例如 https://ql.example.com:5700", text: $viewModel.draftBaseURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()

                    TextField("Open API client_id", text: $viewModel.draftClientID)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.asciiCapable)
                        .autocorrectionDisabled()

                    SecureField("Open API client_secret", text: $viewModel.draftClientSecret)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.asciiCapable)
                        .autocorrectionDisabled()

                    Button {
                        Task {
                            await viewModel.connect()
                            if viewModel.profile != nil {
                                isEditingConnection = false
                            }
                        }
                    } label: {
                        HStack {
                            Label(viewModel.profile == nil ? "保存并连接" : "更新并重连", systemImage: "link.badge.plus")
                            Spacer()
                            if viewModel.isConnecting {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(viewModel.isConnecting || viewModel.isRunningDiagnostics)

                    Button {
                        Task {
                            await viewModel.runDiagnostics()
                        }
                    } label: {
                        HStack {
                            Label("连接诊断", systemImage: "stethoscope")
                            Spacer()
                            if viewModel.isRunningDiagnostics {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(viewModel.isConnecting || viewModel.isRunningDiagnostics)

                    if viewModel.profile != nil {
                        Button("取消编辑") {
                            viewModel.discardDraftChanges()
                            isEditingConnection = false
                        }
                        .disabled(viewModel.isConnecting)
                    }
                } header: {
                    Text(viewModel.profile == nil ? "连接配置" : "编辑连接")
                }
            }
        }
        .navigationTitle("青龙管理")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.prepare()
            isEditingConnection = viewModel.profile == nil
        }
        .sheet(item: $viewModel.diagnosticReport) { report in
            QingLongDiagnosticReportView(report: report)
        }
    }

    private func absoluteDateText(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .year()
                .month()
                .day()
                .hour()
                .minute()
        )
    }

    private func iconName(for tone: QingLongStatusTone) -> String {
        switch tone {
        case .success:
            return "checkmark.circle.fill"
        case .info:
            return "info.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    private func color(for tone: QingLongStatusTone) -> Color {
        switch tone {
        case .success:
            return .green
        case .info:
            return .blue
        case .error:
            return .orange
        }
    }
}

private struct SettingsValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(title)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct QingLongDiagnosticReportView: View {
    let report: QingLongDiagnosticReport

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(report.baseURL)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)

                        Text("生成时间 \(absoluteDateText(report.generatedAt))")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    ForEach(report.steps) { step in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(step.title)
                                    .font(.system(size: 17, weight: .bold))

                                Spacer()

                                QingLongTag(
                                    text: step.isSuccess ? "成功" : "失败",
                                    color: step.isSuccess ? .green : .orange
                                )
                            }

                            Text(step.url)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)

                            Text(step.summary)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)

                            if !step.preview.isEmpty {
                                Text(step.preview)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(Color(.tertiarySystemFill))
                                    )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                    }
                }
                .padding(20)
            }
            .esScreenBackground()
            .navigationTitle("连接诊断")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func absoluteDateText(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .year()
                .month()
                .day()
                .hour()
                .minute()
        )
    }
}

struct HiddenSpaceSettingsDetailView: View {
    @State private var fourKHDRandomMode = HiddenSpaceSettingsStore.shared.load().fourKHDRandomMode
    @State private var javDBRandomMode = HiddenSpaceSettingsStore.shared.load().javDBRandomMode
    @State private var showJavDBDetailsByDefault = HiddenSpaceSettingsStore.shared.load().showJavDBDetailsByDefault
    @State private var missAVDomain = HiddenSpaceSettingsStore.shared.load().missAVDomain

    var body: some View {
        List {
            Section {
                Picker("默认随机模式", selection: $fourKHDRandomMode) {
                    ForEach(HiddenRandomMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } header: {
                Text("4khd")
            } footer: {
                Text("控制隐藏空间首页进入 4khd 时的默认随机方式。")
            }

            Section {
                Picker("默认随机模式", selection: $javDBRandomMode) {
                    ForEach(HiddenJavDBRandomMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                Toggle("默认展开详细信息", isOn: $showJavDBDetailsByDefault)
            } header: {
                Text("javdb")
            } footer: {
                Text("详细信息可在影片卡片与详情页随时切换显示。")
            }

            Section {
                TextField("miss 域名，例如 missav.ws", text: $missAVDomain)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)

                LabeledContent("当前生效") {
                    Text(HiddenMissAVDomainConfiguration.resolvedHost(from: missAVDomain))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !missAVDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("恢复默认域名", role: .destructive) {
                        missAVDomain = ""
                    }
                }
            } header: {
                Text("MissAV")
            } footer: {
                Text("支持直接输入域名或完整 URL；留空时回退默认域名。")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("隐藏空间设置")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadSettings()
        }
        .onChange(of: fourKHDRandomMode) { _ in
            persistSettings()
        }
        .onChange(of: javDBRandomMode) { _ in
            persistSettings()
        }
        .onChange(of: showJavDBDetailsByDefault) { _ in
            persistSettings()
        }
        .onChange(of: missAVDomain) { _ in
            persistSettings()
        }
    }

    private func loadSettings() {
        let settings = HiddenSpaceSettingsStore.shared.load()
        fourKHDRandomMode = settings.fourKHDRandomMode
        javDBRandomMode = settings.javDBRandomMode
        showJavDBDetailsByDefault = settings.showJavDBDetailsByDefault
        missAVDomain = settings.missAVDomain
    }

    private func persistSettings() {
        HiddenSpaceSettingsStore.shared.save(
            HiddenSpaceSettings(
                fourKHDRandomMode: fourKHDRandomMode,
                javDBRandomMode: javDBRandomMode,
                showJavDBDetailsByDefault: showJavDBDetailsByDefault,
                missAVDomain: missAVDomain
            )
        )
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppNavigationState())
}
