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
    @Published private(set) var isCloudIdentityMismatch = false

    private let cloudService = HiddenSupabaseService.shared
    private let identityStore = CloudSyncIdentityStore()
    private var didPrepareCloud = false
    private var preparationWaiters: [CheckedContinuation<Void, Never>] = []
    private var isSyncingCollections = false
    private var cloudUserID: UUID?

    func prepareIfNeeded() async {
        if isPreparingCloud {
            await withCheckedContinuation { continuation in
                preparationWaiters.append(continuation)
            }
            return
        }
        guard !didPrepareCloud else { return }
        didPrepareCloud = true

        isPreparingCloud = true
        defer { finishPreparation() }

        guard let configuration = await cloudService.configuration() else {
            isCloudConfigured = false
            isCloudAuthenticated = false
            cloudUserEmail = nil
            cloudUserID = nil
            isCloudIdentityMismatch = false
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
                cloudUserID = nil
                isCloudIdentityMismatch = false
                cloudStatusMessage = "云端已配置，但尚未登录。"
            }
        } catch {
            isCloudAuthenticated = false
            cloudUserEmail = nil
            cloudUserID = nil
            isCloudIdentityMismatch = false
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

        guard isCloudConfigured, canSyncCurrentAccount else { return }
        await syncNow(reason: "同步成功")
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
                cloudUserID = nil
                isCloudIdentityMismatch = false
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
        cloudUserID = nil
        isCloudIdentityMismatch = false
        cloudStatusMessage = "已退出云端登录，当前仅保存在本地。"
    }

    func syncNow() async {
        await syncNow(reason: "同步成功")
    }

    func syncUTEntryUpsertIfPossible(_ entry: UTEntry) async {
        guard let expectedUserID = await preparedMutationUserID() else { return }

        do {
            try await cloudService.upsertUTEntry(
                entry,
                expectedUserID: expectedUserID
            )
            guard mutationAccountIsCurrent(expectedUserID) else { return }
            cloudStatusMessage = "已同步 UT 记录到云端"
        } catch {
            guard mutationAccountIsCurrent(expectedUserID) else { return }
            handleCloudMutationError(error, fallbackMessage: "UT 云端同步失败")
        }
    }

    func syncUTEntryDeletionIfPossible(_ entry: UTEntry) async {
        guard let expectedUserID = await preparedMutationUserID() else { return }

        do {
            try await cloudService.deleteUTEntry(
                id: entry.id,
                expectedUserID: expectedUserID
            )
            guard mutationAccountIsCurrent(expectedUserID) else { return }
            cloudStatusMessage = "已从云端移除 UT 记录"
        } catch {
            guard mutationAccountIsCurrent(expectedUserID) else { return }
            handleCloudMutationError(error, fallbackMessage: "UT 云端删除失败")
        }
    }

    func syncJavFavoriteIfPossible(
        _ movie: HiddenJavDBMovie,
        shouldRemove: Bool
    ) async {
        guard let expectedUserID = await preparedMutationUserID() else { return }

        do {
            if shouldRemove {
                try await cloudService.deleteFavorite(
                    movieID: movie.id,
                    expectedUserID: expectedUserID
                )
            } else {
                try await cloudService.upsertFavorite(
                    movie,
                    expectedUserID: expectedUserID
                )
            }
            guard mutationAccountIsCurrent(expectedUserID) else { return }
            cloudStatusMessage = shouldRemove
                ? "已从云端移除喜欢影片"
                : "已同步喜欢影片到云端"
        } catch {
            guard mutationAccountIsCurrent(expectedUserID) else { return }
            handleCloudMutationError(error, fallbackMessage: "喜欢影片云端同步失败")
        }
    }

    func syncJavPlaybackUpsertIfPossible(
        _ playback: HiddenJavDBFavoritePlayback
    ) async {
        guard let expectedUserID = await preparedMutationUserID() else { return }

        do {
            try await cloudService.upsertPlayback(
                playback,
                expectedUserID: expectedUserID
            )
            guard mutationAccountIsCurrent(expectedUserID) else { return }
            cloudStatusMessage = "已同步播放收藏到云端"
        } catch {
            guard mutationAccountIsCurrent(expectedUserID) else { return }
            handleCloudMutationError(error, fallbackMessage: "播放收藏云端同步失败")
        }
    }

    func syncJavPlaybackDeletionIfPossible(playbackID: UUID) async {
        guard let expectedUserID = await preparedMutationUserID() else { return }

        do {
            try await cloudService.deletePlayback(
                id: playbackID,
                expectedUserID: expectedUserID
            )
            guard mutationAccountIsCurrent(expectedUserID) else { return }
            cloudStatusMessage = "已从云端移除播放收藏"
        } catch {
            guard mutationAccountIsCurrent(expectedUserID) else { return }
            handleCloudMutationError(error, fallbackMessage: "播放收藏删除失败")
        }
    }

    func sync4KHDAlbumIfPossible(
        _ album: HiddenAlbum,
        shouldRemove: Bool
    ) async {
        guard let expectedUserID = await preparedMutationUserID() else { return }

        do {
            if shouldRemove {
                try await cloudService.delete4KHDAlbum(
                    albumID: album.id,
                    expectedUserID: expectedUserID
                )
            } else {
                try await cloudService.upsert4KHDAlbum(
                    album,
                    expectedUserID: expectedUserID
                )
            }
            guard mutationAccountIsCurrent(expectedUserID) else { return }
            cloudStatusMessage = shouldRemove
                ? "已从云端移除 4KHD 收藏"
                : "已同步 4KHD 收藏到云端"
        } catch {
            guard mutationAccountIsCurrent(expectedUserID) else { return }
            handleCloudMutationError(error, fallbackMessage: "4KHD 收藏云端同步失败")
        }
    }

    func sync4KHDImageIfPossible(
        _ imageURL: URL,
        shouldRemove: Bool
    ) async {
        guard let expectedUserID = await preparedMutationUserID() else { return }
        let imageID = imageURL.absoluteString

        do {
            if shouldRemove {
                try await cloudService.delete4KHDImage(
                    imageID: imageID,
                    expectedUserID: expectedUserID
                )
            } else {
                try await cloudService.upsert4KHDImage(
                    imageURL,
                    expectedUserID: expectedUserID
                )
            }
            guard mutationAccountIsCurrent(expectedUserID) else { return }
            cloudStatusMessage = shouldRemove
                ? "已从云端移除图片收藏"
                : "已同步图片收藏到云端"
        } catch {
            guard mutationAccountIsCurrent(expectedUserID) else { return }
            handleCloudMutationError(error, fallbackMessage: "图片收藏云端同步失败")
        }
    }

    func syncQingLongProfileUpsertIfPossible(_ profile: QingLongPanelProfile) async {
        guard let expectedUserID = await preparedMutationUserID() else { return }

        do {
            try await cloudService.upsertQingLongPanelProfile(
                profile,
                expectedUserID: expectedUserID
            )
            guard mutationAccountIsCurrent(expectedUserID) else { return }
            cloudStatusMessage = "已同步青龙面板配置到云端"
        } catch {
            guard mutationAccountIsCurrent(expectedUserID) else { return }
            handleCloudMutationError(error, fallbackMessage: "青龙面板配置同步失败")
        }
    }

    func syncQingLongProfileDeletionIfPossible(profileID: String) async {
        guard let expectedUserID = await preparedMutationUserID() else { return }

        do {
            try await cloudService.deleteQingLongPanelProfile(
                id: profileID,
                expectedUserID: expectedUserID
            )
            guard mutationAccountIsCurrent(expectedUserID) else { return }
            cloudStatusMessage = "已从云端移除青龙面板配置"
        } catch {
            guard mutationAccountIsCurrent(expectedUserID) else { return }
            handleCloudMutationError(error, fallbackMessage: "青龙面板配置删除失败")
        }
    }

    func syncTrainingDayUpsertIfPossible(_ day: WorkoutDay) async {
        guard let expectedUserID = await preparedMutationUserID() else { return }
        do {
            try await cloudService.upsertTrainingDay(
                day,
                expectedUserID: expectedUserID
            )
            guard mutationAccountIsCurrent(expectedUserID) else { return }
            cloudStatusMessage = "已同步训练记录到云端"
        } catch {
            guard mutationAccountIsCurrent(expectedUserID) else { return }
            handleCloudMutationError(error, fallbackMessage: "训练记录云端同步失败")
        }
    }

    func syncExpenseMonthlyClaimIfPossible(_ claim: MonthlyExpenseClaim) async {
        guard let expectedUserID = await preparedMutationUserID() else { return }
        do {
            try await cloudService.upsertExpenseMonthlyClaim(
                claim,
                expectedUserID: expectedUserID
            )
            guard mutationAccountIsCurrent(expectedUserID) else { return }
            cloudStatusMessage = "已同步报销到云端"
        } catch {
            guard mutationAccountIsCurrent(expectedUserID) else { return }
            handleCloudMutationError(error, fallbackMessage: "报销云端同步失败")
        }
    }

    func syncExpenseTravelClaimIfPossible(_ claim: TravelExpenseClaim) async {
        guard let expectedUserID = await preparedMutationUserID() else { return }
        do {
            try await cloudService.upsertExpenseTravelClaim(
                claim,
                expectedUserID: expectedUserID
            )
            guard mutationAccountIsCurrent(expectedUserID) else { return }
            cloudStatusMessage = "已同步出差报销到云端"
        } catch {
            guard mutationAccountIsCurrent(expectedUserID) else { return }
            handleCloudMutationError(error, fallbackMessage: "出差报销云端同步失败")
        }
    }

    private func syncNow(reason: String) async {
        guard isCloudAuthenticated, !isSyncingCollections else { return }
        guard canSyncCurrentAccount else {
            cloudStatusMessage = "当前账号与此设备的本地数据绑定不一致，已暂停同步。"
            return
        }
        guard let expectedUserID = cloudUserID else {
            cloudStatusMessage = "无法确认云端账号身份，已暂停同步。"
            return
        }

        isSyncingCollections = true
        isCloudBusy = true
        defer {
            isSyncingCollections = false
            isCloudBusy = false
        }

        do {
            _ = try await CloudSyncCoordinator.sync(
                makeCollections(expectedUserID: expectedUserID)
            )
            guard mutationAccountIsCurrent(expectedUserID) else { return }
            cloudStatusMessage = reason
        } catch {
            guard mutationAccountIsCurrent(expectedUserID) else { return }
            if error.isHiddenSupabaseAuthFailure {
                isCloudAuthenticated = false
                cloudUserEmail = nil
                cloudUserID = nil
                isCloudIdentityMismatch = false
                didPrepareCloud = false
            }
            cloudStatusMessage = "云端同步失败：\(error.localizedDescription)"
        }
    }

    private func makeCollections(expectedUserID: UUID) -> [AnyCloudSyncCollection] {
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
                fetchRemote: {
                    try await self.cloudService.fetchFavorites(expectedUserID: expectedUserID)
                },
                saveLocal: HiddenJavDBLocalStore.saveFavoriteMovies,
                upsertRemote: {
                    try await self.cloudService.upsertFavorites(
                        $0,
                        expectedUserID: expectedUserID
                    )
                },
                merge: HiddenCloudMerge.movies
            ).eraseToAnyCollection(),
            CloudSyncCollection(
                label: "jav 播放点",
                unit: "条",
                loadLocal: HiddenJavDBLocalStore.loadFavoritePlaybacks,
                fetchRemote: {
                    try await self.cloudService.fetchPlaybacks(expectedUserID: expectedUserID)
                },
                saveLocal: HiddenJavDBLocalStore.saveFavoritePlaybacks,
                upsertRemote: {
                    try await self.cloudService.upsertPlaybacks(
                        $0,
                        expectedUserID: expectedUserID
                    )
                },
                merge: HiddenCloudMerge.playbacks
            ).eraseToAnyCollection(),
            CloudSyncCollection(
                label: "4khd album",
                unit: "个",
                loadLocal: Hidden4KHDLocalStore.loadFavoriteAlbums,
                fetchRemote: {
                    try await self.cloudService.fetch4KHDAlbums(expectedUserID: expectedUserID)
                },
                saveLocal: Hidden4KHDLocalStore.saveFavoriteAlbums,
                upsertRemote: {
                    try await self.cloudService.upsert4KHDAlbums(
                        $0,
                        expectedUserID: expectedUserID
                    )
                },
                merge: HiddenCloudMerge.albums
            ).eraseToAnyCollection(),
            CloudSyncCollection(
                label: "图片",
                unit: "张",
                loadLocal: Hidden4KHDLocalStore.loadFavoriteImages,
                fetchRemote: {
                    try await self.cloudService.fetch4KHDImages(expectedUserID: expectedUserID)
                },
                saveLocal: Hidden4KHDLocalStore.saveFavoriteImages,
                upsertRemote: {
                    try await self.cloudService.upsert4KHDImages(
                        $0,
                        expectedUserID: expectedUserID
                    )
                },
                merge: HiddenCloudMerge.imageURLs
            ).eraseToAnyCollection(),
            CloudSyncCollection(
                label: "UT",
                unit: "条",
                loadLocal: { UTTrackerLocalStore().loadEntries() },
                fetchRemote: {
                    try await self.cloudService.fetchUTEntries(expectedUserID: expectedUserID)
                },
                saveLocal: { UTTrackerLocalStore().saveEntries($0) },
                upsertRemote: {
                    try await self.cloudService.upsertUTEntries(
                        $0,
                        expectedUserID: expectedUserID
                    )
                },
                merge: HiddenCloudMerge.utEntries
            ).eraseToAnyCollection(),
            CloudSyncCollection(
                label: "青龙",
                unit: "个",
                loadLocal: {
                    QingLongPanelLocalStore().loadProfile().map { [$0] } ?? []
                },
                fetchRemote: {
                    try await self.cloudService.fetchQingLongPanelProfiles(
                        expectedUserID: expectedUserID
                    )
                },
                saveLocal: { profiles in
                    let store = QingLongPanelLocalStore()
                    if let profile = profiles.first {
                        store.saveProfile(profile, postsNotification: true)
                    } else {
                        store.deleteProfile()
                    }
                },
                upsertRemote: {
                    try await self.cloudService.upsertQingLongPanelProfiles(
                        $0,
                        expectedUserID: expectedUserID
                    )
                },
                merge: HiddenCloudMerge.qingLongProfiles
            ).eraseToAnyCollection(),
            CloudSyncCollection(
                label: "训练",
                unit: "天",
                loadLocal: {
                    Array(TrainingLogLocalStore().loadSnapshot().days.values)
                },
                fetchRemote: {
                    try await self.cloudService.fetchTrainingDays(expectedUserID: expectedUserID)
                },
                saveLocal: { days in
                    let store = TrainingLogLocalStore()
                    var map: [String: WorkoutDay] = [:]
                    for day in days {
                        map[day.id] = day
                    }
                    var snapshot = store.loadSnapshot()
                    snapshot.days = map
                    store.saveSnapshot(snapshot)
                },
                upsertRemote: {
                    try await self.cloudService.upsertTrainingDays(
                        $0,
                        expectedUserID: expectedUserID
                    )
                },
                merge: HiddenCloudMerge.workoutDays
            ).eraseToAnyCollection(),
            CloudSyncCollection(
                label: "月度报销",
                unit: "条",
                loadLocal: { ExpenseAssistantLocalStore().loadSnapshot().monthlyClaims },
                fetchRemote: {
                    try await self.cloudService.fetchExpenseMonthlyClaims(
                        expectedUserID: expectedUserID
                    )
                },
                saveLocal: { monthly in
                    let store = ExpenseAssistantLocalStore()
                    var snapshot = store.loadSnapshot()
                    snapshot.monthlyClaims = monthly
                    store.saveSnapshot(snapshot)
                },
                upsertRemote: {
                    try await self.cloudService.upsertExpenseMonthlyClaims(
                        $0,
                        expectedUserID: expectedUserID
                    )
                },
                merge: HiddenCloudMerge.monthlyExpenseClaims
            ).eraseToAnyCollection(),
            CloudSyncCollection(
                label: "出差报销",
                unit: "条",
                loadLocal: { ExpenseAssistantLocalStore().loadSnapshot().travelClaims },
                fetchRemote: {
                    try await self.cloudService.fetchExpenseTravelClaims(
                        expectedUserID: expectedUserID
                    )
                },
                saveLocal: { travel in
                    let store = ExpenseAssistantLocalStore()
                    var snapshot = store.loadSnapshot()
                    snapshot.travelClaims = travel
                    store.saveSnapshot(snapshot)
                },
                upsertRemote: {
                    try await self.cloudService.upsertExpenseTravelClaims(
                        $0,
                        expectedUserID: expectedUserID
                    )
                },
                merge: HiddenCloudMerge.travelExpenseClaims
            ).eraseToAnyCollection()
        ]
    }

    private func applySession(_ session: HiddenSupabaseSession) {
        isCloudAuthenticated = true
        cloudUserID = session.userID
        cloudUserEmail = session.email
        guard let userID = session.userID else {
            isCloudIdentityMismatch = true
            cloudStatusMessage = "无法确认云端账号身份，已暂停同步。"
            return
        }

        switch identityStore.match(for: userID) {
        case .unbound:
            identityStore.bind(to: userID)
            isCloudIdentityMismatch = false
        case .matches:
            isCloudIdentityMismatch = false
        case .mismatches:
            isCloudIdentityMismatch = true
        }

        if isCloudIdentityMismatch {
            cloudStatusMessage = "检测到不同云端账号。为避免数据互相覆盖，已暂停同步。"
        } else {
            cloudStatusMessage = session.email?.cloudNonEmpty.map { "已登录 \($0)" } ?? "已登录云端同步"
        }
    }

    private func prepareForMutationIfNeeded() async -> Bool {
        if isPreparingCloud || !didPrepareCloud {
            await prepareIfNeeded()
        }

        return isCloudConfigured && canSyncCurrentAccount
    }

    private func preparedMutationUserID() async -> UUID? {
        guard await prepareForMutationIfNeeded() else { return nil }
        return cloudUserID
    }

    private func mutationAccountIsCurrent(_ expectedUserID: UUID) -> Bool {
        canSyncCurrentAccount && cloudUserID == expectedUserID
    }

    private func handleCloudMutationError(_ error: Error, fallbackMessage: String) {
        if error.isHiddenSupabaseAuthFailure {
            isCloudAuthenticated = false
            cloudUserEmail = nil
            cloudUserID = nil
            isCloudIdentityMismatch = false
            didPrepareCloud = false
        }

        cloudStatusMessage = "\(fallbackMessage)：\(error.localizedDescription)"
    }

    private func finishPreparation() {
        isPreparingCloud = false
        let waiters = preparationWaiters
        preparationWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private var canSyncCurrentAccount: Bool {
        isCloudAuthenticated && cloudUserID != nil && !isCloudIdentityMismatch
    }
}
