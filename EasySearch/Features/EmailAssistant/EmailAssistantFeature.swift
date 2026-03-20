import SwiftUI

public struct EmailAssistantFeature: AppFeature {
    public var id: String = "email-assistant"
    public var title: String = "邮件助手"
    public var summary: String = "用 DeepSeek 生成、润色和讨论英文邮件，支持来信文本和截图 OCR。"
    public var iconName: String = "envelope.badge"
    public var color: Color = .blue
    public var placement: AppFeaturePlacement = .moduleList

    public init() {}

    public var entryView: AnyView {
        AnyView(EmailAssistantView())
    }
}
