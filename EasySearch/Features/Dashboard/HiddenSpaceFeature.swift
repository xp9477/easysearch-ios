import SwiftUI

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

    @MainActor
    public func statusSummary() async -> FeatureStatusSummary {
        FeatureStatusSummary(kind: .ready, text: "私密")
    }
}
