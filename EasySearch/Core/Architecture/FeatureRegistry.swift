import Foundation
import SwiftUI

// MARK: - Feature Registry

public class FeatureRegistry: ObservableObject {
    @Published public var features: [any AppFeature] = []
    @Published public private(set) var moduleFeatureOrderIDs: [String] = []

    private let userDefaults = UserDefaults.standard
    private let moduleOrderDefaultsKey = "featureRegistry.moduleFeatureOrder"

    public var primaryTabFeatures: [any AppFeature] {
        features.filter { $0.placement == .primaryTab }
    }

    public var moduleListFeatures: [any AppFeature] {
        orderedFeatures(from: features.filter { $0.placement == .moduleList })
    }

    public var hiddenFeatures: [any AppFeature] {
        features.filter { $0.placement == .hiddenModule }
    }

    /// Module features belonging to a capability group, ordered by stored order.
    public func moduleFeatures(in group: AppFeatureGroup) -> [any AppFeature] {
        moduleListFeatures.filter { $0.group == group }
    }

    public init() {
        features.append(EasySearchFeature())
        features.append(UTTrackerFeature())
        features.append(TrainingLogFeature())
        features.append(ExpenseAssistantFeature())
        features.append(QingLongFeature())
        features.append(ImageTranslateFeature())
        features.append(EmailAssistantFeature())
        features.append(UtilitiesFeature())
        features.append(WebDAVFeature())
        features.append(HiddenSpaceFeature())
        reloadModuleFeatureOrder()
    }

    public func moveModuleFeatures(fromOffsets: IndexSet, toOffset: Int) {
        var order = moduleFeatureOrderIDs
        order.move(fromOffsets: fromOffsets, toOffset: toOffset)
        moduleFeatureOrderIDs = order
        userDefaults.set(order, forKey: moduleOrderDefaultsKey)
    }

    /// Reorder features within a single group while preserving relative order of other groups.
    public func moveModuleFeatures(in group: AppFeatureGroup, fromOffsets: IndexSet, toOffset: Int) {
        let groupIDs = moduleFeatures(in: group).map(\.id)
        guard !groupIDs.isEmpty else { return }

        var mutableGroupIDs = groupIDs
        mutableGroupIDs.move(fromOffsets: fromOffsets, toOffset: toOffset)

        var nextOrder: [String] = []
        var groupCursor = 0
        let groupIDSet = Set(groupIDs)

        for id in moduleFeatureOrderIDs {
            if groupIDSet.contains(id) {
                if groupCursor < mutableGroupIDs.count {
                    nextOrder.append(mutableGroupIDs[groupCursor])
                    groupCursor += 1
                }
            } else {
                nextOrder.append(id)
            }
        }

        // Append any missing group IDs (should not happen after normalization).
        while groupCursor < mutableGroupIDs.count {
            nextOrder.append(mutableGroupIDs[groupCursor])
            groupCursor += 1
        }

        moduleFeatureOrderIDs = nextOrder
        userDefaults.set(nextOrder, forKey: moduleOrderDefaultsKey)
    }

    private func reloadModuleFeatureOrder() {
        let defaultIDs = features
            .filter { $0.placement == .moduleList }
            .map(\.id)
        let storedIDs = userDefaults.stringArray(forKey: moduleOrderDefaultsKey) ?? []
        let normalizedStoredIDs = storedIDs.filter { defaultIDs.contains($0) }
        let missingIDs = defaultIDs.filter { !normalizedStoredIDs.contains($0) }
        let normalizedOrder = normalizedStoredIDs + missingIDs

        moduleFeatureOrderIDs = normalizedOrder
        userDefaults.set(normalizedOrder, forKey: moduleOrderDefaultsKey)
    }

    private func orderedFeatures(from unorderedFeatures: [any AppFeature]) -> [any AppFeature] {
        let fallbackIndexByID = Dictionary(
            uniqueKeysWithValues: unorderedFeatures.enumerated().map { ($1.id, $0) }
        )
        let orderIndexByID = Dictionary(
            uniqueKeysWithValues: moduleFeatureOrderIDs.enumerated().map { ($1, $0) }
        )

        return unorderedFeatures.sorted { lhs, rhs in
            let lhsIndex = orderIndexByID[lhs.id] ?? (moduleFeatureOrderIDs.count + (fallbackIndexByID[lhs.id] ?? 0))
            let rhsIndex = orderIndexByID[rhs.id] ?? (moduleFeatureOrderIDs.count + (fallbackIndexByID[rhs.id] ?? 0))
            return lhsIndex < rhsIndex
        }
    }
}

// MARK: - Feature Status Center

@MainActor
public final class FeatureStatusCenter: ObservableObject {
    public static let shared = FeatureStatusCenter()

    @Published public private(set) var summaries: [String: FeatureStatusSummary] = [:]
    @Published public private(set) var cloudSummary = FeatureStatusSummary(kind: .needsConfiguration, text: "仅本地")
    @Published public private(set) var deepSeekSummary = FeatureStatusSummary(kind: .needsConfiguration, text: "未配置")
    @Published public private(set) var qingLongSummary = FeatureStatusSummary(kind: .needsConfiguration, text: "未连接")

    private init() {}

    public func summary(for featureID: String) -> FeatureStatusSummary {
        summaries[featureID] ?? .ready
    }

