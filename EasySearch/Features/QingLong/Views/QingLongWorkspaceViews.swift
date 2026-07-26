import SwiftUI

private enum QingLongJSONFormatter {
    static func editorFormatted(_ value: String) -> String? {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        if let entries = decodeEntries(from: value), entries.count > 1 {
            return entries.compactMap { render($0, pretty: true) }.joined(separator: "\n\n")
        }

        guard let object = decodeObject(from: value) else {
            return nil
        }

        return render(object, pretty: true)
    }

    static func storageFormatted(_ value: String) -> String? {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        if let entries = decodeEntries(from: value), entries.count > 1 {
            return entries.compactMap { render($0, pretty: false) }.joined(separator: "\n")
        }

        guard let object = decodeObject(from: value) else {
            return nil
        }

        return render(object, pretty: false)
    }

    private static func decodeEntries(from value: String) -> [Any]? {
        let blankLineBlocks = splitByBlankLines(value)
        if blankLineBlocks.count > 1, let objects = decodeAll(blankLineBlocks) {
            return objects
        }

        let nonEmptyLines = value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if nonEmptyLines.count > 1, let objects = decodeAll(nonEmptyLines) {
            return objects
        }

        return nil
    }

    private static func splitByBlankLines(_ value: String) -> [String] {
        var blocks: [String] = []
        var currentLines: [String] = []

        value.enumerateLines { line, _ in
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !currentLines.isEmpty {
                    blocks.append(currentLines.joined(separator: "\n"))
                    currentLines.removeAll()
                }
            } else {
                currentLines.append(line)
            }
        }

        if !currentLines.isEmpty {
            blocks.append(currentLines.joined(separator: "\n"))
        }

        return blocks
    }

    private static func decodeAll(_ values: [String]) -> [Any]? {
        var objects: [Any] = []

        for item in values {
            guard let object = decodeObject(from: item) else {
                return nil
            }
            objects.append(object)
        }

        return objects
    }

    private static func decodeObject(from value: String) -> Any? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            return nil
        }

        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    private static func render(_ object: Any, pretty: Bool) -> String? {
        var options: JSONSerialization.WritingOptions = [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes]
        if pretty {
            options.insert(.prettyPrinted)
        }

        guard
            let data = try? JSONSerialization.data(withJSONObject: object, options: options),
            let value = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return value
    }
}

struct QingLongSubscriptionWorkspaceCard: View {
    @ObservedObject var viewModel: QingLongViewModel
    let logAction: (QingLongSubscription) -> Void
    let primaryAction: (QingLongSubscription) -> Void
    let toggleEnabledAction: (QingLongSubscription) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            if viewModel.profile == nil {
                QingLongEmptyState(
                    icon: "arrow.down.circle",
                    title: "订阅管理",
                    description: "连接青龙后可查看并手动拉取订阅。"
                )
            } else {
                QingLongSubscriptionWorkspace(
                    viewModel: viewModel,
                    logAction: logAction,
                    primaryAction: primaryAction,
                    toggleEnabledAction: toggleEnabledAction
                )
            }
        }
        .esCard()
    }
}

private struct QingLongSubscriptionWorkspace: View {
    @ObservedObject var viewModel: QingLongViewModel
    let logAction: (QingLongSubscription) -> Void
    let primaryAction: (QingLongSubscription) -> Void
    let toggleEnabledAction: (QingLongSubscription) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            ESSectionHeader(title: "订阅管理", subtitle: summaryText)

            QingLongSearchField(text: $viewModel.subscriptionSearchText, placeholder: "搜索订阅")

            QingLongFilterBar(
                selection: $viewModel.subscriptionFilter,
                options: QingLongSubscriptionFilter.allCases,
                title: \.title
            )

