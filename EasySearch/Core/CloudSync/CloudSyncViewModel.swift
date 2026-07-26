import Combine
import Foundation

/// App-wide cloud sync owner. Features should not implement parallel full-sync paths.
@MainActor
final class CloudSyncViewModel: ObservableObject {
    static let shared = CloudSyncViewModel()

    @Published var isCloudConfigured = false
    @Published var isCloudAuthenticated = false
    @Published var cloudUserEmail: String?
    @Published var cloudStatusMessage: String?
    @Published var isPreparingCloud = false
    @Published var isCloudBusy = false

    private let cloudService = HiddenSupabaseService.shared
    private var didPrepareCloud = false

    func prepareIfNeeded() async {
        guard !didPrepareCloud, !isPreparingCloud else { return }
        didPrepareCloud = true

        isPreparingCloud = true
        defer { isPreparingCloud = false }

        guard let configuration = await cloudService.configuration() else {
            isCloudConfigured = false
            isCloudAuthenticated = false
            cloudUserEmail = nil
            cloudStatusMessage = "未配置云端同步，当前仅保存在本地。"
            return
        }

        isCloudConfigured = true
        cloudStatusMessage = "已连接 \(configuration.projectHost)，正在检查会话..."

        do {
            if let session = try await cloudService.restoreSessionIfPossible() {
                applySession(session)
                await syncNow(reason: "已恢复云端会话")
            } else {
                isCloudAuthenticated = false
                cloudUserEmail = nil
                cloudStatusMessage = "云端已配置，但尚未登录。"
            }
        } catch {
            isCloudAuthenticated = false
            cloudUserEmail = nil
            cloudStatusMessage = "云端会话恢复失败：\(error.localizedDescription)"
            didPrepareCloud = false
        }
    }

    func syncIfPossible() async {
        guard !isPreparingCloud, !isCloudBusy else { return }

        if !didPrepareCloud {
            await prepareIfNeeded()
            return
        }

        guard isCloudConfigured, isCloudAuthenticated else { return }
        await syncNow(reason: "同步成功")
    }

    /// Call when a feature-level mutation gets 401/403 so UI state stays consistent.
    func markAuthenticationLost(message: String? = nil) {
        isCloudAuthenticated = false
        didPrepareCloud = false
        if let message {
            cloudStatusMessage = message
        }
    }

    func signIn(email: String, password: String) async {
        guard isCloudConfigured else {
            cloudStatusMessage = "请先配置 Supabase URL 和 publishable key。"
            return
        }

        isCloudBusy = true
        defer { isCloudBusy = false }

        do {
            let session = try await cloudService.signIn(email: email, password: password)
            applySession(session)
            await syncNow(reason: "登录成功")
        } catch {
            cloudStatusMessage = "登录失败：\(error.localizedDescription)"
        }
    }

    func signUp(email: String, password: String) async {
        guard isCloudConfigured else {
            cloudStatusMessage = "请先配置 Supabase URL 和 publishable key。"
            return
        }

        isCloudBusy = true
        defer { isCloudBusy = false }

        do {
            let outcome = try await cloudService.signUp(email: email, password: password)
            switch outcome {
            case let .authenticated(session):
                applySession(session)
                await syncNow(reason: "注册成功")
            case let .confirmationRequired(message):
                isCloudAuthenticated = false
                cloudUserEmail = nil
                cloudStatusMessage = message
            }
        } catch {
            cloudStatusMessage = "注册失败：\(error.localizedDescription)"
        }
    }

    func signOut() async {
        await cloudService.signOut()
        isCloudAuthenticated = false
        cloudUserEmail = nil
        cloudStatusMessage = "已退出云端登录，当前仅保存在本地。"
    }

    func syncNow() async {
        await syncNow(reason: "同步成功")
    }

    func syncUTEntryUpsertIfPossible(_ entry: UTEntry) async {
        guard await prepareForMutationIfNeeded() else { return }

        do {
            try await cloudService.upsertUTEntry(entry)
            cloudStatusMessage = "已同步 UT 记录到云端"
        } catch {
            handleCloudMutationError(error, fallbackMessage: "UT 云端同步失败")
        }
    }

    func syncUTEntryDeletionIfPossible(_ entry: UTEntry) async {
        guard await prepareForMutationIfNeeded() else { return }

        do {
            try await cloudService.deleteUTEntry(id: entry.id)
            cloudStatusMessage = "已从云端移除 UT 记录"
        } catch {
            handleCloudMutationError(error, fallbackMessage: "UT 云端删除失败")
        }
    }

    func syncQingLongProfileUpsertIfPossible(_ profile: QingLongPanelProfile) async {
        guard await prepareForMutationIfNeeded() else { return }

        do {
            try await cloudService.upsertQingLongPanelProfile(profile)
            cloudStatusMessage = "已同步青龙面板配置到云端"
        } catch {
            handleCloudMutationError(error, fallbackMessage: "青龙面板配置同步失败")
        }
    }

