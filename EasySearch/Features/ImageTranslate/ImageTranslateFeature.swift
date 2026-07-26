import SwiftUI

public struct ImageTranslateFeature: AppFeature {
    public var id: String = "image-translate"
    public var title: String = "翻译"
    public var summary: String = "文本与图片翻译，拍照选图粘贴即用。"
    public var iconName: String = "globe"
    public var color: Color = Color(red: 0.56, green: 0.35, blue: 0.98)
    public var placement: AppFeaturePlacement = .moduleList
    public var group: AppFeatureGroup? = .aiAndContent

    public init() {}

    public var entryView: AnyView {
        AnyView(ImageTranslateView())
    }

    @MainActor
    public func statusSummary() async -> FeatureStatusSummary {
        if AIConfigurationStore.shared.loadConfiguration().hasAPIKey {
            return FeatureStatusSummary(kind: .ready, text: "可用")
        }
        return FeatureStatusSummary(kind: .needsConfiguration, text: "需配置 AI")
    }

}
