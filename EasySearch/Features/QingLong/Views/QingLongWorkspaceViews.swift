import SwiftUI

struct QingLongWorkspaceCard: View {
    @ObservedObject var viewModel: QingLongViewModel
    let relativeDateText: (Date) -> String
    let openConfigurationAction: () -> Void
    let openSharedEnvironmentsAction: () -> Void
    let editScriptEnvironmentAction: (QingLongCron) -> Void
    let primaryCronAction: (QingLongCron) -> Void
    let toggleCronEnabledAction: (QingLongCron) -> Void
    let logAction: (QingLongCron) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.profile == nil {
                QingLongEmptyState(
                    icon: "server.rack",
                    title: "未连接",
                    actionTitle: "去设置",
                    action: openConfigurationAction
                )
            } else {
                QingLongCronWorkspace(
                    viewModel: viewModel,
                    relativeDateText: relativeDateText,
                    openSharedEnvironmentsAction: openSharedEnvironmentsAction,
                    editScriptEnvironmentAction: editScriptEnvironmentAction,
                    primaryCronAction: primaryCronAction,
                    toggleCronEnabledAction: toggleCronEnabledAction,
                    logAction: logAction
                )
            }
        }
        .padding(14)
        .cardStyle()
    }
}

private struct QingLongCronWorkspace: View {
    @ObservedObject var viewModel: QingLongViewModel
    let relativeDateText: (Date) -> String
    let openSharedEnvironmentsAction: () -> Void
    let editScriptEnvironmentAction: (QingLongCron) -> Void
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

                Button(action: openSharedEnvironmentsAction) {
                    HStack(spacing: 6) {
                        Image(systemName: "shippingbox")
                        Text(sharedButtonTitle)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.blue.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
            }

            QingLongFilterBar(
                selection: $viewModel.cronFilter,
                options: QingLongCronFilter.allCases,
                title: \.title
            )

            if viewModel.crons.isEmpty {
                QingLongEmptyState(
                    icon: "clock.arrow.circlepath",
                    title: "没有任务"
                )
            } else if viewModel.filteredCrons.isEmpty {
                QingLongEmptyState(
                    icon: "magnifyingglass",
                    title: "无匹配结果"
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.filteredCrons.enumerated()), id: \.element.id) { index, cron in
                        QingLongCronRow(
                            cron: cron,
                            linkedEnvironment: viewModel.linkedEnvironment(for: cron),
                            relativeDateText: relativeDateText,
                            isPending: viewModel.isCronPending(cron.id),
                            isLogLoading: viewModel.isLoadingLog(for: cron.id),
                            editScriptEnvironmentAction: {
                                editScriptEnvironmentAction(cron)
                            },
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

    private var sharedButtonTitle: String {
        viewModel.sharedEnvironmentCount == 0 ? "共享变量" : "共享 \(viewModel.sharedEnvironmentCount)"
    }
}

private struct QingLongCronRow: View {
    let cron: QingLongCron
    let linkedEnvironment: QingLongLinkedEnvironment?
    let relativeDateText: (Date) -> String
    let isPending: Bool
    let isLogLoading: Bool
    let editScriptEnvironmentAction: () -> Void
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

            if let linkedEnvironment {
                QingLongLinkedEnvironmentSummary(
                    linkedEnvironment: linkedEnvironment,
                    editAction: editScriptEnvironmentAction
                )
            }

            HStack(spacing: 10) {
                if let lastExecutedAt = cron.lastExecutedAt {
                    Label(relativeDateText(lastExecutedAt), systemImage: "clock")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Text("未执行")
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

private struct QingLongLinkedEnvironmentSummary: View {
    let linkedEnvironment: QingLongLinkedEnvironment
    let editAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    QingLongTag(text: linkedEnvironment.scriptKey, color: .blue)
                    QingLongTag(text: statusText, color: statusColor)

                    if let primaryEnvironment = linkedEnvironment.primaryEnvironment, !primaryEnvironment.isEnabled {
                        QingLongTag(text: "已禁用", color: .orange)
                    }

                    if linkedEnvironment.auxiliaryCount > 0 {
                        QingLongTag(text: "+\(linkedEnvironment.auxiliaryCount)", color: .purple)
                    }
                }

                Text(valuePreview)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Button(action: editAction) {
                Text(linkedEnvironment.primaryEnvironment == nil ? "新建变量" : "编辑变量")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .tint(.blue)
        }
    }

    private var statusText: String {
        switch linkedEnvironment.status {
        case .missing:
            return "未创建"
        case .empty:
            return "空值"
        case .configured:
            return "已配置"
        }
    }

    private var statusColor: Color {
        switch linkedEnvironment.status {
        case .missing:
            return .orange
        case .empty:
            return .blue
        case .configured:
            return .green
        }
    }

    private var valuePreview: String {
        guard let primaryEnvironment = linkedEnvironment.primaryEnvironment else {
            return "未创建"
        }

        return primaryEnvironment.isEmptyValue ? "空值" : primaryEnvironment.maskedValue
    }
}

struct QingLongEnvironmentEditorSheet: View {
    let context: QingLongEnvironmentEditorContext
    let isExistingEnvironmentPending: Bool
    let saveAction: (String, String, String) async -> Bool
    let toggleEnabledAction: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var value: String
    @State private var remarks: String
    @State private var isSaving = false

    init(
        context: QingLongEnvironmentEditorContext,
        isExistingEnvironmentPending: Bool,
        saveAction: @escaping (String, String, String) async -> Bool,
        toggleEnabledAction: (() -> Void)? = nil
    ) {
        self.context = context
        self.isExistingEnvironmentPending = isExistingEnvironmentPending
        self.saveAction = saveAction
        self.toggleEnabledAction = toggleEnabledAction
        _name = State(initialValue: context.initialName)
        _value = State(initialValue: context.initialValue)
        _remarks = State(initialValue: context.initialRemarks)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let subtitle = context.subtitle {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("变量名")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)

                        TextField("变量名", text: $name)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .disabled(!context.allowsNameEditing)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(.secondarySystemGroupedBackground))
                            )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("变量值")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text("可留空")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        TextEditor(text: $value)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .frame(minHeight: 180)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(.secondarySystemGroupedBackground))
                            )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("备注")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)