    func syncQingLongProfileDeletionIfPossible(profileID: String) async {
        guard await prepareForMutationIfNeeded() else { return }

        do {
            try await cloudService.deleteQingLongPanelProfile(id: profileID)
            cloudStatusMessage = "已从云端移除青龙面板配置"
        } catch {
            handleCloudMutationError(error, fallbackMessage: "青龙面板配置删除失败")
        }
    }

    private func syncNow(reason: String) async {
        guard isCloudAuthenticated else { return }

        isCloudBusy = true
        defer { isCloudBusy = false }

        do {
            _ = try await CloudSyncCoordinator.sync(makeCollections())
            cloudStatusMessage = reason
        } catch {
            if error.isHiddenSupabaseAuthFailure {
                isCloudAuthenticated = false
                didPrepareCloud = false
            }
            cloudStatusMessage = "云端同步失败：\(error.localizedDescription)"
        }
    }

    private func makeCollections() -> [AnyCloudSyncCollection] {
        [
            CloudSyncCollection(
                label: "jav 影片",
                unit: "部",
                loadLocal: {
                    let localPlaybacks = HiddenJavDBLocalStore.loadFavoritePlaybacks()
                    return HiddenCloudMerge.movies(
                        primary: HiddenJavDBLocalStore.loadFavoriteMovies(),
                        secondary: localPlaybacks.map(\.movie)
                    )
                },
                fetchRemote: { try await self.cloudService.fetchFavorites() },
                saveLocal: HiddenJavDBLocalStore.saveFavoriteMovies,
                upsertRemote: { try await self.cloudService.upsertFavorites($0) },
                merge: HiddenCloudMerge.movies
            ).eraseToAnyCollection(),
            CloudSyncCollection(
                label: "jav 播放点",
                unit: "条",
                loadLocal: HiddenJavDBLocalStore.loadFavoritePlaybacks,
                fetchRemote: { try await self.cloudService.fetchPlaybacks() },
                saveLocal: HiddenJavDBLocalStore.saveFavoritePlaybacks,
                upsertRemote: { try await self.cloudService.upsertPlaybacks($0) },
                merge: HiddenCloudMerge.playbacks
            ).eraseToAnyCollection(),
            CloudSyncCollection(
                label: "4khd album",
                unit: "个",
                loadLocal: Hidden4KHDLocalStore.loadFavoriteAlbums,
                fetchRemote: { try await self.cloudService.fetch4KHDAlbums() },
                saveLocal: Hidden4KHDLocalStore.saveFavoriteAlbums,
                upsertRemote: { try await self.cloudService.upsert4KHDAlbums($0) },
                merge: HiddenCloudMerge.albums
            ).eraseToAnyCollection(),
            CloudSyncCollection(
                label: "图片",
                unit: "张",
                loadLocal: Hidden4KHDLocalStore.loadFavoriteImages,
                fetchRemote: { try await self.cloudService.fetch4KHDImages() },
                saveLocal: Hidden4KHDLocalStore.saveFavoriteImages,
                upsertRemote: { try await self.cloudService.upsert4KHDImages($0) },
                merge: HiddenCloudMerge.imageURLs
            ).eraseToAnyCollection(),
            CloudSyncCollection(
                label: "UT",
                unit: "条",
                loadLocal: { UTTrackerLocalStore().loadEntries() },
                fetchRemote: { try await self.cloudService.fetchUTEntries() },
                saveLocal: { UTTrackerLocalStore().saveEntries($0) },
                upsertRemote: { try await self.cloudService.upsertUTEntries($0) },
                merge: HiddenCloudMerge.utEntries
            ).eraseToAnyCollection(),
            CloudSyncCollection(
                label: "青龙",
                unit: "个",
                loadLocal: {
                    QingLongPanelLocalStore().loadProfile().map { [$0] } ?? []
                },
                fetchRemote: { try await self.cloudService.fetchQingLongPanelProfiles() },
                saveLocal: { profiles in
                    let store = QingLongPanelLocalStore()
                    if let profile = profiles.first {
                        store.saveProfile(profile, postsNotification: true)
                    } else {
                        store.deleteProfile()
                    }
                },
                upsertRemote: { try await self.cloudService.upsertQingLongPanelProfiles($0) },
                merge: HiddenCloudMerge.qingLongProfiles
            ).eraseToAnyCollection()
        ]
    }

    private func applySession(_ session: HiddenSupabaseSession) {
        isCloudAuthenticated = true
        cloudUserEmail = session.email
        cloudStatusMessage = session.email?.cloudNonEmpty.map { "已登录 \($0)" } ?? "已登录云端同步"
    }

    private func prepareForMutationIfNeeded() async -> Bool {
        if !didPrepareCloud {
            await prepareIfNeeded()
        }

        return isCloudConfigured && isCloudAuthenticated
    }

    private func handleCloudMutationError(_ error: Error, fallbackMessage: String) {
        if error.isHiddenSupabaseAuthFailure {
            isCloudAuthenticated = false
            didPrepareCloud = false
        }

        cloudStatusMessage = "\(fallbackMessage)：\(error.localizedDescription)"
    }
}