            if viewModel.subscriptions.isEmpty {
                QingLongEmptyState(
                    icon: "arrow.down.circle",
                    title: "没有订阅",
                    description: "在青龙面板中创建订阅后，这里可以直接拉取和查看日志。"
                )
            } else if viewModel.filteredSubscriptions.isEmpty {
                QingLongEmptyState(
                    icon: "magnifyingglass",
                    title: "无匹配结果"
                )
            } else {
                LazyVStack(spacing: ESUI.Space.sm) {
                    ForEach(viewModel.filteredSubscriptions) { subscription in
                        QingLongSubscriptionRow(
                            subscription: subscription,
                            isPending: viewModel.isSubscriptionPending(subscription.id),
                            isLogLoading: viewModel.isLoadingSubscriptionLog(for: subscription.id),
                            primaryAction: {
                                primaryAction(subscription)
                            },
                            logAction: {
                                logAction(subscription)
                            },
                            toggleEnabledAction: {
                                toggleEnabledAction(subscription)
                            }
                        )
                    }
                }
            }
        }
    }

    private var summaryText: String {
        let runningCount = viewModel.subscriptions.filter { $0.isRunning || $0.isQueued }.count
        return "\(viewModel.filteredSubscriptions.count)/\(viewModel.subscriptions.count) 个订阅，\(runningCount) 个拉取中"
    }
}

private struct QingLongSubscriptionRow: View {
    let subscription: QingLongSubscription
    let isPending: Bool
    let isLogLoading: Bool
    let primaryAction: () -> Void
    let logAction: () -> Void
    let toggleEnabledAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            HStack(alignment: .top, spacing: ESUI.Space.sm) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(statusColor)
                    .frame(width: 4, height: 42)

                VStack(alignment: .leading, spacing: ESUI.Space.xs) {
                    HStack(alignment: .center, spacing: ESUI.Space.xs) {
                        Text(subscription.titleText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        QingLongSubscriptionStateBadge(subscription: subscription)

                        if subscription.autoAddCron {
                            QingLongTag(text: "自动任务", color: .blue)
                        }

                        Spacer(minLength: 0)

                        if isPending {
                            ProgressView()
                                .scaleEffect(0.85)
                        }
                    }

                    Text(subscription.url)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    HStack(spacing: ESUI.Space.xs) {
                        Label(subscription.scheduleText, systemImage: "clock")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)

                        if !subscription.detailText.isEmpty {
                            Text(subscription.detailText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            HStack(spacing: ESUI.Space.sm) {
                Button(action: primaryAction) {
                    Label(primaryButtonTitle, systemImage: primaryButtonSymbol)
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.glassProminent)
                .tint(subscription.isRunning || subscription.isQueued ? .orange : .green)
                .disabled(isPending || (!subscription.isEnabled && !subscription.isRunning && !subscription.isQueued))

                Button(action: logAction) {
                    HStack(spacing: ESUI.Space.xs) {
                        if isLogLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "doc.text")
                                .frame(width: 12, height: 12)
                        }

                        Text("日志")
                    }
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                }
                .buttonStyle(.glass)
                .tint(.accentColor)
                .disabled(isPending || isLogLoading || !subscription.hasLog)

                Menu {
                    Button(action: toggleEnabledAction) {
                        Label(subscription.isEnabled ? "禁用订阅" : "启用订阅", systemImage: subscription.isEnabled ? "pause.circle" : "play.circle")
                    }
                } label: {
                    Label("更多", systemImage: "ellipsis.circle")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.glass)
                .tint(.secondary)
                .disabled(isPending)
            }
        }
        .padding(ESUI.Space.md)
        .background(
            RoundedRectangle(cornerRadius: ESUI.cardCornerRadius, style: .continuous)
                .fill(ESUI.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ESUI.cardCornerRadius, style: .continuous)
                .stroke(statusColor.opacity(0.12), lineWidth: 1)
        )
    }

    private var primaryButtonTitle: String {
        subscription.isRunning || subscription.isQueued ? "停止" : "拉取"
    }

    private var primaryButtonSymbol: String {
        subscription.isRunning || subscription.isQueued ? "stop.fill" : "arrow.down.circle.fill"
    }

    private var statusColor: Color {
        if subscription.isRunning {
            return .green
        }

        if subscription.isQueued {
            return .blue
        }

        if !subscription.isEnabled {
            return .orange
        }

        return .secondary
    }
}

private struct QingLongSubscriptionStateBadge: View {
    let subscription: QingLongSubscription

    var body: some View {
        HStack(spacing: ESUI.Space.xs) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)

            Text(subscription.statusText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, ESUI.Space.sm)
        .padding(.vertical, ESUI.Space.xs)
        .background(
            Capsule(style: .continuous)
                .fill(statusColor.opacity(0.12))
        )
    }

    private var statusColor: Color {
        if subscription.isRunning {
            return .green
        }

        if subscription.isQueued {
            return .blue
        }

        if !subscription.isEnabled {
            return .orange
        }

        return .gray
    }
}