                        TextField("可选", text: $remarks)
                            .font(.system(size: 14, weight: .medium))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(.secondarySystemGroupedBackground))
                            )
                    }

                    if let environment = context.environment, let toggleEnabledAction {
                        Button(action: toggleEnabledAction) {
                            HStack {
                                Text(environment.isEnabled ? "禁用变量" : "启用变量")

                                if isExistingEnvironmentPending {
                                    ProgressView()
                                        .scaleEffect(0.85)
                                }
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                        .tint(environment.isEnabled ? .orange : .green)
                        .disabled(isExistingEnvironmentPending || isSaving)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(context.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "保存中" : "保存") {
                        Task {
                            isSaving = true
                            defer { isSaving = false }

                            let didSave = await saveAction(name, value, remarks)
                            if didSave {
                                dismiss()
                            }
                        }
                    }
                    .disabled(isSaving || isExistingEnvironmentPending)
                }
            }
        }
    }
}

struct QingLongSharedEnvironmentsSheet: View {
    @ObservedObject var viewModel: QingLongViewModel
    let saveEnvironmentAction: (QingLongEnvironmentEditorContext, String, String, String) async -> Bool
    let toggleEnvironmentAction: (QingLongEnvironment) -> Void

    @State private var searchText = ""
    @State private var selectedEditorContext: QingLongEnvironmentEditorContext?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    QingLongSearchField(text: $searchText, placeholder: "搜索共享变量")

                    QingLongTag(
                        text: "\(filteredSharedEnvironments.count)/\(viewModel.sharedEnvironments.count)",
                        color: Color.secondary
                    )
                }

                if viewModel.sharedEnvironments.isEmpty {
                    QingLongEmptyState(
                        icon: "shippingbox",
                        title: "没有共享变量",
                        actionTitle: "新建",
                        action: {
                            selectedEditorContext = viewModel.makeSharedEnvironmentEditor()
                        }
                    )
                } else if filteredSharedEnvironments.isEmpty {
                    QingLongEmptyState(
                        icon: "magnifyingglass",
                        title: "无匹配结果"
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(filteredSharedEnvironments.enumerated()), id: \.element.id) { index, environment in
                            QingLongSharedEnvironmentRow(
                                environment: environment,
                                isPending: viewModel.isEnvironmentPending(environment.id),
                                editAction: {
                                    selectedEditorContext = viewModel.makeSharedEnvironmentEditor(for: environment)
                                },
                                toggleEnabledAction: {
                                    toggleEnvironmentAction(environment)
                                }
                            )

                            if index < filteredSharedEnvironments.count - 1 {
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
            .padding(16)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("共享变量")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("新建") {
                        selectedEditorContext = viewModel.makeSharedEnvironmentEditor()
                    }
                }
            }
        }
        .sheet(item: $selectedEditorContext) { context in
            QingLongEnvironmentEditorSheet(
                context: context,
                isExistingEnvironmentPending: context.environment.map { viewModel.isEnvironmentPending($0.id) } ?? false,
                saveAction: { name, value, remarks in
                    await saveEnvironmentAction(context, name, value, remarks)
                },
                toggleEnabledAction: context.environment.map { environment in
                    {
                        toggleEnvironmentAction(environment)
                    }
                }
            )
        }
    }

    private var filteredSharedEnvironments: [QingLongEnvironment] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return viewModel.sharedEnvironments }

        return viewModel.sharedEnvironments.filter { environment in
            [
                environment.name,
                environment.remarks,
                environment.value
            ]
            .joined(separator: " ")
            .localizedCaseInsensitiveContains(query)
        }
    }
}

private struct QingLongSharedEnvironmentRow: View {
    let environment: QingLongEnvironment
    let isPending: Bool
    let editAction: () -> Void
    let toggleEnabledAction: () -> Void

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

                if isPending {
                    ProgressView()
                        .scaleEffect(0.85)
                }
            }

            Text(environment.isEmptyValue ? "空值" : environment.maskedValue)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)

            HStack(spacing: 8) {
                QingLongTag(text: environment.isEnabled ? "启用" : "停用", color: environment.isEnabled ? .green : .orange)

                Spacer(minLength: 0)

                Button(action: toggleEnabledAction) {
                    Text(environment.isEnabled ? "禁用" : "启用")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(environment.isEnabled ? .orange : .green)
                .disabled(isPending)

                Button(action: editAction) {
                    Text("编辑")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }
}
