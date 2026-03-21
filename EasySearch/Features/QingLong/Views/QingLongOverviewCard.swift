import SwiftUI

struct QingLongMetric: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let value: String
}

struct QingLongOverviewCard: View {
    @ObservedObject var viewModel: QingLongViewModel
    let metrics: [QingLongMetric]
    let refreshAction: () -> Void
    let openPanelAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("青龙管理")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.primary)

                    Text(summaryText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if let connectionStateText {
                    Text(connectionStateText)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.green.opacity(0.12))
                        )
                }
            }

            HStack(spacing: 8) {
                ForEach(metrics) { metric in
                    HStack(spacing: 6) {
                        Image(systemName: metric.symbol)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.green)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(metric.value)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.primary)

                            Text(metric.title)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.5))
                    )
                }
            }

            if let errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.orange.opacity(0.10))
                )
            }

            if viewModel.profile != nil {
                HStack(spacing: 10) {
                    Button(action: refreshAction) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("刷新")
                            if viewModel.isRefreshing {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(viewModel.isRefreshing || viewModel.isConnecting)

                    if let openPanelAction {
                        Button(action: openPanelAction) {
                            Label("面板", systemImage: "arrow.up.right.square")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                        .tint(.green)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
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
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var summaryText: String {
        if let profile = viewModel.profile {
            if let lastRefreshedAt = viewModel.lastRefreshedAt {
                return "\(profile.hostLabel) · \(relativeDateText(lastRefreshedAt))"
            }
            return profile.hostLabel
        }

        return "未连接"
    }

    private var connectionStateText: String? {
        guard viewModel.profile != nil else { return nil }
        return "已连接"
    }

    private var errorMessage: String? {
        guard let statusState = viewModel.statusState, statusState.tone == .error else {
            return nil
        }
        return statusState.message
    }

    private func relativeDateText(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
