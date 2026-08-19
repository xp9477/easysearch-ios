import SwiftUI

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
            isEditingConnection = viewModel.profile == nil || viewModel.requiresCredentialReconnect
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

struct QingLongDiagnosticReportView: View {
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
