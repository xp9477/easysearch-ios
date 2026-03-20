import SwiftUI

public struct QingLongView: View {
    @StateObject private var viewModel = QingLongViewModel()
    @Environment(\.openURL) private var openURL
    @State private var isEditingConnection = false

    public init() {}

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                QingLongOverviewCard(
                    viewModel: viewModel,
                    metrics: overviewMetrics,
                    startConnectionAction: {
                        isEditingConnection = true
                    },
                    refreshAction: {
                        Task {
                            await viewModel.refresh()
                        }
                    },
                    openPanelAction: openPanelAction
                )

                QingLongConnectionStatusCard(
                    viewModel: viewModel,
                    isEditingConnection: $isEditingConnection,
                    absoluteDateText: absoluteDateText(_:),
                    runDiagnosticsAction: {
                        Task {
                            await viewModel.runDiagnostics()
                        }
                    },
                    disconnectAction: {
                        Task {
                            await viewModel.disconnect()
                        }
                    }
                )

                if viewModel.profile == nil || isEditingConnection {
                    QingLongConnectionEditorCard(
                        viewModel: viewModel,
                        isEditingConnection: $isEditingConnection,
                        connectAction: {
                            Task {
                                await viewModel.connect()
                            }
                        },
                        runDiagnosticsAction: {
                            Task {
                                await viewModel.runDiagnostics()
                            }
                        }
                    )
                }

                QingLongWorkspaceCard(
                    viewModel: viewModel,
                    relativeDateText: relativeDateText(_:),
                    toggleEnvironmentAction: { environment in
                        Task {
                            await viewModel.setEnvironmentEnabled(environment, enabled: !environment.isEnabled)
                        }
                    },
                    primaryCronAction: { cron in
                        Task {
                            if cron.isRunning {
                                await viewModel.stopCron(cron)
                            } else {
                                await viewModel.runCron(cron)
                            }
                        }
                    },
                    toggleCronEnabledAction: { cron in
                        Task {
                            await viewModel.setCronEnabled(cron, enabled: !cron.isEnabled)
                        }
                    },
                    logAction: { cron in
                        Task {
                            await viewModel.loadCronLog(cron)
                        }
                    }
                )
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
        .sheet(item: $viewModel.diagnosticReport) { report in
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
    }

    private var overviewMetrics: [QingLongMetric] {
        let runningCronCount = viewModel.crons.filter(\.isRunning).count
        let disabledEnvironmentCount = viewModel.environments.filter { !$0.isEnabled }.count

        return [
            QingLongMetric(id: "status", title: "连接状态", value: viewModel.profile == nil ? "未连接" : "已连接"),
            QingLongMetric(id: "envs", title: "环境变量", value: "\(viewModel.environments.count) 个"),
            QingLongMetric(id: "crons", title: "定时任务", value: "\(viewModel.crons.count) 个"),
            QingLongMetric(id: "running", title: "运行中", value: "\(runningCronCount) 个"),
            QingLongMetric(id: "disabled-envs", title: "禁用变量", value: "\(disabledEnvironmentCount) 个"),
            QingLongMetric(
                id: "updated",
                title: "最近刷新",
                value: viewModel.lastRefreshedAt.map(relativeDateText) ?? "尚未刷新"
            )
        ]
    }

    private var openPanelAction: (() -> Void)? {
        guard let panelURL = viewModel.profile?.baseURL else { return nil }
        return {
            openURL(panelURL)
        }
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
}

#Preview {
    NavigationStack {
        QingLongView()
    }
}
