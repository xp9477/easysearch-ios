import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var navigationState: AppNavigationState
    @EnvironmentObject private var registry: FeatureRegistry
    @StateObject private var cloudViewModel = HiddenCloudSyncViewModel.shared
    @StateObject private var utNotificationManager = UTNotificationManager.shared
    @StateObject private var expenseAssistantNotificationManager = ExpenseAssistantNotificationManager.shared
    @StateObject private var webDAVSettingsStore = WebDAVSettingsStore.shared
    @State private var path = NavigationPath()
    @State private var deepSeekConfiguration = ImageTranslateConfiguration(
        baseURL: DeepSeekClientConfiguration.defaultBaseURL,
        apiKey: "",
        model: "deepseek-chat",
        targetLanguage: .simplifiedChinese
    )
    @State private var qingLongProfile: QingLongPanelProfile?

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

    private var deepSeekStatusText: String {
        deepSeekConfiguration.hasAPIKey ? "已配置" : "未配置"
    }

    private var qingLongStatusText: String {
        qingLongProfile == nil ? "未连接" : "已连接"
    }

    private var cloudSyncStatusText: String {
        if !cloudViewModel.isCloudConfigured {
            return "仅本地"
        }
        if cloudViewModel.isCloudAuthenticated {
            let email = cloudViewModel.cloudUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return email.isEmpty ? "云端已登录" : email
        }
        return "云端未登录"
    }

    private var orderedModuleSettingsItems: [ModuleSettingsItem] {
        registry.moduleListFeatures.compactMap(moduleSettingsItem(for:))
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    cloudSyncSection

                    if !orderedModuleSettingsItems.isEmpty {
                        moduleSettingsSection
                    }

                    aboutSection
                }
                .padding(.horizontal, ESUI.screenHorizontalPadding)
                .padding(.top, 14)
            }
            .esBottomTabPadding()
            .esScreenBackground()
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SettingsRoute.self) { route in
                settingsDestination(for: route)
            }
            .task {
                await cloudViewModel.prepareIfNeeded()
                await utNotificationManager.configure()
                await expenseAssistantNotificationManager.configure()
                refreshSummaryState()
                handlePendingRouteIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: .imageTranslateConfigurationDidChange)) { _ in
                refreshSummaryState()
            }
            .onReceive(NotificationCenter.default.publisher(for: .qingLongPanelDidChange)) { _ in
                refreshSummaryState()
            }
            .onChange(of: navigationState.pendingSettingsRoute) { _ in
                handlePendingRouteIfNeeded()
            }
        }
    }

    private var cloudSyncSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ESSectionHeader(title: "同步状态")

            NavigationLink(value: SettingsRoute.cloudSync) {
                ModuleSettingsRow(
                    title: "云端同步",
                    status: cloudSyncStatusText,
                    systemImage: "icloud",
                    tone: cloudViewModel.isCloudAuthenticated ? .success : .neutral
                )
            }
            .buttonStyle(ESCardButtonStyle())
        }
    }

    private var moduleSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ESSectionHeader(title: "模块设置", trailing: "\(orderedModuleSettingsItems.count)")

            VStack(spacing: 10) {
                ForEach(orderedModuleSettingsItems) { item in
                    NavigationLink(value: item.route) {
                        ModuleSettingsRow(
                            title: item.title,
                            status: item.status,
                            systemImage: item.systemImage,
                            tone: item.tone
                        )
                    }
                    .buttonStyle(ESCardButtonStyle())
                }
            }
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ESSectionHeader(title: "关于")

            HStack(spacing: 14) {
                ESFeatureIcon(systemName: "app.badge", color: .accentColor, size: 46)

                VStack(alignment: .leading, spacing: 4) {
                    Text("EasySearch")
                        .font(.subheadline.weight(.semibold))
                    Text("版本 \(appVersionText)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .esCard()
        }
    }

    @ViewBuilder
    private func settingsDestination(for route: SettingsRoute) -> some View {
        switch route {
        case .cloudSync:
            CloudSyncSettingsDetailView()
        case .utTracker:
            UTTrackerSettingsDetailView()
        case .expenseAssistant:
            ExpenseAssistantSettingsDetailView()
        case .imageTranslate:
            AISettingsDetailView(entry: .imageTranslate)
        case .emailAssistant:
            AISettingsDetailView(entry: .emailAssistant)
        case .qingLong:
            QingLongSettingsDetailView()
        case .webDAV:
            WebDAVSettingsView(store: webDAVSettingsStore)
        }
    }

    private func refreshSummaryState() {
        deepSeekConfiguration = ImageTranslateConfigurationStore.shared.loadConfiguration()
        qingLongProfile = QingLongPanelLocalStore().loadProfile()
    }

    private func handlePendingRouteIfNeeded() {
        guard let route = navigationState.pendingSettingsRoute else { return }
        path = NavigationPath()
        path.append(route)
        navigationState.pendingSettingsRoute = nil
    }

    private func moduleSettingsItem(for feature: any AppFeature) -> ModuleSettingsItem? {
        switch feature.id {
        case "uttracker":
            return ModuleSettingsItem(
                id: feature.id,
                title: feature.title,
                status: utNotificationManager.statusText,
                systemImage: feature.iconName,
                route: .utTracker
            )
        case "expense-assistant":
            return ModuleSettingsItem(
                id: feature.id,
                title: feature.title,
                status: expenseAssistantNotificationManager.statusText,
                systemImage: feature.iconName,
                route: .expenseAssistant
            )
        case "qinglong-management":
            return ModuleSettingsItem(
                id: feature.id,
                title: feature.title,
                status: qingLongProfile?.hostLabel ?? qingLongStatusText,
                systemImage: feature.iconName,
                route: .qingLong
            )
        case "image-translate":
            return ModuleSettingsItem(
                id: feature.id,
                title: feature.title,
                status: "\(deepSeekStatusText) · \(deepSeekConfiguration.resolvedModel)",
                systemImage: feature.iconName,
                route: .imageTranslate
            )
        case "email-assistant":
            return ModuleSettingsItem(
                id: feature.id,
                title: feature.title,
                status: deepSeekStatusText,
                systemImage: feature.iconName,
                route: .emailAssistant
            )
        case "webdav":
            let count = webDAVSettingsStore.locations.count
            let currentName = webDAVSettingsStore.selectedLocation?.name ?? ""
            return ModuleSettingsItem(
                id: feature.id,
                title: feature.title,
                status: count == 0 ? "未配置" : "\(count) 个位置 · \(currentName)",
                systemImage: feature.iconName,
                route: .webDAV
            )
        default:
            return nil
        }
    }
}

