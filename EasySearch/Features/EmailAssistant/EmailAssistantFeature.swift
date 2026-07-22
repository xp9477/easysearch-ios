import SwiftUI

public struct EmailAssistantFeature: AppFeature {
    public var id: String = "email-assistant"
    public var title: String = "邮件助手"
    public var summary: String = "生成、润色与讨论英文邮件。"
    public var iconName: String = "envelope.badge"
    public var color: Color = Color(red: 0.12, green: 0.62, blue: 0.90)
    public var placement: AppFeaturePlacement = .moduleList
    public var group: AppFeatureGroup? = .aiAndContent

    public init() {}

    public var entryView: AnyView {
        AnyView(EmailAssistantView())
    }
}