struct QingLongWorkspaceCard: View {
    @ObservedObject var viewModel: QingLongViewModel
    let relativeDateText: (Date) -> String
    let openConfigurationAction: () -> Void
    let openSharedEnvironmentsAction: () -> Void
    let editScriptEnvironmentAction: (QingLongCron) -> Void
    let editCronAction: (QingLongCron) -> Void
    let primaryCronAction: (QingLongCron) -> Void
    let toggleCronEnabledAction: (QingLongCron) -> Void
    let logAction: (QingLongCron) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
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
                    editCronAction: editCronAction,
                    primaryCronAction: primaryCronAction,
                    toggleCronEnabledAction: toggleCronEnabledAction,
                    logAction: logAction
                )
            }
        }
        .esCard()
    }
}

private struct QingLongCronWorkspace: View {
    @ObservedObject var viewModel: QingLongViewModel
    let relativeDateText: (Date) -> String
    let openSharedEnvironmentsAction: () -> Void
    let editScriptEnvironmentAction: (QingLongCron) -> Void
    let editCronAction: (QingLongCron) -> Void
    let primaryCronAction: (QingLongCron) -> Void
    let toggleCronEnabledAction: (QingLongCron) -> Void
    let logAction: (QingLongCron) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            HStack(alignment: .top, spacing: ESUI.Space.sm) {
                VStack(alignment: .leading, spacing: ESUI.Space.xxs) {
                    Text("任务列表")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(summaryText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: ESUI.Space.xs)

                Button(action: openSharedEnvironmentsAction) {
                    Label(sharedButtonTitle, systemImage: "shippingbox")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.glass)
            }

            QingLongSearchField(text: $viewModel.cronSearchText, placeholder: "搜索任务")

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
                LazyVStack(spacing: ESUI.Space.xs) {
                    ForEach(viewModel.filteredCrons) { cron in
                        QingLongCronListRow(
                            cron: cron,
                            relativeDateText: relativeDateText,
                            isLogLoading: viewModel.isLoadingLog(for: cron.id),
                            destination: {
                                QingLongCronDetailView(
                                    viewModel: viewModel,
                                    cronID: cron.id,
                                    relativeDateText: relativeDateText,
                                    editScriptEnvironmentAction: editScriptEnvironmentAction,
                                    editCronAction: editCronAction,
                                    primaryCronAction: primaryCronAction,
                                    toggleCronEnabledAction: toggleCronEnabledAction,
                                    logAction: logAction
                                )
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

    private var sharedButtonTitle: String {
        viewModel.sharedEnvironmentCount == 0 ? "共享变量" : "共享 \(viewModel.sharedEnvironmentCount)"
    }

    private var summaryText: String {
        let runningCount = viewModel.crons.filter(\.isRunning).count
        return "\(viewModel.filteredCrons.count)/\(viewModel.crons.count) 个任务，\(runningCount) 个运行中"
    }
}

private struct QingLongCronListRow<Destination: View>: View {
    let cron: QingLongCron
    let relativeDateText: (Date) -> String
    let isLogLoading: Bool
    @ViewBuilder let destination: () -> Destination
    let logAction: () -> Void

    var body: some View {
        HStack(spacing: ESUI.Space.sm) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(statusColor)
                .frame(width: 4, height: 34)

            NavigationLink(destination: destination()) {
                HStack(spacing: ESUI.Space.sm) {
                    VStack(alignment: .leading, spacing: ESUI.Space.xxs) {
                        Text(cron.primaryTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        HStack(spacing: 5) {
                            Image(systemName: "clock")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)

                            if let lastExecutedAt = cron.lastExecutedAt {
                                Text(relativeDateText(lastExecutedAt))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("未执行")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.secondary.opacity(0.7))
                }
            }
            .buttonStyle(.plain)

            Button(action: logAction) {
                Group {
                    if isLogLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "doc.text.magnifyingglass")
                            .frame(width: 14, height: 14)
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(cron.hasLog ? Color.green : Color.secondary)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(cron.hasLog ? Color.accentColor.opacity(0.12) : Color(.quaternarySystemFill))
                )
            }
            .buttonStyle(.plain)
            .disabled(!cron.hasLog || isLogLoading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                .fill(ESUI.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                .stroke(statusColor.opacity(0.14), lineWidth: 1)
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

        return .secondary
    }
}

private struct QingLongLinkedEnvironmentSummary: View {
    let linkedEnvironment: QingLongLinkedEnvironment
    let editAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: ESUI.Space.xs) {
            Image(systemName: "shippingbox")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.blue)

            Text(linkedEnvironment.scriptKey)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)

            QingLongTag(text: statusText, color: statusColor)

            if let primaryEnvironment = linkedEnvironment.primaryEnvironment, !primaryEnvironment.isEnabled {
                QingLongTag(text: "已禁用", color: .orange)
            }

            if linkedEnvironment.auxiliaryCount > 0 {
                QingLongTag(text: "+\(linkedEnvironment.auxiliaryCount)", color: .purple)
            }

            Text(valuePreview)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button(action: editAction) {
                Image(systemName: "slider.horizontal.3")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, ESUI.Space.xs)
            }
            .buttonStyle(.glass)
            .tint(.blue)
        }
        .padding(.horizontal, ESUI.Space.sm)
        .padding(.vertical, ESUI.Space.xs)
        .background(
            RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.58))
        )
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
        _value = State(initialValue: QingLongJSONFormatter.editorFormatted(context.initialValue) ?? context.initialValue)
        _remarks = State(initialValue: context.initialRemarks)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ESUI.Space.md) {
                    if let subtitle = context.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: ESUI.Space.xs) {
                        Text("变量名")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        TextField("变量名", text: $name)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .disabled(!context.allowsNameEditing)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                                    .fill(ESUI.surface)
                            )
                    }