    public func refresh() async {
        let cloud = HiddenCloudSyncViewModel.shared
        await cloud.prepareIfNeeded()

        if !cloud.isCloudConfigured {
            cloudSummary = FeatureStatusSummary(kind: .empty, text: "仅本地")
        } else if cloud.isCloudAuthenticated {
            let email = cloud.cloudUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            cloudSummary = FeatureStatusSummary(
                kind: .ready,
                text: email.isEmpty ? "已登录" : email
            )
        } else {
            cloudSummary = FeatureStatusSummary(kind: .needsConfiguration, text: "未登录")
        }

        let deepSeek = ImageTranslateConfigurationStore.shared.loadConfiguration()
        deepSeekSummary = deepSeek.hasAPIKey
            ? FeatureStatusSummary(kind: .ready, text: "已配置")
            : FeatureStatusSummary(kind: .needsConfiguration, text: "未配置")

        let qingLong = QingLongPanelLocalStore().loadProfile()
        qingLongSummary = qingLong == nil
            ? FeatureStatusSummary(kind: .needsConfiguration, text: "未连接")
            : FeatureStatusSummary(kind: .ready, text: "已连接")

        var next: [String: FeatureStatusSummary] = [:]

        // UT Tracker
        let utEntries = UTTrackerLocalStore().loadEntries()
        let utAuth = UTNotificationManager.shared.authorizationStatus
        if utAuth == .denied {
            next["uttracker"] = FeatureStatusSummary(kind: .needsAuthorization, text: "通知未授权")
        } else if utEntries.isEmpty {
            next["uttracker"] = FeatureStatusSummary(kind: .empty, text: "暂无记录")
        } else {
            next["uttracker"] = FeatureStatusSummary(kind: .ready, text: "本月可记录")
        }

        // Training log
        let trainingSnapshot = TrainingLogLocalStore().loadSnapshot()
        let trainingMonthStart = TrainingLogCalendar.startOfMonth(Date())
        let trainingDaysThisMonth = trainingSnapshot.days.values.filter { day in
            day.hasTraining && TrainingLogCalendar.calendar.isDate(day.dayStart, equalTo: trainingMonthStart, toGranularity: .month)
        }.count
        if trainingSnapshot.days.values.contains(where: \.hasTraining) {
            next["training-log"] = FeatureStatusSummary(
                kind: .ready,
                text: trainingDaysThisMonth > 0 ? "本月 \(trainingDaysThisMonth) 天" : "有历史"
            )
        } else {
            next["training-log"] = FeatureStatusSummary(kind: .empty, text: "暂无训练")
        }

        // Expense
        let expenseSnapshot = ExpenseAssistantLocalStore().loadSnapshot()
        let expenseAuth = ExpenseAssistantNotificationManager.shared.authorizationStatus
        let overdueMonthly = ExpenseAssistantReminderEngine.overdueMonthlyClaims(in: expenseSnapshot, asOf: Date())
        let overdueTravel = ExpenseAssistantReminderEngine.overdueTravelClaims(in: expenseSnapshot, asOf: Date())
        if expenseAuth == .denied {
            next["expense-assistant"] = FeatureStatusSummary(kind: .needsAuthorization, text: "通知未授权")
        } else if expenseSnapshot.monthlyClaims.isEmpty && expenseSnapshot.travelClaims.isEmpty {
            next["expense-assistant"] = FeatureStatusSummary(kind: .empty, text: "暂无单据")
        } else if !overdueMonthly.isEmpty || !overdueTravel.isEmpty {
            next["expense-assistant"] = FeatureStatusSummary(kind: .attentionNeeded, text: "有待处理")
        } else {
            next["expense-assistant"] = FeatureStatusSummary(kind: .ready, text: "跟踪中")
        }
        // QingLong
        next["qinglong-management"] = qingLongSummary

        // Image Translate / Email share DeepSeek
        if deepSeek.hasAPIKey {
            next["image-translate"] = FeatureStatusSummary(kind: .ready, text: "可用")
            next["email-assistant"] = FeatureStatusSummary(kind: .ready, text: "可用")
        } else {
            next["image-translate"] = FeatureStatusSummary(kind: .needsConfiguration, text: "需配置 AI")
            next["email-assistant"] = FeatureStatusSummary(kind: .needsConfiguration, text: "需配置 AI")
        }

        // WebDAV
        let webdavState = await MainActor.run { () -> (Bool, Int) in
            let store = WebDAVSettingsStore.shared
            return (store.configuration != nil, store.locations.count)
        }
        if !webdavState.0 {
            next["webdav"] = FeatureStatusSummary(kind: .needsConfiguration, text: "未配置")
        } else {
            let count = webdavState.1
            next["webdav"] = FeatureStatusSummary(kind: .ready, text: count > 0 ? "\(count) 个位置" : "已连接")
        }
        // Utilities always ready
        next["utilities"] = FeatureStatusSummary(kind: .ready, text: "可用")

        summaries = next
    }
}

// MARK: - Hidden Space Feature

public struct HiddenSpaceFeature: AppFeature {
    public var id: String = "hidden-space"
    public var title: String = "隐藏空间"
    public var summary: String = "受保护的低曝光能力入口。"
    public var iconName: String = "lock.shield"
    public var color: Color = .purple
    public var placement: AppFeaturePlacement = .hiddenModule
    public var group: AppFeatureGroup? = nil

    public init() {}

    public var entryView: AnyView {
        AnyView(HiddenSpaceView())
    }
}
