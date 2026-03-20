import SwiftUI

struct QingLongMetric: Identifiable {
    let id: String
    let title: String
    let value: String
}

struct QingLongOverviewCard: View {
    @ObservedObject var viewModel: QingLongViewModel
    let metrics: [QingLongMetric]
    let startConnectionAction: () -> Void
    let refreshAction: () -> Void
    let openPanelAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("QingLong")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(viewModel.profile?.displayName ?? "连接你的面板")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.primary)

                Text(
                    viewModel.profile == nil
                        ? "先完成 Open API 接入，后面就按“环境变量 / 定时任务”两个工作区管理，不再把接入表单和运维列表堆在一起。"
                        : "已切到管理视角。连接信息收敛成摘要卡，日常操作集中在下面的工作区里。"
                )
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 12)], spacing: 12) {
                ForEach(metrics) { metric in
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
            }

            if let statusState = viewModel.statusState {
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

            HStack(spacing: 12) {
                if viewModel.profile == nil {
                    Button(action: startConnectionAction) {
                        Label("开始连接", systemImage: "link.badge.plus")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                } else {
                    Button(action: refreshAction) {
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

                    if let openPanelAction {
                        Button(action: openPanelAction) {
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
