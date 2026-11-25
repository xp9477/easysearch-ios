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
                        ESNavigationRow(
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

                Section("应用") {
                    NavigationLink(value: SettingsRoute.softwareUpdate) {
                        ESNavigationRow(
                            title: "软件更新", icon: "arrow.clockwise", color: .blue,
                            status: appUpdateService.currentVersionLabel
                        )
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
            ESNavigationRow(
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

private struct SoftwareUpdateView: View {
    @ObservedObject var service: AppUpdateService
    @State private var downloadFailure: String?
    @State private var isVisible = false

    var body: some View {
        List {
            if service.isChecking || service.lastResult == nil {
                ProgressView("正在检查更新…")
            } else if let result = service.lastResult {
                resultSections(result)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("软件更新")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .task {
            guard !service.isDownloading else { return }
            await checkForUpdates()
        }
        .refreshable { await checkForUpdates() }
    }

    @ViewBuilder
    private func resultSections(_ result: AppUpdateCheckResult) -> some View {
        switch result {
        case let .updateAvailable(current, remote):
            Section {
                versionSummary(
                    "EasySearch \(remote.versionLabel)",
                    detail: remote.versionLabel == service.currentVersionLabel
                        ? "有新构建 · \(remote.build)"
                        : "有新版本"
                )
            }

            Section {
                updateAction(for: remote)
                if let downloadFailure, !service.isDownloading {
                    Label(downloadFailure, systemImage: "exclamationmark.circle")
                        .font(.subheadline)
                }
            } footer: {
                Text("未签名 IPA，安装前需通过签名工具处理。")
            }

            releaseNotes(remote)
            installedVersion(current)

        case let .upToDate(current, remote):
            Section {
                versionSummary("EasySearch \(service.currentVersionLabel)", detail: "已是最新版本")
                Button("重新检查", systemImage: "arrow.clockwise") { Task { await checkForUpdates() } }
            }
            if remote.resolvedBuildNumber == Int(service.currentBuild) { releaseNotes(remote) }
            installedVersion(current)

        case let .unavailable(message):
            Section {
                VStack(alignment: .leading, spacing: ESUI.Space.xs) {
                    Label("暂时无法检查更新", systemImage: "exclamationmark.circle")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Button("重新检查") { Task { await checkForUpdates() } }
            }
            installedVersion(service.currentVersionText)
        }
    }

    private func versionSummary(_ version: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: ESUI.Space.xs) {
            Text(version).font(.title2.bold()).accessibilityAddTraits(.isHeader)
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.vertical, ESUI.Space.xs)
    }

    @ViewBuilder
    private func updateAction(for release: AppUpdateManifest) -> some View {
        Group {
            if let cached = service.cachedIPA(for: release) {
                ShareLink(item: cached) {
                    Text("分享已下载的 IPA").fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            } else {
                Button(action: downloadIPA) {
                    VStack(spacing: ESUI.Space.xs) {
                        Text(service.isDownloading ? "正在下载 IPA…" : "下载并分享 IPA").fontWeight(.semibold)
                        if service.isDownloading {
                            ProgressView(value: service.downloadProgress)
                                .tint(.white)
                                .accessibilityLabel("下载进度")
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(service.isDownloading)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(ESUI.primaryActionFill)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private func releaseNotes(_ release: AppUpdateManifest) -> some View {
        if let notes = release.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: ESUI.Space.xs) {
                    Text("更新内容").font(.headline).accessibilityAddTraits(.isHeader)
                    Text(notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(.vertical, ESUI.Space.xs)
            }
        }
    }

    private func installedVersion(_ current: String) -> some View {
        Section {
            LabeledContent("已安装", value: current)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
        }
    }

    private func checkForUpdates() async {
        guard !service.isChecking, !service.isDownloading else { return }
        downloadFailure = nil
        await service.checkForUpdates()
        guard !Task.isCancelled else { return }
        UIAccessibility.post(notification: .announcement, argument: service.statusMessage)
    }

    private func downloadIPA() {
        downloadFailure = nil
        Task {
            let fileURL = await service.downloadLatestIPA()
            guard isVisible else { return }
            if let fileURL {
                // The native ShareLink also remains available after dismissal or a failed presentation.
                _ = service.presentShareSheet(for: fileURL)
            } else {
                downloadFailure = service.statusMessage ?? "无法下载，请重试。"
                UIAccessibility.post(notification: .announcement, argument: downloadFailure)
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppNavigationState())
        .environmentObject(FeatureStatusCenter.shared)
}