                    VStack(alignment: .leading, spacing: ESUI.Space.xs) {
                        HStack {
                            Text("变量值")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button("格式化") {
                                value = QingLongJSONFormatter.editorFormatted(value) ?? value
                            }
                            .font(.caption2.weight(.semibold))
                            .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            Text("可留空")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        TextEditor(text: $value)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .frame(minHeight: 180)
                            .padding(ESUI.Space.sm)
                            .background(
                                RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                                    .fill(ESUI.surface)
                            )
                    }

                    VStack(alignment: .leading, spacing: ESUI.Space.xs) {
                        Text("备注")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        TextField("可选", text: $remarks)
                            .font(.subheadline)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                                    .fill(ESUI.surface)
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
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.glass)
                        .tint(environment.isEnabled ? .orange : .green)
                        .disabled(isExistingEnvironmentPending || isSaving)
                    }
                }
                .padding(ESUI.Space.md)
            }
            .background(ESUI.appBackground.ignoresSafeArea())
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

                            let normalizedValue = QingLongJSONFormatter.storageFormatted(value) ?? value
                            if let editorValue = QingLongJSONFormatter.editorFormatted(normalizedValue), editorValue != value {
                                value = editorValue
                            }

                            let didSave = await saveAction(name, normalizedValue, remarks)
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

struct QingLongCronEditorSheet: View {
    let context: QingLongCronEditorContext
    let isPending: Bool
    let saveAction: (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var schedule: String
    @State private var isSaving = false

    init(
        context: QingLongCronEditorContext,
        isPending: Bool,
        saveAction: @escaping (String) async -> Bool
    ) {
        self.context = context
        self.isPending = isPending
        self.saveAction = saveAction
        _schedule = State(initialValue: context.initialSchedule)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: ESUI.Space.md) {
                Text(context.title)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: ESUI.Space.xs) {
                    Text("Cron")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    TextField("例如 */5 * * * *", text: $schedule, axis: .vertical)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                                .fill(ESUI.surface)
                        )
                }

                Text("只修改主 cron 表达式，命令和其它配置保持不变。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
            .padding(ESUI.Space.md)
            .background(ESUI.appBackground.ignoresSafeArea())
            .navigationTitle("编辑调度")
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

                            let didSave = await saveAction(schedule)
                            if didSave {
                                dismiss()
                            }
                        }
                    }
                    .disabled(isSaving || isPending)
                }
            }
        }
    }
}

