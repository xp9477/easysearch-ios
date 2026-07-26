import Foundation

@MainActor
final class ExpenseAssistantViewModel: ObservableObject {
    @Published private(set) var snapshot: ExpenseAssistantSnapshot

    private let store: any ExpenseAssistantStore
    private let calendar: Calendar
    private let notificationCenter: NotificationCenter
    private let nowProvider: () -> Date
    private var observer: NSObjectProtocol?

    init(
        store: any ExpenseAssistantStore = ExpenseAssistantLocalStore(),
        calendar: Calendar = .expenseAssistant,
        notificationCenter: NotificationCenter = .default,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.calendar = calendar
        self.notificationCenter = notificationCenter
        self.nowProvider = nowProvider

        let loadedSnapshot = store.loadSnapshot()
        let normalizedSnapshot = ExpenseAssistantReminderEngine.normalized(
            snapshot: loadedSnapshot,
            now: nowProvider(),
            calendar: calendar
        )
        snapshot = normalizedSnapshot

        if loadedSnapshot != normalizedSnapshot {
            store.saveSnapshot(normalizedSnapshot)
        }

        observer = notificationCenter.addObserver(
            forName: .expenseAssistantDataDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reloadFromStore()
            }
        }
    }

    deinit {
        if let observer {
            notificationCenter.removeObserver(observer)
        }
    }

    var monthlyClaims: [MonthlyExpenseClaim] {
        snapshot.monthlyClaims
    }

    var travelClaims: [TravelExpenseClaim] {
        snapshot.travelClaims
    }

    var overdueMonthlyClaims: [MonthlyExpenseClaim] {
        ExpenseAssistantReminderEngine.overdueMonthlyClaims(
            in: snapshot,
            asOf: nowProvider(),
            calendar: calendar
        )
    }

    var overdueTravelClaims: [TravelExpenseClaim] {
        ExpenseAssistantReminderEngine.overdueTravelClaims(
            in: snapshot,
            asOf: nowProvider(),
            calendar: calendar
        )
    }

    var overdueMonthlyClaimIDs: Set<String> {
        Set(overdueMonthlyClaims.map(\.id))
    }

    var overdueTravelClaimIDs: Set<UUID> {
        Set(overdueTravelClaims.map(\.id))
    }

    var nextReminderDate: Date? {
        ExpenseAssistantReminderEngine.nextReminderDate(
            in: snapshot,
            after: nowProvider(),
            calendar: calendar
        )
    }

    func refreshIfNeeded() {
        let normalizedSnapshot = ExpenseAssistantReminderEngine.normalized(
            snapshot: store.loadSnapshot(),
            now: nowProvider(),
            calendar: calendar
        )
        guard normalizedSnapshot != snapshot else { return }
        snapshot = normalizedSnapshot
        store.saveSnapshot(normalizedSnapshot)
    }

    func monthlyClaim(id: String) -> MonthlyExpenseClaim? {
        snapshot.monthlyClaims.first(where: { $0.id == id })
    }

    func travelClaim(id: UUID) -> TravelExpenseClaim? {
        snapshot.travelClaims.first(where: { $0.id == id })
    }

    @discardableResult
    func addTravelClaim(title: String, startDate: Date) -> TravelExpenseClaim {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let claim = TravelExpenseClaim(
            title: trimmedTitle,
            startDate: startDate,
            createdAt: nowProvider(),
            updatedAt: nowProvider()
        )
        snapshot.travelClaims.insert(claim, at: 0)
        persistSnapshot(syncMonthly: nil, syncTravel: claim)
        return claim
    }

    func updateMonthlyStatus(
        claimID: String,
        field: MonthlyExpenseField,
        status: ExpenseClaimItemStatus
    ) {
        mutateMonthlyClaim(claimID: claimID) { claim in
            claim.setStatus(status, for: field)
        }
    }

    func updateTravelTitle(claimID: UUID, title: String) {
        mutateTravelClaim(claimID: claimID) { claim in
            claim.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func updateTravelStartDate(claimID: UUID, startDate: Date) {
        mutateTravelClaim(claimID: claimID) { claim in
            claim.startDate = startDate
            if let endDate = claim.endDate, endDate < startDate {
                claim.endDate = startDate
            }
        }
    }

    func updateTravelEndDate(claimID: UUID, endDate: Date?) {
        mutateTravelClaim(claimID: claimID) { claim in
            if let endDate {
                claim.endDate = max(endDate, claim.startDate)
            } else {
                claim.endDate = nil
            }
        }
    }

    func updateTravelApprovalStatus(claimID: UUID, status: TravelApprovalStatus) {
        mutateTravelClaim(claimID: claimID) { claim in
            claim.travelApprovalStatus = status
        }
    }

    func updateTravelStatus(
        claimID: UUID,
        field: TravelExpenseField,
        status: ExpenseClaimItemStatus
    ) {
        mutateTravelClaim(claimID: claimID) { claim in
            claim.setStatus(status, for: field)
        }
    }

    /// 把所有逾期项一键置为"已提交"(仍可在详情内继续改状态)。
    func markAllOverdueSubmitted() {
        let overdueMonthlyIDs = overdueMonthlyClaimIDs
        let overdueTravelIDs = overdueTravelClaimIDs
        guard !overdueMonthlyIDs.isEmpty || !overdueTravelIDs.isEmpty else { return }

        var changedMonthly: [MonthlyExpenseClaim] = []
        var changedTravel: [TravelExpenseClaim] = []

        for index in snapshot.monthlyClaims.indices where overdueMonthlyIDs.contains(snapshot.monthlyClaims[index].id) {
            for field in MonthlyExpenseField.allCases where !snapshot.monthlyClaims[index].status(for: field).isResolved {
                snapshot.monthlyClaims[index].setStatus(.submitted, for: field)
            }
            changedMonthly.append(snapshot.monthlyClaims[index])
        }

        for index in snapshot.travelClaims.indices where overdueTravelIDs.contains(snapshot.travelClaims[index].id) {
            for field in TravelExpenseField.allCases where !snapshot.travelClaims[index].status(for: field).isResolved {
                snapshot.travelClaims[index].setStatus(.submitted, for: field)
            }
            snapshot.travelClaims[index].updatedAt = nowProvider()
            changedTravel.append(snapshot.travelClaims[index])
        }

        let normalizedSnapshot = ExpenseAssistantReminderEngine.normalized(
            snapshot: snapshot,
            now: nowProvider(),
            calendar: calendar
        )
        snapshot = normalizedSnapshot
        store.saveSnapshot(normalizedSnapshot)
        Task {
            await ExpenseAssistantNotificationManager.shared.refreshSchedulesIfAuthorized()
            for claim in changedMonthly {
                let latest = normalizedSnapshot.monthlyClaims.first(where: { $0.id == claim.id }) ?? claim
                await CloudSyncViewModel.shared.syncExpenseMonthlyClaimIfPossible(latest)
            }
            for claim in changedTravel {
                let latest = normalizedSnapshot.travelClaims.first(where: { $0.id == claim.id }) ?? claim
                await CloudSyncViewModel.shared.syncExpenseTravelClaimIfPossible(latest)
            }
        }
    }

    private func reloadFromStore() {
        let reloadedSnapshot = ExpenseAssistantReminderEngine.normalized(
            snapshot: store.loadSnapshot(),
            now: nowProvider(),
            calendar: calendar
        )
        guard reloadedSnapshot != snapshot else { return }
        snapshot = reloadedSnapshot
    }

    private func mutateMonthlyClaim(
        claimID: String,
        mutation: (inout MonthlyExpenseClaim) -> Void
    ) {
        guard let index = snapshot.monthlyClaims.firstIndex(where: { $0.id == claimID }) else { return }
        mutation(&snapshot.monthlyClaims[index])
        let claim = snapshot.monthlyClaims[index]
        persistSnapshot(syncMonthly: claim, syncTravel: nil)
    }

    private func mutateTravelClaim(
        claimID: UUID,
        mutation: (inout TravelExpenseClaim) -> Void
    ) {
        guard let index = snapshot.travelClaims.firstIndex(where: { $0.id == claimID }) else { return }
        mutation(&snapshot.travelClaims[index])
        snapshot.travelClaims[index].updatedAt = nowProvider()
        let claim = snapshot.travelClaims[index]
        persistSnapshot(syncMonthly: nil, syncTravel: claim)
    }

    private func persistSnapshot(
        syncMonthly: MonthlyExpenseClaim? = nil,
        syncTravel: TravelExpenseClaim? = nil
    ) {
        let normalizedSnapshot = ExpenseAssistantReminderEngine.normalized(
            snapshot: snapshot,
            now: nowProvider(),
            calendar: calendar
        )
        snapshot = normalizedSnapshot
        store.saveSnapshot(normalizedSnapshot)
        Task {
            await ExpenseAssistantNotificationManager.shared.refreshSchedulesIfAuthorized()
            if let syncMonthly {
                let claim = normalizedSnapshot.monthlyClaims.first(where: { $0.id == syncMonthly.id }) ?? syncMonthly
                await CloudSyncViewModel.shared.syncExpenseMonthlyClaimIfPossible(claim)
            }
            if let syncTravel {
                let claim = normalizedSnapshot.travelClaims.first(where: { $0.id == syncTravel.id }) ?? syncTravel
                await CloudSyncViewModel.shared.syncExpenseTravelClaimIfPossible(claim)
            }
        }
    }
}
