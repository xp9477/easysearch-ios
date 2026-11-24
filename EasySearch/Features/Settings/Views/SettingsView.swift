import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var navigationState: AppNavigationState
    @EnvironmentObject private var statusCenter: FeatureStatusCenter
    @ObservedObject private var cloudViewModel = CloudSyncViewModel.shared
    @ObservedObject private var webDAVSettingsStore = WebDAVSettingsStore.shared
    @ObservedObject private var appUpdateService = AppUpdateService.shared
    @State private var path = NavigationPath()

    private var cloudStatus: String {
        if cloudViewModel.isPreparingCloud { return "正在检查…" }
        if cloudViewModel.isCloudIdentityMismatch { return "已暂停同步" }
        if !cloudViewModel.isCloudConfigured { return "仅本地" }
        return cloudViewModel.isCloudAuthenticated ? "已登录" : "未登录"
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section("账户") {
                    NavigationLink(value: SettingsRoute.cloudSync) {
                        SettingsNavigationRow(
                            title: "云端同步", icon: "icloud.fill", color: .blue,
                            status: cloudStatus, needsAttention: cloudViewModel.isCloudIdentityMismatch
                        )
                    }
                }

                Section("模块") {
                    moduleLink("UT 记录", icon: "chart.bar.doc.horizontal", id: "uttracker", route: .utTracker, permissionsOnly: true)
                    moduleLink("报销助手", icon: "receipt", id: "expense-assistant", route: .expenseAssistant, permissionsOnly: true)
                    moduleLink("青龙管理", icon: "server.rack", id: "qinglong-management", route: .qingLong)
                    moduleLink("外置存储", icon: "externaldrive.fill", id: "webdav", route: .webDAV)
                }

                Section("关于与更新") {
                    LabeledContent("版本", value: appUpdateService.currentVersionLabel)
                    NavigationLink(value: SettingsRoute.softwareUpdate) {
                        SettingsNavigationRow(title: "检测更新", icon: "arrow.clockwise", color: .blue)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: SettingsRoute.self, destination: settingsDestination)
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

    private func moduleLink(_ title: String, icon: String, id: String, route: SettingsRoute, permissionsOnly: Bool = false) -> some View {
        let summary = statusCenter.summary(for: id)
        let status: String? = switch summary.kind {
        case .needsAuthorization: summary.text
        case .needsConfiguration, .processing, .offlineOrUnavailable, .recoverableFailure:
            permissionsOnly ? nil : summary.text
        default: nil
        }

        return NavigationLink(value: route) {
            SettingsNavigationRow(
                title: title, icon: icon, color: ESUI.moduleColor(for: id), status: status,
                needsAttention: summary.kind == .needsAuthorization || summary.kind == .recoverableFailure
            )
        }
    }

    @ViewBuilder
    private func settingsDestination(for route: SettingsRoute) -> some View {
        switch route {
        case .cloudSync: CloudSyncSettingsDetailView()
        case .utTracker: UTTrackerSettingsDetailView()
        case .expenseAssistant: ExpenseAssistantSettingsDetailView()
        case .qingLong: QingLongSettingsDetailView()
        case .webDAV: WebDAVSettingsView(store: webDAVSettingsStore)
        case .softwareUpdate: SoftwareUpdateView(service: appUpdateService)
        case .hiddenSpace: HiddenSpaceSettingsHubView()
        }
    }

    private func handlePendingRouteIfNeeded() {
        guard let route = navigationState.pendingSettingsRoute else { return }
        path.append(route)
        navigationState.pendingSettingsRoute = nil
    }
}

private struct SettingsNavigationRow: View {
    let title: String
    let icon: String
    let color: Color
    var status: String? = nil
    var needsAttention = false

    var body: some View {
        HStack(spacing: ESUI.Space.sm) {
            ESFeatureIcon(systemName: icon, color: color, size: 30)
                .accessibilityHidden(true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: ESUI.Space.sm) {
                    Text(title).fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    if let status {
                        statusLabel(status).fixedSize(horizontal: true, vertical: false)
                    }
                }

                VStack(alignment: .leading, spacing: ESUI.Space.xs) {
                    Text(title)
                    if let status { statusLabel(status) }
                }
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    private func statusLabel(_ status: String) -> some View {
        Text(status)
            .font(.subheadline)
            .foregroundStyle(needsAttention ? Color.primary : Color.secondary)
    }
}

private struct SoftwareUpdateView: View {
    @ObservedObject var service: AppUpdateService
    @State private var downloadFailure: String?

    var body: some View {
        List {
            if service.isChecking {
                ProgressView("正在检查更新…")
            } else if let result = service.lastResult {
                resultSections(result)
            } else {
                LabeledContent("当前版本", value: service.currentVersionLabel)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("软件更新")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !service.isDownloading else { return }
            await checkForUpdates()
        }
    }

    @ViewBuilder
    private func resultSections(_ result: AppUpdateCheckResult) -> some View {
        switch result {
        case let .updateAvailable(current, remote):
            Section {
                versionSummary(
                    "有新版本",
                    version: "EasySearch \(remote.versionLabel)",
                    detail: remote.versionLabel == service.currentVersionLabel
                        ? "构建 \(remote.build)"
                        : "当前版本 \(service.currentVersionLabel)"
                )
            }

            Section {
                Button(action: downloadIPA) {
                    VStack(spacing: ESUI.Space.sm) {
                        Text(service.isDownloading ? "正在下载 IPA…" : "下载并分享 IPA")
                            .fontWeight(.semibold)
                        if service.isDownloading {
                            ProgressView(value: service.downloadProgress)
                                .tint(.white)
                                .accessibilityLabel("下载进度")
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(service.isDownloading)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                if let downloadFailure {
                    Label(downloadFailure, systemImage: "exclamationmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
            } footer: {
                Text("这是未签名 IPA，安装前需要签名。")
            }

            versionDetails(remote, current: current)

        case let .upToDate(current, remote):
            Section {
                versionSummary("已是最新版本", version: "EasySearch \(service.currentVersionLabel)")
            }
            versionDetails(remote, current: current, showRemoteBuild: false)

        case let .unavailable(message):
            Section {
                Label("暂时无法检查更新", systemImage: "exclamationmark.circle")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Button("重新检查") { Task { await checkForUpdates() } }
                DisclosureGroup("错误详情") {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func versionSummary(_ status: String, version: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            Text(status).font(.subheadline.weight(.semibold)).foregroundStyle(Color.accentColor)
            Text(version).font(.title2.bold()).accessibilityAddTraits(.isHeader)
            if let detail { Text(detail).font(.subheadline).foregroundStyle(.secondary) }
        }
        .padding(.vertical, ESUI.Space.sm)
    }

    private func versionDetails(_ remote: AppUpdateManifest, current: String, showRemoteBuild: Bool = true) -> some View {
        Section {
            if (showRemoteBuild || remote.build == service.currentBuild),
               let notes = remote.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                DisclosureGroup("更新内容") {
                    Text(notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, ESUI.Space.xs)
                        .textSelection(.enabled)
                }
                .id(remote.build)
            }

            DisclosureGroup("构建信息") {
                LabeledContent("当前版本", value: current)
                if showRemoteBuild { LabeledContent("可用更新", value: remote.displayVersion) }
            }
        }
    }

    private func checkForUpdates() async {
        downloadFailure = nil
        await service.checkForUpdates()
        guard !Task.isCancelled else { return }
        UIAccessibility.post(notification: .announcement, argument: service.statusMessage)
    }

    private func downloadIPA() {
        downloadFailure = nil
        Task {
            if let fileURL = await service.downloadLatestIPA(), service.presentShareSheet(for: fileURL) { return }
            downloadFailure = service.statusMessage ?? "无法下载，请重试。"
            UIAccessibility.post(notification: .announcement, argument: downloadFailure)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppNavigationState())
        .environmentObject(FeatureStatusCenter.shared)
}
