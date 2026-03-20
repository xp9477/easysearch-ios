import SwiftUI
import UIKit

private enum QingLongWorkspaceSection: String, CaseIterable, Identifiable {
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

private enum QingLongEnvironmentFilter: String, CaseIterable, Identifiable {
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

private enum QingLongCronFilter: String, CaseIterable, Identifiable {
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

private struct QingLongMetric: Identifiable {
    let id: String
    let title: String
    let value: String
}

public struct QingLongView: View {
    @StateObject private var viewModel = QingLongViewModel()
    @Environment(\.openURL) private var openURL
    @State private var selectedSection: QingLongWorkspaceSection = .environments
    @State private var environmentSearchText = ""
    @State private var cronSearchText = ""
    @State private var environmentFilter: QingLongEnvironmentFilter = .all
    @State private var cronFilter: QingLongCronFilter = .all
    @State private var isEditingConnection = false

    public init() {}

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                overviewCard
                connectionStatusCard

                if viewModel.profile == nil || isEditingConnection {
                    connectionEditorCard
                }

                workspaceCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("青龙管理")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.prepare()
            isEditingConnection = viewModel.profile == nil
        }
        .refreshable {
            guard viewModel.profile != nil else { return }
            await viewModel.refresh()
        }
        .onChange(of: viewModel.profile == nil) { isDisconnected in
            if isDisconnected {
                isEditingConnection = true
            }
        }
        .onChange(of: viewModel.isConnecting) { isConnecting in
            if !isConnecting, viewModel.profile != nil {
                isEditingConnection = false
            }
        }
        .sheet(item: $viewModel.selectedCronLog) { log in
            cronLogSheet(log)
        }
        .sheet(item: $viewModel.diagnosticReport) { report in
            diagnosticSheet(report)
        }
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("QingLong")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(viewModel.profile?.displayName ?? "连接你的面板")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.primary)

