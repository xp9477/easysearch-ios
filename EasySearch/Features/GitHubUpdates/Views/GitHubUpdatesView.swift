import SwiftUI
import UIKit

public struct GitHubUpdatesView: View {
    @StateObject private var viewModel = GitHubUpdatesViewModel()
    @StateObject private var notificationManager = GitHubUpdatesNotificationManager.shared
    @Environment(\.openURL) private var openURL

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heroCard
                watchlistCard

                if shouldShowNotificationCard {
                    notificationCard
                }
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

    private var shouldShowNotificationCard: Bool {
        !notificationManager.notificationsEnabled || !viewModel.hasRepositories
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("GitHub Watch")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.72))

                    Text("项目更新提醒")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)

                    Text(heroDescriptionText)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.8))
                }

                Spacer(minLength: 12)

                statusChip(
                    title: notificationManager.notificationsEnabled ? "通知已开启" : "通知待开启",
                    color: notificationManager.notificationsEnabled ? heroAccentColor : .orange,
                    prominent: true
                )
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                heroMetric(title: "关注仓库", value: "\(viewModel.repositories.count)")
                heroMetric(title: "监控中", value: "\(viewModel.activeRepositoryCount)")
                heroMetric(title: "近 7 天活跃", value: "\(viewModel.recentlyUpdatedCount)")
                heroMetric(title: "最近检查", value: viewModel.latestCheckedAt.map(relativeDateText) ?? "尚未检查")
            }

            if let notice = viewModel.notice {
                noticeBanner(notice, onDarkBackground: true)
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
                            .tint(.white)
                    }
                }
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(heroAccentColor)
            .disabled(!viewModel.canRefreshRepositories)

            infoStrip(
                icon: "clock.arrow.circlepath",
                text: "后台刷新由 iOS 统一调度，应用会申请最早 4 小时后再次检查；下拉页面也可以手动刷新。",
                foreground: Color.white.opacity(0.82),
                background: Color.white.opacity(0.08)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.18, green: 0.20, blue: 0.24),
                            Color(red: 0.09, green: 0.10, blue: 0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var watchlistCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(
                eyebrow: "Watchlist",
                title: "仓库状态",
                description: viewModel.repositories.isEmpty
                    ? "先添加一个公开仓库地址，页面会按最近 push 时间自动排序。"
                    : "把新增入口放在列表顶部，下面直接看每个仓库当前状态。"
            )

            quickAddComposer

            if viewModel.repositories.isEmpty {
                emptyState(
                    icon: "shippingbox.circle",
                    title: "暂无关注仓库",
                    description: "支持 `https://github.com/owner/repo`、`git@github.com:owner/repo.git` 或 `owner/repo`。"
                )
            } else {
                watchlistOverview

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
                            relativeDateText: relativeDateText(_:),
                            absoluteDateText: absoluteDateText(_:)
                        )
                    }
                }
            }
        }
        .padding(24)
        .cardStyle()
    }

    private var quickAddComposer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("快速添加")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)

            TextField("输入 GitHub 仓库地址", text: $viewModel.draftRepositoryAddress)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit {
                    Task {
                        await viewModel.addRepository()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.systemBackground))
                )

            VStack(alignment: .leading, spacing: 10) {
                Text("公开仓库会在添加时先校验一遍，再加入提醒列表。")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                Button {
                    Task {
                        await viewModel.addRepository()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isAddingRepository {
                            ProgressView()
                        } else {
                            Image(systemName: "plus.circle.fill")
                        }
                        Text("加入提醒")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(heroAccentColor)
                .disabled(!viewModel.canAddRepository)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.tertiarySystemFill))
        )
    }

    private var watchlistOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    statusChip(
                        title: "\(viewModel.activeRepositoryCount) 个监控中",
                        color: heroAccentColor
                    )


                    if viewModel.recentlyUpdatedCount > 0 {
                        statusChip(
                            title: "\(viewModel.recentlyUpdatedCount) 个近 7 天活跃",
                            color: .orange
                        )
                    }

                    if viewModel.archivedRepositoryCount > 0 {
                        statusChip(
                            title: "\(viewModel.archivedRepositoryCount) 个已归档或停用",
                            color: .secondary
                        )
                    }
                }
            }

            infoStrip(
                icon: "arrow.up.right.and.arrow.down.left",
                text: "仓库卡片会优先突出最近活跃、归档和停用状态，减少无意义的冗余提示。",
                foreground: .secondary,
                background: Color(.tertiarySystemFill)
            )
        }
    }

    private var notificationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                eyebrow: "Notifications",
                title: "通知与后台刷新",
                description: "通知只在后台检查到新 push 时触发。未授权时，这里保留显式引导；正常开启后不再单独占满一张大卡。"
            )

            HStack(spacing: 12) {
                Image(systemName: notificationManager.notificationsEnabled ? "bell.badge.fill" : "bell.slash")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(notificationManager.notificationsEnabled ? heroAccentColor : .secondary)

                Text(notificationManager.statusText)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()
            }

            switch notificationManager.authorizationStatus {
            case .notDetermined:
                Button {
                    Task {
                        await notificationManager.requestAuthorization()
                    }
                } label: {
                    Label("开启通知", systemImage: "bell.badge")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(heroAccentColor)

            case .denied:
                Button {
                    guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(settingsURL)
                } label: {
                    Label("前往系统设置", systemImage: "gearshape")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)

            case .authorized, .provisional, .ephemeral:
                Button {
                    Task {
                        await notificationManager.refreshAuthorizationStatus()
                    }
                } label: {
                    Label("刷新通知状态", systemImage: "arrow.clockwise")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
                .tint(heroAccentColor)

            @unknown default:
                EmptyView()
            }
        }
        .padding(24)
        .cardStyle()
    }

    private var heroDescriptionText: String {
        if viewModel.hasRepositories {
            return "最近 push、最近检查和通知状态会汇总到这里，列表直接展示每个仓库当前监控状态。"
        }

        return "先加一个公开仓库，后面后台有新 push 时就会发本地通知；打开 App 时也会顺手补查一次。"
    }

    private var heroAccentColor: Color {
        Color(red: 0.18, green: 0.73, blue: 0.53)
    }

    private func heroMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.66))

            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }

    private func sectionHeader(eyebrow: String, title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.primary)

            Text(description)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func statusChip(title: String, color: Color, prominent: Bool = false) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(prominent ? Color.white : color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(prominent ? color.opacity(0.96) : color.opacity(0.12))
            )
    }

    private func noticeBanner(_ notice: GitHubUpdatesNotice, onDarkBackground: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: notice.iconName)
                .font(.system(size: 14, weight: .bold))

            Text(notice.message)
                .font(.system(size: 13, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .foregroundStyle(onDarkBackground ? Color.white : notice.color)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(onDarkBackground ? Color.white.opacity(0.08) : notice.color.opacity(0.12))
        )
    }

    private func infoStrip(icon: String, text: String, foreground: Color, background: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .padding(.top, 1)

            Text(text)
                .font(.system(size: 13, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(background)
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

private struct GitHubWatchedRepositoryRow: View {
    let repository: GitHubWatchedRepository
    let isDeleting: Bool
    let canDelete: Bool
    let openAction: () -> Void
    let deleteAction: () -> Void
    let relativeDateText: (Date) -> String
    let absoluteDateText: (Date) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(repository.fullName)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 8)

                        statusChip(
                            title: status.title,
                            color: status.color
                        )
                    }

                    if !repository.repositoryDescription.isEmpty {
                        Text(repository.repositoryDescription)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack(spacing: 8) {
                repositoryPill("默认分支 \(repository.defaultBranch)")

                if repository.isArchived {
                    repositoryPill("已归档")
                }

                if repository.isDisabled {
                    repositoryPill("已停用")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                detailRow(
                    label: "最近 push",
                    value: repository.lastKnownPushedAt.map(relativeDateText) ?? "尚未拿到最近 push 时间"
                )
                detailRow(
                    label: "上次检查",
                    value: repository.lastCheckedAt.map(absoluteDateText) ?? "等待首次检查"
                )
            }

            HStack(spacing: 10) {
                Button(action: openAction) {
                    Label("打开仓库", systemImage: "arrow.up.right.square")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .tint(Color(red: 0.18, green: 0.73, blue: 0.53))

                Button(role: .destructive, action: deleteAction) {
                    HStack(spacing: 8) {
                        if isDeleting {
                            ProgressView()
                        } else {
                            Image(systemName: "trash")
                        }
                        Text("移除")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .disabled(!canDelete)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(status.color.opacity(0.18), lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(status.color.opacity(0.85))
                .frame(width: 4)
                .padding(.vertical, 12)
        }
    }

    private var status: RepositoryStatus {
        if repository.isDisabled {
            return RepositoryStatus(title: "已停用", color: .secondary)
        }

        if repository.isArchived {
            return RepositoryStatus(title: "已归档", color: .secondary)
        }

        if let pushedAt = repository.lastKnownPushedAt {
            let elapsed = Date().timeIntervalSince(pushedAt)
            if elapsed <= 3 * 24 * 60 * 60 {
                return RepositoryStatus(title: "最近有更新", color: .orange)
            }
        }

        if repository.lastCheckedAt == nil {
            return RepositoryStatus(title: "等待检查", color: .secondary)
        }

        return RepositoryStatus(
            title: "监控中",
            color: Color(red: 0.18, green: 0.73, blue: 0.53)
        )
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private func repositoryPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(.tertiarySystemFill))
            )
    }

    private func statusChip(title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.12))
            )
    }
}

private struct RepositoryStatus {
    let title: String
    let color: Color
}

private extension View {
    func cardStyle() -> some View {
        background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private extension GitHubUpdatesNotice {
    var color: Color {
        switch tone {
        case .neutral:
            return .secondary
        case .success:
            return Color(red: 0.18, green: 0.73, blue: 0.53)
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
