import SwiftUI

public struct QingLongView: View {
    @EnvironmentObject private var navigationState: AppNavigationState
    @StateObject private var viewModel = QingLongViewModel()
    @Environment(\.openURL) private var openURL
    @State private var selectedScriptEnvironmentEditor: QingLongEnvironmentEditorContext?
    @State private var selectedCronEditor: QingLongCronEditorContext?
    @State private var isShowingSharedEnvironments = false

    public init() {}

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                QingLongOverviewCard(
                    viewModel: viewModel,
                    metrics: overviewMetrics,
                    refreshAction: {
                        Task {
                            await viewModel.refresh()
                        }
                    },
                    openPanelAction: openPanelAction
                )

                QingLongSubscriptionWorkspaceCard(
                    viewModel: viewModel,
                    logAction: { subscription in
                        Task {
                            await viewModel.loadSubscriptionLog(subscription)
                        }
                    },
                    primaryAction: { subscription in
                        Task {
                            if subscription.isRunning || subscription.isQueued {
                                await viewModel.stopSubscription(subscription)
                            } else {
                                await viewModel.runSubscription(subscription)
                            }
                        }
                    },
                    toggleEnabledAction: { subscription in
                        Task {
                            await viewModel.setSubscriptionEnabled(subscription, enabled: !subscription.isEnabled)
                        }
                    }
                )

                QingLongWorkspaceCard(
                    viewModel: viewModel,
                    relativeDateText: relativeDateText(_:),
                    openConfigurationAction: {
                        navigationState.openSettings(.qingLong)
                    },
                    openSharedEnvironmentsAction: {
                        isShowingSharedEnvironments = true
                    },
                    editScriptEnvironmentAction: { cron in
                        selectedScriptEnvironmentEditor = viewModel.makeScriptEnvironmentEditor(for: cron)
                    },
                    editCronAction: { cron in
                        selectedCronEditor = viewModel.makeCronEditor(for: cron)
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
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("青龙管理")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.prepare()
        }
        .refreshable {
            guard viewModel.profile != nil else { return }
            await viewModel.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .qingLongPanelDidChange)) { _ in
            Task {
                await viewModel.prepare()
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
        .sheet(item: $viewModel.selectedSubscriptionLog) { log in
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
        .sheet(item: $selectedScriptEnvironmentEditor) { context in
            QingLongEnvironmentEditorSheet(
                context: context,
                isExistingEnvironmentPending: context.environment.map { viewModel.isEnvironmentPending($0.id) } ?? false,
                saveAction: { name, value, remarks in
                    await viewModel.saveEnvironment(using: context, name: name, value: value, remarks: remarks)
                },
                toggleEnabledAction: context.environment.map { environment in
                    {
                        Task {
                            await viewModel.setEnvironmentEnabled(environment, enabled: !environment.isEnabled)
                        }
                    }
                }
            )
        }
        .sheet(item: $selectedCronEditor) { context in
            if let cron = viewModel.crons.first(where: { $0.id == context.cronID }) {
                QingLongCronEditorSheet(
                    context: context,
                    isPending: viewModel.isCronPending(context.cronID),
                    saveAction: { schedule in
                        await viewModel.saveCronSchedule(for: cron, schedule: schedule)
                    }
                )
            }
        }
        .sheet(isPresented: $isShowingSharedEnvironments) {
            QingLongSharedEnvironmentsSheet(
                viewModel: viewModel,
                saveEnvironmentAction: { context, name, value, remarks in
                    await viewModel.saveEnvironment(using: context, name: name, value: value, remarks: remarks)
                },
                toggleEnvironmentAction: { environment in
                    Task {
                        await viewModel.setEnvironmentEnabled(environment, enabled: !environment.isEnabled)
                    }
                }
            )
        }
    }

    private var overviewMetrics: [QingLongMetric] {
        let runningCronCount = viewModel.crons.filter(\.isRunning).count

        return [
            QingLongMetric(id: "envs", symbol: "shippingbox", title: "变量", value: "\(viewModel.environments.count)"),
            QingLongMetric(id: "crons", symbol: "clock.arrow.circlepath", title: "任务", value: "\(viewModel.crons.count)"),
            QingLongMetric(id: "subs", symbol: "arrow.down.circle", title: "订阅", value: "\(viewModel.subscriptions.count)"),
            QingLongMetric(id: "running", symbol: "play.circle.fill", title: "运行", value: "\(runningCronCount)")
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
}

#Preview {
    NavigationStack {
        QingLongView()
            .environmentObject(AppNavigationState())
    }
}
