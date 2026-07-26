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
            ScrollView {
                VStack(alignment: .leading, spacing: ESUI.sectionSpacing) {
                    simpleListSection(title: "通用") {
                        NavigationLink(value: SettingsRoute.cloudSync) {
                            ESSettingsRow(title: "云端同步", systemImage: "icloud", iconColor: .blue)
                        }
                        .buttonStyle(.plain)

                        NavigationLink(value: SettingsRoute.imageTranslate) {
                            ESSettingsRow(title: "AI 服务", systemImage: "sparkles", iconColor: .cyan)
                        }
                        .buttonStyle(.plain)
                    }

                    simpleListSection(title: "关于") {
                        ESSettingsRow(
                            title: "版本 \(appVersionText)",
                            systemImage: "info.circle",
                            iconColor: .secondary,
                            showsChevron: false
                        )

                        Button {
                            Task {
                                await appUpdateService.checkForUpdates()
                            }
                        } label: {
                            ESSettingsRow(
                                title: appUpdateService.isChecking ? "正在检查…" : "检测更新",
                                systemImage: "arrow.triangle.2.circlepath",
                                iconColor: .blue,
                                showsChevron: false
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(appUpdateService.isChecking || appUpdateService.isDownloading)

                        if case let .updateAvailable(_, remote) = appUpdateService.lastResult {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("新版本 \(remote.displayVersion)")
                                    .font(.subheadline.weight(.semibold))
                                if let notes = remote.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
                                   !notes.isEmpty {
                                    Text(notes)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }

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
                            .padding(.horizontal, 4)
                            .padding(.top, 4)
                        }

                        if let message = appUpdateService.statusMessage?
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                           !message.isEmpty {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                        }
                    }
                }
                .padding(.horizontal, ESUI.screenHorizontalPadding)
                .padding(.top, ESUI.Space.lg)
                .padding(.bottom, ESUI.Space.huge)
            }
            .esBottomTabPadding()
            .esScreenBackground()
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
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

    private func simpleListSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.bottom, 2)

            VStack(spacing: ESUI.Space.sm) {
                content()
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
        case .imageTranslate:
            AISettingsDetailView(entry: .imageTranslate)
        case .emailAssistant:
            AISettingsDetailView(entry: .emailAssistant)
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