private struct QingLongCronDetailView: View {
    @ObservedObject var viewModel: QingLongViewModel
    let cronID: Int
    let relativeDateText: (Date) -> String
    let editScriptEnvironmentAction: (QingLongCron) -> Void
    let editCronAction: (QingLongCron) -> Void
    let primaryCronAction: (QingLongCron) -> Void
    let toggleCronEnabledAction: (QingLongCron) -> Void
    let logAction: (QingLongCron) -> Void

    var body: some View {
        Group {
            if let cron = currentCron {
                ScrollView {
                    VStack(alignment: .leading, spacing: ESUI.Space.md) {
                        QingLongCronSummaryCard(
                            cron: cron,
                            linkedEnvironment: viewModel.linkedEnvironment(for: cron),
                            relativeDateText: relativeDateText,
                            isEnvironmentPending: viewModel.linkedEnvironment(for: cron).flatMap { $0.primaryEnvironment }.map { viewModel.isEnvironmentPending($0.id) } ?? false,
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

                        QingLongCronScheduleCard(
                            cron: cron,
                            editAction: {
                                editCronAction(cron)
                            }
                        )

                        QingLongCronScriptCard(
                            cron: cron,
                            destination: {
                                QingLongCronScriptFileView(
                                    viewModel: viewModel,
                                    cron: cron
                                )
                            }
                        )
                    }
                    .padding(ESUI.Space.md)
                }
                .background(ESUI.appBackground.ignoresSafeArea())
                .navigationTitle(cron.primaryTitle)
                .navigationBarTitleDisplayMode(.inline)
            } else {
                QingLongEmptyState(icon: "clock.arrow.circlepath", title: "任务不存在")
                    .padding(ESUI.Space.md)
                    .background(ESUI.appBackground.ignoresSafeArea())
            }
        }
    }

    private var currentCron: QingLongCron? {
        viewModel.crons.first { $0.id == cronID }
    }
}

private struct QingLongCronSummaryCard: View {
    let cron: QingLongCron
    let linkedEnvironment: QingLongLinkedEnvironment?
    let relativeDateText: (Date) -> String
    let isEnvironmentPending: Bool
    let isPending: Bool
    let isLogLoading: Bool
    let editScriptEnvironmentAction: () -> Void
    let primaryAction: () -> Void
    let toggleEnabledAction: () -> Void
    let logAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.md) {
            HStack(spacing: ESUI.Space.xs) {
                QingLongCronStateBadge(cron: cron)

                if cron.isPinned {
                    QingLongTag(text: "Pinned", color: .teal)
                }

                Spacer(minLength: 0)

                if isPending {
                    ProgressView()
                        .scaleEffect(0.85)
                }
            }

            VStack(alignment: .leading, spacing: ESUI.Space.xs) {
                Text(cron.primaryTitle)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)

                if !cron.secondaryTitle.isEmpty {
                    Text(cron.secondaryTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: ESUI.Space.sm),
                    GridItem(.flexible(), spacing: ESUI.Space.sm)
                ],
                spacing: ESUI.Space.sm
            ) {
                QingLongDetailMetricTile(
                    title: "上次执行",
                    value: cron.lastExecutedAt.map(relativeDateText) ?? "未执行"
                )

                QingLongDetailMetricTile(
                    title: "脚本变量",
                    value: linkedEnvironment.map(environmentStatusText(for:)) ?? "无映射"
                )
            }

            if let linkedEnvironment {
                VStack(alignment: .leading, spacing: ESUI.Space.sm) {
                    HStack(spacing: ESUI.Space.xs) {
                        Text(linkedEnvironment.scriptKey)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(.primary)

                        QingLongTag(text: environmentStatusText(for: linkedEnvironment), color: environmentStatusColor(for: linkedEnvironment))

                        if let primaryEnvironment = linkedEnvironment.primaryEnvironment, !primaryEnvironment.isEnabled {
                            QingLongTag(text: "已禁用", color: .orange)
                        }

                        Spacer(minLength: 0)
                    }

                    QingLongDetailField(
                        title: "当前值",
                        value: environmentValuePreview(for: linkedEnvironment),
                        monospaced: true
                    )

                    if let remarks = linkedEnvironment.primaryEnvironment?.remarks, !remarks.isEmpty {
                        QingLongDetailField(title: "备注", value: remarks)
                    }

                    if linkedEnvironment.auxiliaryCount > 0 {
                        QingLongDetailField(title: "扩展变量", value: "\(linkedEnvironment.auxiliaryCount) 个")
                    }

                    Button(action: editScriptEnvironmentAction) {
                        Label(linkedEnvironment.primaryEnvironment == nil ? "新建变量" : "编辑变量", systemImage: "slider.horizontal.3")
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.glass)
                    .tint(.blue)
                    .disabled(isEnvironmentPending)
                }
                .padding(ESUI.Space.sm)
                .background(
                    RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                        .fill(ESUI.fill)
                )
            }

