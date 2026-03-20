import SwiftUI
import UIKit

struct QingLongConnectionStatusCard: View {
    @ObservedObject var viewModel: QingLongViewModel
    @Binding var isEditingConnection: Bool
    let absoluteDateText: (Date) -> String
    let runDiagnosticsAction: () -> Void
    let disconnectAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let profile = viewModel.profile {
                QingLongSectionHeader(
                    eyebrow: "Connection",
                    title: "当前连接",
                    description: "连接配置已经折叠成摘要，日常只保留高频动作；需要改地址或密钥时再展开编辑。"
                )

                VStack(spacing: 12) {
                    QingLongConnectionInfoRow(icon: "server.rack", title: "面板地址", value: profile.baseURL.absoluteString)
                    QingLongConnectionInfoRow(icon: "network", title: "主机标识", value: profile.hostLabel)
                    QingLongConnectionInfoRow(icon: "clock", title: "最近连接", value: profile.lastConnectedAt.map(absoluteDateText) ?? "暂无记录")
                    QingLongConnectionInfoRow(icon: "tray.and.arrow.down", title: "本地保存", value: absoluteDateText(profile.savedAt))
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

                    Button(action: runDiagnosticsAction) {
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

                Button(role: .destructive, action: disconnectAction) {
                    Label("断开连接", systemImage: "trash")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
            } else {
                QingLongSectionHeader(
                    eyebrow: "Onboarding",
                    title: "接入步骤",
                    description: "第一次配置只关注三件事：地址正确、凭据正确、面板权限完整。接入成功后，下面的工作区会自动切到管理模式。"
                )

                VStack(spacing: 12) {
                    QingLongOnboardingStep(number: "01", title: "面板地址", description: "支持域名、IP 和端口，建议公网场景使用 HTTPS。")
                    QingLongOnboardingStep(number: "02", title: "Open API 凭据", description: "在“系统设置 -> 应用设置”里创建应用，拿到 client_id 和 client_secret。")
                    QingLongOnboardingStep(number: "03", title: "最小验证", description: "先跑一次连接诊断，确认 token、envs、crons 接口都能通。")
                }
            }
        }
        .padding(24)
        .cardStyle()
    }
}

struct QingLongConnectionEditorCard: View {
    @ObservedObject var viewModel: QingLongViewModel
    @Binding var isEditingConnection: Bool
    let connectAction: () -> Void
    let runDiagnosticsAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            QingLongSectionHeader(
                eyebrow: "Configuration",
                title: viewModel.profile == nil ? "连接配置" : "编辑连接",
                description: "表单只在接入时或主动编辑时展开。保存成功后会自动折叠，避免长期占据页面主区域。"
            )

            VStack(alignment: .leading, spacing: 8) {
                QingLongFieldLabel("面板地址")
                QingLongEditorTextField("例如 https://ql.example.com:5700", text: $viewModel.draftBaseURL, keyboardType: .URL)
            }

            VStack(alignment: .leading, spacing: 8) {
                QingLongFieldLabel("client_id")
                QingLongEditorTextField("Open API client_id", text: $viewModel.draftClientID, keyboardType: .asciiCapable)
            }

            VStack(alignment: .leading, spacing: 8) {
                QingLongFieldLabel("client_secret")
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
                Button(action: connectAction) {
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

            Button(action: runDiagnosticsAction) {
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
}

private struct QingLongConnectionInfoRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
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
}

private struct QingLongOnboardingStep: View {
    let number: String
    let title: String
    let description: String

    var body: some View {
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
}

private struct QingLongFieldLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary)
    }
}

private struct QingLongEditorTextField: View {
    let placeholder: String
    @Binding var text: String
    let keyboardType: UIKeyboardType

    init(_ placeholder: String, text: Binding<String>, keyboardType: UIKeyboardType) {
        self.placeholder = placeholder
        self._text = text
        self.keyboardType = keyboardType
    }

    var body: some View {
        TextField(placeholder, text: $text)
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
}
