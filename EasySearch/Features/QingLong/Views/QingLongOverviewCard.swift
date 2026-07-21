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
        VStack(alignment: .leading, spacing: ESUI.Space.md) {
            HStack(alignment: .top, spacing: ESUI.Space.sm) {
                ESFeatureIcon(systemName: "terminal", color: .green)

                VStack(alignment: .leading, spacing: ESUI.Space.xxs) {
                    Text("青龙管理")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(summaryText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                if let connectionStateText {
                    ESStatusBadge(text: connectionStateText, tone: .success)
                } else {
                    ESStatusBadge(text: "未连接", tone: .warning)
                }
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: ESUI.Space.xs),
                    GridItem(.flexible(), spacing: ESUI.Space.xs)
                ],
                spacing: ESUI.Space.xs
            ) {
                ForEach(metrics) { metric in
                    VStack(alignment: .leading, spacing: ESUI.Space.xxs) {
                        HStack(spacing: 4) {
                            Image(systemName: metric.symbol)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.accentColor)
                            Text(metric.value)
                                .font(.headline)
                                .foregroundStyle(.primary)
                        }
                        Text(metric.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, ESUI.Space.sm)
                    .padding(.vertical, ESUI.Space.sm)
                    .background(
                        RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                            .fill(ESUI.fill)
                    )
                }
            }

            if let errorMessage {
                ESStatusBanner(
                    title: errorMessage,
                    systemImage: "exclamationmark.triangle.fill",
                    tone: .warning
                )
            }

            if viewModel.profile != nil {
                HStack(spacing: ESUI.Space.sm) {
                    Button(action: refreshAction) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("刷新")
                            if viewModel.isRefreshing {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, ESUI.Space.xs)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isRefreshing || viewModel.isConnecting)

                    if let openPanelAction {
                        Button(action: openPanelAction) {
                            Label("面板", systemImage: "arrow.up.right.square")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, ESUI.Space.xs)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .esCard()
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
