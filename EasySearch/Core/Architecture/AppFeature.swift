import SwiftUI

// MARK: - Placement & Groups

public enum AppFeaturePlacement: String {
    case primaryTab
    case moduleList
    case hiddenModule
}

/// Capability-type groups for the workbench module list.
public enum AppFeatureGroup: String, CaseIterable, Identifiable, Hashable {
    case recordsAndProgress
    case aiAndContent
    case connectAndOps
    case utilities

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .recordsAndProgress: return "记录与进度"
        case .aiAndContent: return "AI 与内容"
        case .connectAndOps: return "连接与运维"
        case .utilities: return "实用工具"
        }
    }
}

// MARK: - Global Feature Status

public enum FeatureStatusKind: String, Equatable, Hashable {
    case ready
    case needsConfiguration
    case needsAuthorization
    case empty
    case processing
    case offlineOrUnavailable
    case recoverableFailure
    case attentionNeeded
}

public struct FeatureStatusSummary: Equatable, Hashable {
    public let kind: FeatureStatusKind
    public let text: String

    public init(kind: FeatureStatusKind, text: String) {
        self.kind = kind
        self.text = text
    }

    public static let ready = FeatureStatusSummary(kind: .ready, text: "可用")
}

// MARK: - AppFeature

/// Represents a distinct feature or "mini-app" within the super app.
public protocol AppFeature: Identifiable {
    var id: String { get }
    var title: String { get }
    var summary: String { get }
    var iconName: String { get }
    var color: Color { get }
    var placement: AppFeaturePlacement { get }
    /// Capability group for module-list features. Nil for primary tab / hidden.
    var group: AppFeatureGroup? { get }

    @MainActor
    @ViewBuilder
    var entryView: AnyView { get }

    /// Feature-owned status for the workbench / status center (avoids Core omniscience).
    @MainActor
    func statusSummary() async -> FeatureStatusSummary
}

public extension AppFeature {
    var group: AppFeatureGroup? { nil }

    @MainActor
    func statusSummary() async -> FeatureStatusSummary { .ready }
}

extension View {
    func appTabBarBehavior() -> some View {
        tabBarMinimizeBehavior(.onScrollDown)
    }
}
