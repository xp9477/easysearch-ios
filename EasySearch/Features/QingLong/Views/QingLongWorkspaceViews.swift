import SwiftUI

struct QingLongWorkspaceCard: View {
    @ObservedObject var viewModel: QingLongViewModel
    let relativeDateText: (Date) -> String
    let toggleEnvironmentAction: (QingLongEnvironment) -> Void
    let primaryCronAction: (QingLongCron) -> Void
    let toggleCronEnabledAction: (QingLongCron) -> Void
    let logAction: (QingLongCron) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            QingLongSectionHeader(
                eyebrow: "Workspace",
                title: "管理工作区",
                description: viewModel.profile == nil
                    ? "连接成功后，这里会切换成环境变量和定时任务两个管理工作区。"
                    : "把高频运维动作收敛成两个工作区，再用搜索和筛选快速定位目标。"
            )

            if viewModel.profile == nil {
                QingLongEmptyState(
                    icon: "rectangle.split.2x1",
                    title: "还没有进入管理态",
                    description: "先完成连接，再使用环境变量和定时任务工作区。"
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
        .padding(24)
        .cardStyle()
    }
}

private struct QingLongEnvironmentWorkspace: View {
    @ObservedObject var viewModel: QingLongViewModel
    let toggleEnvironmentAction: (QingLongEnvironment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            QingLongSearchField(text: $viewModel.environmentSearchText, placeholder: "搜索变量名或备注")

            QingLongFilterBar(
                selection: $viewModel.environmentFilter,
                options: QingLongEnvironmentFilter.allCases,
                title: \.title
            )

            Text("显示 \(viewModel.filteredEnvironments.count) / \(viewModel.environments.count) 个变量，默认优先展示 Pinned 和启用项。")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            if viewModel.environments.isEmpty {
                QingLongEmptyState(
                    icon: "shippingbox",
                    title: "暂无环境变量",
                    description: "当前面板没有返回变量，或者应用权限里没有 envs 访问能力。"
                )
            } else if viewModel.filteredEnvironments.isEmpty {
                QingLongEmptyState(
                    icon: "magnifyingglass",
                    title: "没有匹配的变量",
                    description: "调整关键词或筛选条件后再试。"
                )
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.filteredEnvironments) { environment in
                        QingLongEnvironmentRow(
                            environment: environment,
                            isPending: viewModel.isEnvironmentPending(environment.id),
                            toggleEnabledAction: {
                                toggleEnvironmentAction(environment)
                            }
                        )
                    }
                }
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
        VStack(alignment: .leading, spacing: 16) {
            QingLongSearchField(text: $viewModel.cronSearchText, placeholder: "搜索任务名、命令或标签")

            QingLongFilterBar(
                selection: $viewModel.cronFilter,
                options: QingLongCronFilter.allCases,
                title: \.title
            )

            Text("显示 \(viewModel.filteredCrons.count) / \(viewModel.crons.count) 个任务，优先把运行中任务和最近执行过的任务排在前面。")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            if viewModel.crons.isEmpty {
                QingLongEmptyState(
                    icon: "clock.arrow.circlepath",
                    title: "暂无定时任务",
                    description: "当前面板没有返回 cron 数据，或者应用权限里没有 crons 访问能力。"
                )
            } else if viewModel.filteredCrons.isEmpty {
                QingLongEmptyState(
                    icon: "magnifyingglass",
                    title: "没有匹配的任务",
                    description: "调整关键词或筛选条件后再试。"
                )
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.filteredCrons) { cron in
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
                    }
                }
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