            ViewThatFits(in: .vertical) {
                HStack(spacing: ESUI.Space.sm) {
                    primaryButton
                    logButton
                    actionMenu
                }

                VStack(spacing: ESUI.Space.sm) {
                    HStack(spacing: ESUI.Space.sm) {
                        primaryButton
                        logButton
                    }

                    HStack {
                        Spacer(minLength: 0)
                        actionMenu
                    }
                }
            }
        }
        .esCard()
    }

    private var primaryButton: some View {
        Button(action: primaryAction) {
            Label(cron.isRunning ? "停止" : "运行", systemImage: cron.isRunning ? "stop.fill" : "play.fill")
                .font(.footnote.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.glassProminent)
        .tint(cron.isRunning ? .orange : .green)
        .disabled(isPending)
    }

    private var logButton: some View {
        Button(action: logAction) {
            HStack(spacing: ESUI.Space.xs) {
                if isLogLoading {
                    ProgressView()
                        .scaleEffect(0.85)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "doc.text")
                        .frame(width: 14, height: 14)
                }

                Text("查看日志")
            }
            .font(.footnote.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.glass)
        .tint(.accentColor)
        .disabled(isPending || !cron.hasLog || isLogLoading)
    }

    private var actionMenu: some View {
        Menu {
            Button(action: toggleEnabledAction) {
                Label(cron.isEnabled ? "禁用任务" : "启用任务", systemImage: cron.isEnabled ? "pause.circle" : "checkmark.circle")
            }
        } label: {
            Label("更多", systemImage: "ellipsis.circle")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .buttonStyle(.glass)
        .tint(.secondary)
        .disabled(isPending)
    }

    private func environmentStatusText(for linkedEnvironment: QingLongLinkedEnvironment) -> String {
        switch linkedEnvironment.status {
        case .missing:
            return "未创建"
        case .empty:
            return "空值"
        case .configured:
            return linkedEnvironment.primaryEnvironment?.isEnabled == false ? "已禁用" : "已配置"
        }
    }

    private func environmentStatusColor(for linkedEnvironment: QingLongLinkedEnvironment) -> Color {
        switch linkedEnvironment.status {
        case .missing:
            return .orange
        case .empty:
            return .blue
        case .configured:
            return linkedEnvironment.primaryEnvironment?.isEnabled == false ? .orange : .green
        }
    }
    
    private func environmentValuePreview(for linkedEnvironment: QingLongLinkedEnvironment) -> String {
        guard let primaryEnvironment = linkedEnvironment.primaryEnvironment else {
            return "未创建"
        }

        return primaryEnvironment.isEmptyValue ? "空值" : primaryEnvironment.maskedValue
    }
}

private struct QingLongCronScheduleCard: View {
    let cron: QingLongCron
    let editAction: () -> Void

    var body: some View {
        QingLongDetailCard(title: "调度") {
            VStack(alignment: .leading, spacing: ESUI.Space.sm) {
                HStack {
                    Spacer(minLength: 0)

                    Button(action: editAction) {
                        Label("编辑", systemImage: "square.and.pencil")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.glass)
                    .tint(.blue)
                }

                QingLongDetailField(
                    title: "主计划",
                    value: cron.schedule.isEmpty ? "未返回" : cron.schedule,
                    monospaced: true
                )

                if !cron.extraSchedules.isEmpty {
                    ForEach(Array(cron.extraSchedules.enumerated()), id: \.offset) { index, item in
                        QingLongDetailField(
                            title: "附加计划 \(index + 1)",
                            value: item.schedule,
                            monospaced: true
                        )
                    }
                }

                if !cron.labels.isEmpty {
                    QingLongDetailField(
                        title: "标签",
                        value: cron.labels.joined(separator: " · ")
                    )
                }
            }
        }
    }
}

private struct QingLongCronScriptCard<Destination: View>: View {
    let cron: QingLongCron
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        QingLongDetailCard(title: "脚本文件") {
            if let scriptLocation = cron.scriptLocation {
                VStack(alignment: .leading, spacing: ESUI.Space.sm) {
                    QingLongDetailField(title: "文件", value: scriptLocation.fileName, monospaced: true)

                    if let path = scriptLocation.path, !path.isEmpty {
                        QingLongDetailField(title: "路径", value: path, monospaced: true)
                    }

                    NavigationLink(destination: destination()) {
                        Label("查看脚本文件", systemImage: "doc.text.magnifyingglass")
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.glass)
                    .tint(.blue)
                }
            } else {
                QingLongDetailField(title: "状态", value: "未识别脚本路径")
            }
        }
    }
}

