import SwiftUI

public struct QingLongView: View {
    @EnvironmentObject private var navigationState: AppNavigationState
    @StateObject private var viewModel = QingLongViewModel()
    @Environment(\.openURL) private var openURL

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

                QingLongWorkspaceCard(
                    viewModel: viewModel,
                    relativeDateText: relativeDateText(_:),
                    openConfigurationAction: {
                        navigationState.openSettings(.qingLong)
                    },
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
    }

    private var overviewMetrics: [QingLongMetric] {
        let runningCronCount = viewModel.crons.filter(\.isRunning).count

        return [
            QingLongMetric(id: "envs", symbol: "shippingbox", title: "变量", value: "\(viewModel.environments.count)"),
            QingLongMetric(id: "crons", symbol: "clock.arrow.circlepath", title: "任务", value: "\(viewModel.crons.count)"),
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
