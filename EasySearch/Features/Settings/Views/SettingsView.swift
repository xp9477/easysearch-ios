import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var navigationState: AppNavigationState
    @EnvironmentObject private var statusCenter: FeatureStatusCenter
    @ObservedObject private var cloudViewModel = CloudSyncViewModel.shared
    @ObservedObject private var webDAVSettingsStore = WebDAVSettingsStore.shared
    @ObservedObject private var appUpdateService = AppUpdateService.shared
    @State private var path = NavigationPath()

    private var appVersionText: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (shortVersion, buildVersion) {
        case let (shortVersion?, buildVersion?) where !shortVersion.isEmpty && !buildVersion.isEmpty:
            return "\(shortVersion) (\(buildVersion))"
        case let (shortVersion?, _) where !shortVersion.isEmpty:
            return shortVersion
        case let (_, buildVersion?) where !buildVersion.isEmpty:
            return buildVersion
        default:
            return "未知"
        }
    }

    private var cloudSubtitle: String {
        if !cloudViewModel.isCloudConfigured {
            return "仅本地保存"
        }
        if cloudViewModel.isCloudIdentityMismatch {
            return "账号待确认"
        }
        if cloudViewModel.isCloudAuthenticated {
            return cloudViewModel.cloudUserEmail ?? "已登录"
        }
        return "未登录"
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section("云端与账户") {
                    NavigationLink(value: SettingsRoute.cloudSync) {
                        settingsModuleRow(
                            title: "云端同步",
                            subtitle: cloudSubtitle,
                            icon: "icloud.fill",
                            iconColor: .blue,
                            status: statusCenter.cloudSummary
                        )
                    }
                }

                Section("模块配置与权限") {
                    NavigationLink(value: SettingsRoute.utTracker) {
                        settingsModuleRow(
                            title: "UT 记录",
                            subtitle: "目标与通知提醒",
                            icon: "chart.bar.doc.horizontal",
                            iconColor: .indigo,
                            status: statusCenter.summary(for: "uttracker")
                        )
                    }

                    NavigationLink(value: SettingsRoute.expenseAssistant) {
                        settingsModuleRow(
                            title: "报销助手",
                            subtitle: "单据与逾期提醒",
                            icon: "receipt",
                            iconColor: .orange,
                            status: statusCenter.summary(for: "expense-assistant")
                        )
                    }

                    NavigationLink(value: SettingsRoute.qingLong) {
                        settingsModuleRow(
                            title: "青龙管理",
                            subtitle: "面板连接与诊断",
                            icon: "server.rack",
                            iconColor: .green,
                            status: statusCenter.summary(for: "qinglong-management")
                        )
                    }

                    NavigationLink(value: SettingsRoute.webDAV) {
                        settingsModuleRow(
                            title: "WebDAV 文件",
                            subtitle: "存储位置与凭证",
                            icon: "externaldrive.fill",
                            iconColor: .blue,
                            status: statusCenter.summary(for: "webdav")
                        )
                    }
                }

                Section("关于与更新") {
                    LabeledContent("版本", value: appVersionText)

                    Button {
                        Task {
                            await appUpdateService.checkForUpdates()
                            announceUpdateStatus()
                        }
                    } label: {
                        HStack {
                            Text(appUpdateService.isChecking ? "正在检查…" : "检测更新")
                            Spacer()
                            if appUpdateService.isChecking {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(appUpdateService.isChecking || appUpdateService.isDownloading)

                    if let lastResult = appUpdateService.lastResult {
                        updateResultSection(lastResult)
                    }

                    if !updateResultIsUnavailable,
                       let message = appUpdateService.statusMessage?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                       !message.isEmpty {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: SettingsRoute.self) { route in
                settingsDestination(for: route)
            }
            .task {
                await cloudViewModel.prepareIfNeeded()
                await UTNotificationManager.shared.configure()
                await ExpenseAssistantNotificationManager.shared.configure()
                await statusCenter.refresh()
                handlePendingRouteIfNeeded()
            }
            .onChange(of: navigationState.pendingSettingsRoute) {
                handlePendingRouteIfNeeded()
            }
            .onChange(of: navigationState.selectedTab) { _, tab in
                if tab == .settings {
                    Task { await statusCenter.refresh() }
                    handlePendingRouteIfNeeded()
                }
            }
        }
    }

    private func settingsModuleRow(
        title: String,
        subtitle: String,
        icon: String,
        iconColor: Color,
        status: FeatureStatusSummary
    ) -> some View {
        HStack(spacing: ESUI.Space.sm) {
            ESFeatureIcon(systemName: icon, color: iconColor, size: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: ESUI.Space.xs)

            ESStatusBadge(text: status.text, tone: .from(kind: status.kind))
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func updateResultSection(_ result: AppUpdateCheckResult) -> some View {
        switch result {
        case let .updateAvailable(_, remote):
            VStack(alignment: .leading, spacing: 8) {
                Text("新版本 \(remote.displayVersion)")
                    .font(.subheadline.weight(.semibold))

                updateNotesBlock(remote.notes)

                Button {
                    Task {
                        if let fileURL = await appUpdateService.downloadLatestIPA() {
                            appUpdateService.presentShareSheet(for: fileURL)
                        } else {
                            announceUpdateStatus()
                        }
                    }
                } label: {
                    HStack {
                        Text(appUpdateService.isDownloading ? "下载中…" : "下载并分享到签名工具")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        if appUpdateService.isDownloading {
                            ProgressView(value: appUpdateService.downloadProgress)
                                .frame(width: 80)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .disabled(appUpdateService.isDownloading)
            }

        case let .upToDate(_, remote):
            if let notes = remote.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("当前版本说明")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(notes)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

        case let .unavailable(message):
            Label {
                Text("检查失败：\(message)")
                    .font(.footnote)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func updateNotesBlock(_ notes: String?) -> some View {
        if let notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("更新内容")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(notes)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Navigation

    @ViewBuilder
    private func settingsDestination(for route: SettingsRoute) -> some View {
        switch route {
        case .cloudSync:
            CloudSyncSettingsDetailView()
        case .utTracker:
            UTTrackerSettingsDetailView()
        case .expenseAssistant:
            ExpenseAssistantSettingsDetailView()
        case .qingLong:
            QingLongSettingsDetailView()
        case .webDAV:
            WebDAVSettingsView(store: webDAVSettingsStore)
        case .hiddenSpace:
            HiddenSpaceSettingsHubView()
        }
    }

    private func handlePendingRouteIfNeeded() {
        guard let route = navigationState.pendingSettingsRoute else { return }
        path.append(route)
        navigationState.pendingSettingsRoute = nil
    }

    private var updateResultIsUnavailable: Bool {
        guard let result = appUpdateService.lastResult,
              case .unavailable = result else { return false }
        return true
    }

    private func announceUpdateStatus() {
        guard let message = appUpdateService.statusMessage?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty else { return }
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppNavigationState())
        .environmentObject(FeatureStatusCenter.shared)
}
