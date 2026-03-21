import SwiftUI

public struct GitHubUpdatesView: View {
    @StateObject private var viewModel = GitHubUpdatesViewModel()
    @Environment(\.openURL) private var openURL

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summaryCard
                repositoriesCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("GitHub 更新")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.refreshAll()
        }
        .task {
            await viewModel.prepare()
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("GitHub 更新提醒")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.primary)

            VStack(spacing: 12) {
                summaryRow(title: "已关注", value: "\(viewModel.repositories.count) 个仓库")
                summaryRow(title: "上次检查", value: viewModel.latestCheckedAt.map(relativeDateText) ?? "尚未检查")
            }

            if let notice = viewModel.notice {
                noticeBanner(notice)
            }

            Button {
                Task {
                    await viewModel.refreshAll()
                }
            } label: {
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
            .tint(.indigo)
            .disabled(!viewModel.canRefreshRepositories)
        }
        .padding(24)
        .cardStyle()
    }

    private var repositoriesCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("提醒列表")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)

            if viewModel.repositories.isEmpty {
                emptyState(
                    icon: "shippingbox.circle",
                    title: "暂无关注仓库",
                    description: "在设置里添加仓库后，会显示在这里。"
                )
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.repositories) { repository in
                        GitHubWatchedRepositoryRow(
                            repository: repository,
                            isDeleting: viewModel.isDeletingRepository(repository),
                            canDelete: viewModel.canDeleteRepository(repository),
                            openAction: {
                                openURL(repository.htmlURL)
                            },
                            deleteAction: {
                                Task {
                                    await viewModel.deleteRepository(repository)
                                }
                            },
                            relativeDateText: relativeDateText(_:)
                        )
                    }
                }
            }
        }
        .padding(24)
        .cardStyle()
    }

    private func summaryRow(title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func noticeBanner(_ notice: GitHubUpdatesNotice) -> some View {
        HStack(spacing: 10) {
            Image(systemName: notice.iconName)
                .font(.system(size: 14, weight: .bold))

            Text(notice.message)
                .font(.system(size: 13, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .foregroundStyle(notice.color)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(notice.color.opacity(0.12))
        )
    }

    private func emptyState(icon: String, title: String, description: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)

            Text(description)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.tertiarySystemFill))
        )
    }

    private func relativeDateText(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

}

private struct GitHubWatchedRepositoryRow: View {
    let repository: GitHubWatchedRepository
    let isDeleting: Bool
    let canDelete: Bool
    let openAction: () -> Void
    let deleteAction: () -> Void
    let relativeDateText: (Date) -> String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(repository.fullName)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if !repository.repositoryDescription.isEmpty {
                    Text(repository.repositoryDescription)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(pushText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            accessory
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .contentShape(Rectangle())
        .contextMenu {
            Button(action: openAction) {
                Label("打开仓库", systemImage: "arrow.up.right.square")
            }

            Button(role: .destructive, action: deleteAction) {
                Label("移除", systemImage: "trash")
            }
            .disabled(!canDelete)
        }
    }

    @ViewBuilder
    private var accessory: some View {
        if isDeleting {
            ProgressView()
        } else if let statusText {
            Text(statusText)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(statusColor.opacity(0.12))
                )
        }
    }

    private var pushText: String {
        if let pushedAt = repository.lastKnownPushedAt {
            return "最近 push \(relativeDateText(pushedAt))"
        }

        return "尚未拿到最近 push 时间"
    }

    private var statusText: String? {
        if repository.isArchived || repository.isDisabled {
            return "已归档"
        }

        if let pushedAt = repository.lastKnownPushedAt,
           Date().timeIntervalSince(pushedAt) <= 3 * 24 * 60 * 60 {
            return "最近有更新"
        }

        return nil
    }

    private var statusColor: Color {
        switch statusText {
        case "最近有更新":
            return .orange
        case "已归档":
            return .secondary
        default:
            return .indigo
        }
    }
}

private extension GitHubUpdatesNotice {
    var color: Color {
        switch tone {
        case .neutral:
            return .secondary
        case .success:
            return .green
        case .caution:
            return .orange
        }
    }

    var iconName: String {
        switch tone {
        case .neutral:
            return "info.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .caution:
            return "exclamationmark.triangle.fill"
        }
    }
}

#Preview {
    NavigationStack {
        GitHubUpdatesView()
    }
}