private struct QingLongCronScriptFileView: View {
    @ObservedObject var viewModel: QingLongViewModel
    let cron: QingLongCron

    @State private var scriptFile: QingLongScriptFile?
    @State private var loadError: String?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let scriptLocation = cron.scriptLocation {
                VStack(alignment: .leading, spacing: ESUI.Space.md) {
                    QingLongDetailCard(title: "文件") {
                        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
                            QingLongDetailField(title: "文件名", value: scriptLocation.fileName, monospaced: true)

                            if let path = scriptLocation.path, !path.isEmpty {
                                QingLongDetailField(title: "路径", value: path, monospaced: true)
                            }
                        }
                    }

                    QingLongDetailCard(title: "脚本内容") {
                        if isLoading && scriptFile == nil {
                            HStack(spacing: ESUI.Space.sm) {
                                ProgressView()
                                Text("加载中")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        } else if let loadError {
                            QingLongEmptyState(
                                icon: "exclamationmark.triangle",
                                title: "脚本加载失败",
                                description: loadError,
                                actionTitle: "重试",
                                action: loadScript
                            )
                        } else if let scriptFile {
                            QingLongScriptCodeView(content: formattedScriptContent(scriptFile.content))
                        } else {
                            QingLongEmptyState(icon: "doc.text", title: "没有脚本内容")
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .padding(ESUI.Space.md)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(ESUI.appBackground.ignoresSafeArea())
                .navigationTitle(scriptLocation.fileName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("刷新") {
                            loadScript()
                        }
                        .disabled(isLoading)
                    }
                }
                .task(id: scriptLocation.reference) {
                    guard scriptFile == nil, loadError == nil else { return }
                    loadScript()
                }
            } else {
                QingLongEmptyState(icon: "doc.text", title: "未识别脚本路径")
                    .padding(ESUI.Space.md)
                    .background(ESUI.appBackground.ignoresSafeArea())
            }
        }
    }

    private func loadScript() {
        Task {
            isLoading = true
            loadError = nil
            defer { isLoading = false }

            do {
                scriptFile = try await viewModel.loadScriptFile(for: cron)
            } catch {
                scriptFile = nil
                loadError = error.localizedDescription
            }
        }
    }

    private func formattedScriptContent(_ content: String) -> String {
        content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}

private struct QingLongScriptCodeView: View {
    let content: String

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 0) {
                    Text(verbatim: lineNumberText)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                        .multilineTextAlignment(.trailing)
                        .padding(.trailing, 12)
                        .padding(.vertical, 12)

                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 1)
                        .padding(.vertical, 10)

                    Text(verbatim: displayContent)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                .fill(ESUI.fill)
        )
    }

    private var displayContent: String {
        content.isEmpty ? "// 文件为空" : content
    }

    private var lineNumberText: String {
        let lineCount = max(displayContent.components(separatedBy: "\n").count, 1)
        return (1...lineCount).map(String.init).joined(separator: "\n")
    }
}

private struct QingLongDetailCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            content()
        }
        .esCard()
    }
}

private struct QingLongDetailField: View {
    let title: String
    let value: String
    var monospaced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            if monospaced {
                Text(value)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            } else {
                Text(value)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct QingLongDetailMetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                .fill(ESUI.fill)
        )
    }
}

private struct QingLongCronStateBadge: View {
    let cron: QingLongCron

