import SwiftUI

public struct GitHubUpdatesView: View {
    @StateObject private var viewModel = GitHubUpdatesViewModel()
    @Environment(\.openURL) private var openURL

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ESUI.sectionSpacing) {
                summaryCard
                repositoriesCard
            }
            .padding(.horizontal, ESUI.screenHorizontalPadding)
            .padding(.top, ESUI.Space.md)
            .padding(.bottom, ESUI.Space.xxl)
        }
        .esScreenBackground()
        .navigationTitle("GitHub 更新")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.refreshAll()
        }
        .task {
            await viewModel.prepare()
        }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.md) {
            ESSectionHeader(
                title: "更新概览",
                subtitle: "关注仓库的 push 提醒"
            )

            VStack(spacing: ESUI.Space.sm) {
                ESValueRow(title: "已关注", value: "\(viewModel.repositories.count) 个仓库")
                ESValueRow(
                    title: "上次检查",
                    value: viewModel.latestCheckedAt.map(relativeDateText) ?? "尚未检查"
                )
            }

            if let notice = viewModel.notice {
                ESStatusBanner(
                    title: notice.message,
                    systemImage: notice.iconName,
                    tone: notice.tone.badgeTone
                )
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
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, ESUI.Space.xs)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.canRefreshRepositories)
        }
        .esCard()
    }

    // MARK: - Repositories

    private var repositoriesCard: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.md) {
            ESSectionHeader(
                title: "提醒列表",
                trailing: viewModel.repositories.isEmpty ? nil : "\(viewModel.repositories.count)"
            )

            if viewModel.repositories.isEmpty {
                ESEmptyState(
                    title: "暂无关注仓库",
                    message: "在设置里添加仓库后，会显示在这里。",
                    systemImage: "shippingbox"
                )
            } else {
                LazyVStack(spacing: ESUI.Space.xs) {
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
        .esCard()
    }

    private func relativeDateText(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Repository Row

private struct GitHubWatchedRepositoryRow: View {
    let repository: GitHubWatchedRepository
    let isDeleting: Bool
    let canDelete: Bool
    let openAction: () -> Void
    let deleteAction: () -> Void
    let relativeDateText: (Date) -> String

    var body: some View {
        HStack(alignment: .top, spacing: ESUI.Space.sm) {
            ESFeatureIcon(systemName: "shippingbox.fill", color: .indigo, size: 36)

            VStack(alignment: .leading, spacing: ESUI.Space.xxs) {
                Text(repository.fullName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if !repository.repositoryDescription.isEmpty {
                    Text(repository.repositoryDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(pushText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: ESUI.Space.xs)

            accessory
        }
        .padding(ESUI.Space.md)
        .background(
            RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                .fill(ESUI.fill)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isDeleting else { return }
            openAction()
        }
        .contextMenu {
            Button(action: openAction) {
                Label("打开仓库", systemImage: "arrow.up.right.square")
            }

            Button(role: .destructive, action: deleteAction) {
                Label("移除", systemImage: "trash")
            }
            .disabled(!canDelete)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("轻点打开仓库")
    }

    @ViewBuilder
    private var accessory: some View {
        if isDeleting {
            ProgressView()
        } else if let statusText, let tone = statusTone {
            ESStatusBadge(text: statusText, tone: tone)
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

    private var statusTone: ESStatusBadge.Tone? {
        switch statusText {
        case "最近有更新":
            return .warning
        case "已归档":
            return .neutral
        default:
            return nil
        }
    }
}

// MARK: - Notice Mapping

private extension GitHubUpdatesNotice {
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

private extension GitHubUpdatesNoticeTone {
    var badgeTone: ESStatusBadge.Tone {
        switch self {
        case .neutral:
            return .neutral
        case .success:
            return .success
        case .caution:
            return .warning
        }
    }
}

#Preview {
    NavigationStack {
        GitHubUpdatesView()
    }
}
