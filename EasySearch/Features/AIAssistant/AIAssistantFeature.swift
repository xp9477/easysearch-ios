import SwiftUI

/// 合并翻译与邮件助手的统一 AI 工具入口。
public struct AIAssistantFeature: AppFeature {
    public var id: String = "ai-assistant"
    public var title: String = "AI 助手"
    public var summary: String = "翻译与英文邮件,一处搞定。"
    public var iconName: String = "sparkles"
    public var color: Color = .purple
    public var placement: AppFeaturePlacement = .moduleList
    public var group: AppFeatureGroup? = .aiAndContent

    public init() {}

    public var entryView: AnyView {
        AnyView(AIAssistantView())
    }

    @MainActor
    public func statusSummary() async -> FeatureStatusSummary {
        if AIConfigurationStore.shared.loadConfiguration().hasAPIKey {
            return FeatureStatusSummary(kind: .ready, text: "可用")
        }
        return FeatureStatusSummary(kind: .needsConfiguration, text: "需配置 AI")
    }
}