    var body: some View {
        HStack(spacing: ESUI.Space.xs) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)

            Text(cron.statusText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, ESUI.Space.sm)
        .padding(.vertical, ESUI.Space.xs)
        .background(
            Capsule(style: .continuous)
                .fill(statusColor.opacity(0.12))
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

struct QingLongSharedEnvironmentsSheet: View {
    @ObservedObject var viewModel: QingLongViewModel
    let saveEnvironmentAction: (QingLongEnvironmentEditorContext, String, String, String) async -> Bool
    let toggleEnvironmentAction: (QingLongEnvironment) -> Void

    @State private var searchText = ""
    @State private var selectedEditorContext: QingLongEnvironmentEditorContext?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ESUI.Space.md) {
                    QingLongSharedEnvironmentHeaderCard(
                        totalCount: viewModel.sharedEnvironments.count,
                        filteredCount: filteredSharedEnvironments.count,
                        createAction: {
                            selectedEditorContext = viewModel.makeSharedEnvironmentEditor()
                        }
                    )

                    QingLongSearchField(text: $searchText, placeholder: "搜索共享变量")

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
                        LazyVStack(spacing: ESUI.Space.sm) {
                            ForEach(filteredSharedEnvironments) { environment in
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
                            }
                        }
                    }
                }
                .padding(ESUI.Space.md)
            }
            .background(ESUI.appBackground.ignoresSafeArea())
            .navigationTitle("共享变量")
            .navigationBarTitleDisplayMode(.inline)
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

private struct QingLongSharedEnvironmentHeaderCard: View {
    let totalCount: Int
    let filteredCount: Int
    let createAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: ESUI.Space.sm) {
            VStack(alignment: .leading, spacing: 5) {
                Text("共享变量")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button(action: createAction) {
                Label("新建", systemImage: "plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(ESUI.Space.md)
        .background(
            RoundedRectangle(cornerRadius: ESUI.cardCornerRadius, style: .continuous)
                .fill(ESUI.surface)
        )
    }

    private var summaryText: String {
        "\(filteredCount)/\(totalCount) 个变量"
    }
}

private struct QingLongSharedEnvironmentRow: View {
    let environment: QingLongEnvironment
    let isPending: Bool
    let editAction: () -> Void
    let toggleEnabledAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            HStack(alignment: .top, spacing: ESUI.Space.sm) {
                VStack(alignment: .leading, spacing: ESUI.Space.xs) {
                    HStack(spacing: ESUI.Space.xs) {
                        Text(environment.titleText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        QingLongTag(text: environment.isEnabled ? "启用" : "停用", color: environment.isEnabled ? .green : .orange)
                    }

                    if !environment.remarks.isEmpty {
                        Text(environment.remarks)
                            .font(.caption2)
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

            HStack(spacing: ESUI.Space.xs) {
                Image(systemName: environment.isEmptyValue ? "minus.circle" : "key.horizontal.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(environment.isEmptyValue ? Color.secondary : Color.blue)

                Text(environment.isEmptyValue ? "空值" : environment.maskedValue)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, ESUI.Space.sm)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                    .fill(ESUI.fill)
            )

            HStack(spacing: ESUI.Space.xs) {
                Button(action: toggleEnabledAction) {
                    Label(environment.isEnabled ? "禁用" : "启用", systemImage: environment.isEnabled ? "pause.circle" : "play.circle")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, ESUI.Space.sm)
                        .padding(.vertical, ESUI.Space.xs)
                }
                .buttonStyle(.glass)
                .tint(environment.isEnabled ? .orange : .green)
                .disabled(isPending)

                Button(action: editAction) {
                    Text("编辑")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, ESUI.Space.sm)
                        .padding(.vertical, ESUI.Space.xs)
                }
                .buttonStyle(.glass)
                .tint(.blue)

                Spacer(minLength: 0)
            }
        }
        .padding(ESUI.Space.md)
        .background(
            RoundedRectangle(cornerRadius: ESUI.cardCornerRadius, style: .continuous)
                .fill(ESUI.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ESUI.cardCornerRadius, style: .continuous)
                .stroke(statusColor.opacity(0.12), lineWidth: 1)
        )
    }

    private var statusColor: Color {
        environment.isEnabled ? .green : .orange
    }
}