                Text(viewModel.profile == nil
                     ? "先完成 Open API 接入，后面就按“环境变量 / 定时任务”两个工作区管理，不再把接入表单和运维列表堆在一起。"
                     : "已切到管理视角。连接信息收敛成摘要卡，日常操作集中在下面的工作区里。")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 12)], spacing: 12) {
                ForEach(overviewMetrics) { metric in
                    metricCard(metric)
                }
            }

            if let statusState = viewModel.statusState {
                statusBanner(statusState)
            }

            HStack(spacing: 12) {
                if viewModel.profile == nil {
                    Button {
                        isEditingConnection = true
                    } label: {
                        Label("开始连接", systemImage: "link.badge.plus")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                } else {
                    Button {
                        Task {
                            await viewModel.refresh()
                        }
                    } label: {
                        HStack {
                            Label("立即刷新", systemImage: "arrow.clockwise")
                            Spacer()
                            if viewModel.isRefreshing {
                                ProgressView()
                            }
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(viewModel.isRefreshing || viewModel.isConnecting)

                    if let panelURL = viewModel.profile?.baseURL {
                        Button {
                            openURL(panelURL)
                        } label: {
                            Label("打开面板", systemImage: "arrow.up.right.square")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.bordered)
                        .tint(.green)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(.secondarySystemGroupedBackground),
                            Color.green.opacity(0.14)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var connectionStatusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let profile = viewModel.profile {
                sectionHeader(
                    eyebrow: "Connection",
                    title: "当前连接",
                    description: "连接配置已经折叠成摘要，日常只保留高频动作；需要改地址或密钥时再展开编辑。"
                )

                VStack(spacing: 12) {
                    connectionInfoRow(icon: "server.rack", title: "面板地址", value: profile.baseURL.absoluteString)
                    connectionInfoRow(icon: "network", title: "主机标识", value: profile.hostLabel)
                    connectionInfoRow(icon: "clock", title: "最近连接", value: profile.lastConnectedAt.map(absoluteDateText) ?? "暂无记录")
                    connectionInfoRow(icon: "tray.and.arrow.down", title: "本地保存", value: absoluteDateText(profile.savedAt))
                }

                HStack(spacing: 12) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isEditingConnection = true
                        }
                    } label: {
                        Label("编辑连接", systemImage: "slider.horizontal.3")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)

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
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                    .disabled(viewModel.isRunningDiagnostics || viewModel.isConnecting)
                }

                Button(role: .destructive) {
                    Task {
                        await viewModel.disconnect()
                    }
                } label: {
                    Label("断开连接", systemImage: "trash")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
            } else {
                sectionHeader(
                    eyebrow: "Onboarding",
                    title: "接入步骤",
                    description: "第一次配置只关注三件事：地址正确、凭据正确、面板权限完整。接入成功后，下面的工作区会自动切到管理模式。"
                )

                VStack(spacing: 12) {
                    onboardingStep(number: "01", title: "面板地址", description: "支持域名、IP 和端口，建议公网场景使用 HTTPS。")
                    onboardingStep(number: "02", title: "Open API 凭据", description: "在“系统设置 -> 应用设置”里创建应用，拿到 client_id 和 client_secret。")
                    onboardingStep(number: "03", title: "最小验证", description: "先跑一次连接诊断，确认 token、envs、crons 接口都能通。")
                }
            }
        }
        .padding(24)
        .cardStyle()
    }

    private var connectionEditorCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                eyebrow: "Configuration",
                title: viewModel.profile == nil ? "连接配置" : "编辑连接",
                description: "表单只在接入时或主动编辑时展开。保存成功后会自动折叠，避免长期占据页面主区域。"
            )

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("面板地址")
                editorTextField("例如 https://ql.example.com:5700", text: $viewModel.draftBaseURL, keyboardType: .URL)
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("client_id")
                editorTextField("Open API client_id", text: $viewModel.draftClientID, keyboardType: .asciiCapable)
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("client_secret")
                SecureField("Open API client_secret", text: $viewModel.draftClientSecret)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.asciiCapable)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.tertiarySystemFill))
                    )
            }

            HStack(spacing: 12) {
                Button {
                    Task {
                        await viewModel.connect()
                    }
                } label: {
                    HStack {
                        Label(viewModel.profile == nil ? "保存并连接" : "更新并重连", systemImage: "link.badge.plus")
                        Spacer()
                        if viewModel.isConnecting {
                            ProgressView()
                        }
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(viewModel.isConnecting || viewModel.isRunningDiagnostics)

                if viewModel.profile != nil {
                    Button {
                        viewModel.discardDraftChanges()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isEditingConnection = false
                        }
                    } label: {
                        Label("取消编辑", systemImage: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                    .disabled(viewModel.isConnecting)
                }
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
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
            .disabled(viewModel.isConnecting || viewModel.isRunningDiagnostics)
        }
        .padding(24)
        .cardStyle()
    }

    private var workspaceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                eyebrow: "Workspace",
                title: "管理工作区",
                description: viewModel.profile == nil
                    ? "连接成功后，这里会切换成环境变量和定时任务两个管理工作区。"
                    : "把高频运维动作收敛成两个工作区，再用搜索和筛选快速定位目标。"
            )

            if viewModel.profile == nil {
                emptyState(
                    icon: "rectangle.split.2x1",
                    title: "还没有进入管理态",
                    description: "先完成连接，再使用环境变量和定时任务工作区。"
                )
            } else {
                Picker("管理工作区", selection: $selectedSection) {
                    ForEach(QingLongWorkspaceSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)

                if selectedSection == .environments {
                    environmentWorkspace
                } else {
                    cronWorkspace
                }
            }
        }
        .padding(24)
        .cardStyle()
    }

    private var environmentWorkspace: some View {
        VStack(alignment: .leading, spacing: 16) {
            searchField(text: $environmentSearchText, placeholder: "搜索变量名或备注")

            filterBar(
                selection: $environmentFilter,
                options: QingLongEnvironmentFilter.allCases,
                title: \.title
            )

            Text("显示 \(filteredEnvironments.count) / \(viewModel.environments.count) 个变量，默认优先展示 Pinned 和启用项。")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            if viewModel.environments.isEmpty {
                emptyState(
                    icon: "shippingbox",
                    title: "暂无环境变量",
                    description: "当前面板没有返回变量，或者应用权限里没有 envs 访问能力。"
                )
            } else if filteredEnvironments.isEmpty {
                emptyState(
                    icon: "magnifyingglass",
                    title: "没有匹配的变量",
                    description: "调整关键词或筛选条件后再试。"
                )
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(filteredEnvironments) { environment in
                        QingLongEnvironmentRow(
                            environment: environment,
                            isPending: viewModel.isEnvironmentPending(environment.id),
                            toggleEnabledAction: {
                                Task {
                                    await viewModel.setEnvironmentEnabled(environment, enabled: !environment.isEnabled)
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    private var cronWorkspace: some View {
        VStack(alignment: .leading, spacing: 16) {
            searchField(text: $cronSearchText, placeholder: "搜索任务名、命令或标签")

            filterBar(
                selection: $cronFilter,
                options: QingLongCronFilter.allCases,
                title: \.title
            )

            Text("显示 \(filteredCrons.count) / \(viewModel.crons.count) 个任务，优先把运行中任务和最近执行过的任务排在前面。")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            if viewModel.crons.isEmpty {
                emptyState(
                    icon: "clock.arrow.circlepath",
                    title: "暂无定时任务",
                    description: "当前面板没有返回 cron 数据，或者应用权限里没有 crons 访问能力。"
                )
            } else if filteredCrons.isEmpty {
                emptyState(
                    icon: "magnifyingglass",
                    title: "没有匹配的任务",
                    description: "调整关键词或筛选条件后再试。"
                )
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(filteredCrons) { cron in
                        QingLongCronRow(
                            cron: cron,
                            relativeDateText: relativeDateText(_:),
                            isPending: viewModel.isCronPending(cron.id),
                            isLogLoading: viewModel.isLoadingLog(for: cron.id),
                            primaryAction: {
                                Task {
                                    if cron.isRunning {
                                        await viewModel.stopCron(cron)
                                    } else {
                                        await viewModel.runCron(cron)
                                    }
                                }
                            },
                            toggleEnabledAction: {
                                Task {
                                    await viewModel.setCronEnabled(cron, enabled: !cron.isEnabled)
                                }
                            },
                            logAction: {
                                Task {
                                    await viewModel.loadCronLog(cron)
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    private var overviewMetrics: [QingLongMetric] {
        let runningCronCount = viewModel.crons.filter(\.isRunning).count
        let disabledEnvironmentCount = viewModel.environments.filter { !$0.isEnabled }.count

        return [
            QingLongMetric(
                id: "status",
                title: "连接状态",
                value: viewModel.profile == nil ? "未连接" : "已连接"
            ),
            QingLongMetric(
                id: "envs",
                title: "环境变量",
                value: "\(viewModel.environments.count) 个"
            ),
            QingLongMetric(
                id: "crons",
                title: "定时任务",
                value: "\(viewModel.crons.count) 个"
            ),
            QingLongMetric(
                id: "running",
                title: "运行中",
                value: "\(runningCronCount) 个"
            ),
            QingLongMetric(
                id: "disabled-envs",
                title: "禁用变量",
                value: "\(disabledEnvironmentCount) 个"
            ),
            QingLongMetric(
                id: "updated",
                title: "最近刷新",
                value: viewModel.lastRefreshedAt.map(relativeDateText) ?? "尚未刷新"
            )
        ]
    }

    private var filteredEnvironments: [QingLongEnvironment] {
        let query = normalizedSearchText(environmentSearchText)

        return viewModel.environments.filter { environment in
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

    private var filteredCrons: [QingLongCron] {
        let query = normalizedSearchText(cronSearchText)

        return viewModel.crons.filter { cron in
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

    private func metricCard(_ metric: QingLongMetric) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(metric.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(metric.value)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.5))
        )
    }

    private func sectionHeader(eyebrow: String, title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.primary)

            Text(description)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func statusBanner(_ statusState: QingLongStatusState) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusIconName(for: statusState.tone))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(statusColor(for: statusState.tone))

            Text(statusState.message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(statusColor(for: statusState.tone).opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(statusColor(for: statusState.tone).opacity(0.16), lineWidth: 1)
        )
    }

    private func connectionInfoRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.green)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.tertiarySystemFill))
        )
    }

    private func onboardingStep(number: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.green)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.green.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)

                Text(description)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.tertiarySystemFill))
        )
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary)
    }

    private func editorTextField(_ placeholder: String, text: Binding<String>, keyboardType: UIKeyboardType) -> some View {
        TextField(placeholder, text: text)
            .textInputAutocapitalization(.never)
            .keyboardType(keyboardType)
            .autocorrectionDisabled()
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
            )
    }

    private func searchField(text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !text.wrappedValue.isEmpty {
                Button {
                    text.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.tertiarySystemFill))
        )
    }

    private func filterBar<Option: Identifiable & Hashable>(
        selection: Binding<Option>,
        options: [Option],
        title: KeyPath<Option, String>
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(options) { option in
                    Button {
                        selection.wrappedValue = option
                    } label: {
                        Text(option[keyPath: title])
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(selection.wrappedValue == option ? Color.green : Color.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(selection.wrappedValue == option ? Color.green.opacity(0.12) : Color(.tertiarySystemFill))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func emptyState(icon: String, title: String, description: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)

            Text(description)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.tertiarySystemFill))
        )
    }

    private func cronLogSheet(_ log: QingLongCronLog) -> some View {
        NavigationStack {
            ScrollView {
                Text(log.content)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(log.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func diagnosticSheet(_ report: QingLongDiagnosticReport) -> some View {
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

    private func normalizedSearchText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func relativeDateText(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
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

    private func statusIconName(for tone: QingLongStatusTone) -> String {
        switch tone {
        case .success:
            return "checkmark.circle.fill"
        case .info:
            return "info.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    private func statusColor(for tone: QingLongStatusTone) -> Color {
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

private struct QingLongEnvironmentRow: View {
    let environment: QingLongEnvironment
    let isPending: Bool
    let toggleEnabledAction: () -> Void

    @State private var revealsValue = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(environment.titleText)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.primary)

                    if !environment.remarks.isEmpty {
                        Text(environment.remarks)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 12)

                if isPending {
                    ProgressView()
                        .scaleEffect(0.9)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("变量值")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            revealsValue.toggle()
                        }
                    } label: {
                        Label(revealsValue ? "隐藏" : "查看", systemImage: revealsValue ? "eye.slash" : "eye")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.green)
                }

                Text(revealsValue ? visibleValue : environment.maskedValue)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    QingLongTag(text: environment.isEnabled ? "已启用" : "已禁用", color: environment.isEnabled ? .green : .orange)

                    if environment.isPinned {
                        QingLongTag(text: "Pinned", color: .blue)
                    }

                    if let position = environment.position {
                        QingLongTag(text: "位置 \(position)", color: .teal)
                    }
                }
            }

            Button(action: toggleEnabledAction) {
                Label(environment.isEnabled ? "禁用变量" : "启用变量", systemImage: environment.isEnabled ? "pause.circle" : "checkmark.circle")
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(environment.isEnabled ? .orange : .green)
            .disabled(isPending)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.tertiarySystemFill))
        )
    }

    private var visibleValue: String {
        environment.value.isEmpty ? "空值" : environment.value
    }
}

private struct QingLongCronRow: View {
    let cron: QingLongCron
    let relativeDateText: (Date) -> String
    let isPending: Bool
    let isLogLoading: Bool
    let primaryAction: () -> Void
    let toggleEnabledAction: () -> Void
    let logAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(cron.primaryTitle)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.primary)

                    if !cron.secondaryTitle.isEmpty {
                        Text(cron.secondaryTitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 12)

                if isPending {
                    ProgressView()
                        .scaleEffect(0.9)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    QingLongTag(text: cron.statusText, color: statusColor)

                    if !cron.schedule.isEmpty {
                        QingLongTag(text: cron.schedule, color: .blue)
                    }

                    ForEach(cron.extraSchedules, id: \.schedule) { item in
                        QingLongTag(text: item.schedule, color: .blue)
                    }

                    ForEach(cron.labels, id: \.self) { label in
                        QingLongTag(text: label, color: .purple)
                    }

                    if cron.isPinned {
                        QingLongTag(text: "Pinned", color: .teal)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("执行命令")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(cron.command.isEmpty ? "未返回命令内容" : cron.command)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )

            HStack(spacing: 10) {
                if let lastRunningAt = cron.lastRunningAt {
                    Label("上次运行 \(relativeDateText(lastRunningAt))", systemImage: "clock")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                if cron.hasLog {
                    Label("可查看日志", systemImage: "doc.text")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Button(action: primaryAction) {
                    Label(cron.isRunning ? "停止" : "运行", systemImage: cron.isRunning ? "stop.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(cron.isRunning ? .orange : .green)
                .disabled(isPending)

                Button(action: logAction) {
                    HStack {
                        Label("日志", systemImage: "doc.text")
                        if isLogLoading {
                            ProgressView()
                                .scaleEffect(0.85)
                        }
                    }
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(.green)
                .disabled(isPending || !cron.hasLog || isLogLoading)

                Menu {
                    Button(action: toggleEnabledAction) {
                        Label(cron.isEnabled ? "禁用任务" : "启用任务", systemImage: cron.isEnabled ? "pause.circle" : "checkmark.circle")
                    }
                } label: {
                    Label("更多", systemImage: "ellipsis.circle")
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
                .disabled(isPending)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.tertiarySystemFill))
        )
    }

    private var statusColor: Color {
        if !cron.isEnabled {
            return .orange
        }

        if cron.isRunning {
            return .green
        }

        if cron.isQueued {
            return .blue
        }

        return .gray
    }
}

private struct QingLongTag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.12))
            )
    }
}

private extension View {
    func cardStyle() -> some View {
        background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

#Preview {
    NavigationStack {
        QingLongView()
    }
}
