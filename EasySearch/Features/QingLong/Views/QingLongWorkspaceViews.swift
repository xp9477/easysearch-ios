import SwiftUI

struct QingLongWorkspaceCard: View {
    @ObservedObject var viewModel: QingLongViewModel
    let relativeDateText: (Date) -> String
    let openConfigurationAction: () -> Void
    let toggleEnvironmentAction: (QingLongEnvironment) -> Void
    let primaryCronAction: (QingLongCron) -> Void
    let toggleCronEnabledAction: (QingLongCron) -> Void
    let logAction: (QingLongCron) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.profile == nil {
                QingLongEmptyState(
                    icon: "server.rack",
                    title: "未连接",
                    description: nil,
                    actionTitle: "去设置",
                    action: openConfigurationAction
                )
            } else {
                Picker("管理工作区", selection: $viewModel.selectedSection) {
                    ForEach(QingLongWorkspaceSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)

                if viewModel.selectedSection == .environments {
                    QingLongEnvironmentWorkspace(
                        viewModel: viewModel,
                        toggleEnvironmentAction: toggleEnvironmentAction
                    )
                } else {
                    QingLongCronWorkspace(
                        viewModel: viewModel,
                        relativeDateText: relativeDateText,
                        primaryCronAction: primaryCronAction,
                        toggleCronEnabledAction: toggleCronEnabledAction,
                        logAction: logAction
                    )
                }
            }
        }
        .padding(14)
        .cardStyle()
    }
}

private struct QingLongEnvironmentWorkspace: View {
    @ObservedObject var viewModel: QingLongViewModel
    let toggleEnvironmentAction: (QingLongEnvironment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                QingLongSearchField(text: $viewModel.environmentSearchText, placeholder: "搜索变量")

                QingLongTag(
                    text: "\(viewModel.filteredEnvironments.count)/\(viewModel.environments.count)",
                    color: Color.secondary
                )
            }

            QingLongFilterBar(
                selection: $viewModel.environmentFilter,
                options: QingLongEnvironmentFilter.allCases,
                title: \.title
            )

            if viewModel.environments.isEmpty {
                QingLongEmptyState(
                    icon: "shippingbox",
                    title: "没有变量",
                    description: nil
                )
            } else if viewModel.filteredEnvironments.isEmpty {
                QingLongEmptyState(
                    icon: "magnifyingglass",
                    title: "无匹配结果",
                    description: nil
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.filteredEnvironments.enumerated()), id: \.element.id) { index, environment in
                        QingLongEnvironmentRow(
                            environment: environment,
                            isPending: viewModel.isEnvironmentPending(environment.id),
                            toggleEnabledAction: {
                                toggleEnvironmentAction(environment)
                            }
                        )

                        if index < viewModel.filteredEnvironments.count - 1 {
                            Divider()
                                .padding(.leading, 12)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                )
            }
        }
    }
}

private struct QingLongCronWorkspace: View {
    @ObservedObject var viewModel: QingLongViewModel
    let relativeDateText: (Date) -> String
    let primaryCronAction: (QingLongCron) -> Void
    let toggleCronEnabledAction: (QingLongCron) -> Void
    let logAction: (QingLongCron) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                QingLongSearchField(text: $viewModel.cronSearchText, placeholder: "搜索任务")

                QingLongTag(
                    text: "\(viewModel.filteredCrons.count)/\(viewModel.crons.count)",
                    color: Color.secondary
                )
            }

            QingLongFilterBar(
                selection: $viewModel.cronFilter,
                options: QingLongCronFilter.allCases,
                title: \.title
            )

            if viewModel.crons.isEmpty {
                QingLongEmptyState(
                    icon: "clock.arrow.circlepath",
                    title: "没有任务",
                    description: nil
                )
            } else if viewModel.filteredCrons.isEmpty {
                QingLongEmptyState(
                    icon: "magnifyingglass",
                    title: "无匹配结果",
                    description: nil
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.filteredCrons.enumerated()), id: \.element.id) { index, cron in
                        QingLongCronRow(
                            cron: cron,
                            relativeDateText: relativeDateText,
                            isPending: viewModel.isCronPending(cron.id),
                            isLogLoading: viewModel.isLoadingLog(for: cron.id),
                            primaryAction: {
                                primaryCronAction(cron)
                            },
                            toggleEnabledAction: {
                                toggleCronEnabledAction(cron)
                            },
                            logAction: {
                                logAction(cron)
                            }
                        )

                        if index < viewModel.filteredCrons.count - 1 {
                            Divider()
                                .padding(.leading, 12)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                )
            }
        }
    }
}

private struct QingLongEnvironmentRow: View {
    let environment: QingLongEnvironment
    let isPending: Bool
    let toggleEnabledAction: () -> Void

    @State private var revealsValue = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(environment.titleText)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if !environment.remarks.isEmpty {
                        Text(environment.remarks)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    if environment.isPinned {
                        QingLongTag(text: "Pinned", color: .blue)
                    }

                    QingLongTag(
                        text: environment.isEnabled ? "启用" : "停用",
                        color: environment.isEnabled ? .green : .orange
                    )

                    if isPending {
                        ProgressView()
                            .scaleEffect(0.85)
                    }

                    Button(action: toggleEnabledAction) {
                        Text(environment.isEnabled ? "禁用" : "启用")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(environment.isEnabled ? .orange : .green)
                    .disabled(isPending)
                }
            }

            HStack(alignment: .top, spacing: 10) {
                Text(revealsValue ? visibleValue : environment.maskedValue)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        revealsValue.toggle()
                    }
                } label: {
                    Image(systemName: revealsValue ? "eye.slash" : "eye")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(cron.primaryTitle)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if !cron.secondaryTitle.isEmpty {
                        Text(cron.secondaryTitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 12)

                if isPending {
                    ProgressView()
                        .scaleEffect(0.85)
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

            Text(cron.command.isEmpty ? "未返回命令内容" : cron.command)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)

            HStack(spacing: 10) {
                if let lastRunningAt = cron.lastRunningAt {
                    Label(relativeDateText(lastRunningAt), systemImage: "clock")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Text("未运行")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button(action: primaryAction) {
                    Image(systemName: cron.isRunning ? "stop.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 14, height: 14)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(cron.isRunning ? .orange : .green)
                .disabled(isPending)

                Button(action: logAction) {
                    Group {
                        if isLogLoading {
                            ProgressView()
                                .scaleEffect(0.85)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "doc.text")
                                .frame(width: 14, height: 14)
                        }
                    }
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(.green)
                .disabled(isPending || !cron.hasLog || isLogLoading)

                Menu {
                    Button(action: toggleEnabledAction) {
                        Label(cron.isEnabled ? "禁用任务" : "启用任务", systemImage: cron.isEnabled ? "pause.circle" : "checkmark.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 15, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
                .disabled(isPending)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
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
