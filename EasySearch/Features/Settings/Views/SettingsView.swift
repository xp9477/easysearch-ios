import SwiftUI

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

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section("通用") {
                    NavigationLink(value: SettingsRoute.cloudSync) {
                        Label {
                            Text("云端同步")
                        } icon: {
                            ESFeatureIcon(systemName: "icloud", color: .blue, size: 30)
                        }
                    }
                }

                Section("关于") {
                    LabeledContent("版本", value: appVersionText)

                    Button {
                        Task {
                            await appUpdateService.checkForUpdates()
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

                    if let message = appUpdateService.statusMessage?
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
            .onChange(of: navigationState.pendingSettingsRoute) { _ in
                handlePendingRouteIfNeeded()
            }
            .onChange(of: navigationState.selectedTab) { tab in
                if tab == .settings {
                    Task { await statusCenter.refresh() }
                    handlePendingRouteIfNeeded()
                }
            }
        }
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
            // Still show latest release notes so users know what landed in the current build.
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

        case .unavailable:
            EmptyView()
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

}

#Preview {
    SettingsView()
        .environmentObject(AppNavigationState())
}
