import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var navigationState: AppNavigationState
    @EnvironmentObject private var statusCenter: FeatureStatusCenter
    @StateObject private var cloudViewModel = HiddenCloudSyncViewModel.shared
    @StateObject private var utNotificationManager = UTNotificationManager.shared
    @StateObject private var expenseAssistantNotificationManager = ExpenseAssistantNotificationManager.shared
    @StateObject private var webDAVSettingsStore = WebDAVSettingsStore.shared
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

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: ESUI.sectionSpacing) {
                    simpleListSection(title: "通用") {
                        NavigationLink(value: SettingsRoute.cloudSync) {
                            ESSettingsRow(title: "云端同步", systemImage: "icloud", iconColor: .blue)
                        }
                        .buttonStyle(.plain)

                        NavigationLink(value: SettingsRoute.imageTranslate) {
                            ESSettingsRow(title: "AI 服务", systemImage: "sparkles", iconColor: .cyan)
                        }
                        .buttonStyle(.plain)
                    }

                    simpleListSection(title: "关于") {
                        ESSettingsRow(
                            title: "版本 \(appVersionText)",
                            systemImage: "info.circle",
                            iconColor: .secondary,
                            showsChevron: false
                        )
                    }
                }
                .padding(.horizontal, ESUI.screenHorizontalPadding)
                .padding(.top, ESUI.Space.lg)
                .padding(.bottom, ESUI.Space.huge)
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

    private func simpleListSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.bottom, 2)

            VStack(spacing: ESUI.Space.sm) {
                content()
            }
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
        case .imageTranslate:
            AISettingsDetailView(entry: .imageTranslate)
        case .emailAssistant:
            AISettingsDetailView(entry: .emailAssistant)
        case .qingLong:
            QingLongSettingsDetailView()
        case .webDAV:
            WebDAVSettingsView(store: webDAVSettingsStore)
        case .hiddenSpace:
            HiddenSpaceSettingsHubView()
        }
    }

    private func handlePendingRouteIfNeeded() {
        guard let route = navigationState.pendingSettingsRoute else { return }
        path.append(route)
        navigationState.pendingSettingsRoute = nil
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

struct UTTrackerSettingsDetailView: View {
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

struct ExpenseAssistantSettingsDetailView: View {
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

struct QingLongSettingsDetailView: View {
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

struct HiddenSpaceSettingsHubView: View {
    var body: some View {
        List {
            NavigationLink {
                Hidden4KHDSettingsDetailView()
            } label: {
                Label("4khd 设置", systemImage: "photo.stack")
            }

            NavigationLink {
                HiddenJavDBSettingsDetailView()
            } label: {
                Label("javdb 设置", systemImage: "film.stack")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("隐藏空间设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct Hidden4KHDSettingsDetailView: View {
    @State private var fourKHDRandomMode = HiddenSpaceSettingsStore.shared.load().fourKHDRandomMode

    var body: some View {
        List {
            Section {
                Picker("默认随机模式", selection: $fourKHDRandomMode) {
                    ForEach(HiddenRandomMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } header: {
                Text("随机")
            } footer: {
                Text("控制进入 4khd 时的默认随机方式。")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("4khd 设置")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            fourKHDRandomMode = HiddenSpaceSettingsStore.shared.load().fourKHDRandomMode
        }
        .onChange(of: fourKHDRandomMode) { mode in
            HiddenSpaceSettingsStore.shared.update { settings in
                settings.fourKHDRandomMode = mode
            }
        }
    }
}

struct HiddenJavDBSettingsDetailView: View {
    @State private var javDBRandomMode = HiddenSpaceSettingsStore.shared.load().javDBRandomMode
    @State private var showJavDBDetailsByDefault = HiddenSpaceSettingsStore.shared.load().showJavDBDetailsByDefault
    @State private var missAVDomain = HiddenSpaceSettingsStore.shared.load().missAVDomain

    var body: some View {
        List {
            Section {
                Picker("默认随机模式", selection: $javDBRandomMode) {
                    ForEach(HiddenJavDBRandomMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                Toggle("默认展开详细信息", isOn: $showJavDBDetailsByDefault)
            } header: {
                Text("随机与详情")
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
        .navigationTitle("javdb 设置")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let settings = HiddenSpaceSettingsStore.shared.load()
            javDBRandomMode = settings.javDBRandomMode
            showJavDBDetailsByDefault = settings.showJavDBDetailsByDefault
            missAVDomain = settings.missAVDomain
        }
        .onChange(of: javDBRandomMode) { mode in
            HiddenSpaceSettingsStore.shared.update { settings in
                settings.javDBRandomMode = mode
            }
        }
        .onChange(of: showJavDBDetailsByDefault) { enabled in
            HiddenSpaceSettingsStore.shared.update { settings in
                settings.showJavDBDetailsByDefault = enabled
            }
        }
        .onChange(of: missAVDomain) { domain in
            HiddenSpaceSettingsStore.shared.update { settings in
                settings.missAVDomain = domain
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppNavigationState())
}