private struct ModuleSettingsItem: Identifiable {
    let id: String
    let title: String
    let status: String
    let systemImage: String
    let route: SettingsRoute

    var tone: ESStatusPill.Tone {
        if status.contains("已") || status.contains("@") {
            return .success
        }
        if status.contains("未") || status.contains("尚未") {
            return .warning
        }
        return .neutral
    }
}

private struct ModuleSettingsRow: View {
    let title: String
    let status: String
    let systemImage: String
    var tone: ESStatusPill.Tone = .neutral

    var body: some View {
        HStack(spacing: 14) {
            ESFeatureIcon(systemName: systemImage, color: iconColor, size: 46)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            ESStatusPill(text: statusPillText, tone: tone)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .esCard()
    }

    private var statusPillText: String {
        if status.contains("@") {
            return "已登录"
        }
        if status.contains("已") {
            return "已配置"
        }
        if status.contains("未") || status.contains("尚未") {
            return "待配置"
        }
        return "本地"
    }

    private var iconColor: Color {
        switch tone {
        case .neutral:
            return .accentColor
        default:
            return tone.color
        }
    }
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
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
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
            }

            Section(
                header: Text("javdb")
            ) {
                Picker("默认随机模式", selection: $javDBRandomMode) {
                    ForEach(HiddenJavDBRandomMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                Toggle("默认展开详细信息", isOn: $showJavDBDetailsByDefault)
            }

            Section(
                header: Text("MissAV"),
                footer: VStack(alignment: .leading, spacing: 4) {
                    Text("支持直接输入域名或完整 URL；留空时回退默认域名。")
                    Text("当前生效：\(HiddenMissAVDomainConfiguration.resolvedHost(from: missAVDomain))")
                }
            ) {
                TextField("miss 域名，例如 missav.ws", text: $missAVDomain)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)

                if !missAVDomain.isEmpty {
                    Button("恢复默认域名") {
                        missAVDomain = ""
                    }
                }
            }
        }
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
