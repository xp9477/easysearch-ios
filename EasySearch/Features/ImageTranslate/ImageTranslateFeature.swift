import SwiftUI

public struct ImageTranslateFeature: AppFeature {
    public var id: String = "image-translate"
    public var title: String = "翻译"
    public var summary: String = "支持文本翻译和图片翻译，可拍照、选图、粘贴截图或直接输入文本，再用 AI 模型生成结果。"
    public var iconName: String = "globe"
    public var color: Color = .cyan
    public var placement: AppFeaturePlacement = .moduleList

    public init() {}

    public var entryView: AnyView {
        AnyView(ImageTranslateView())
    }
}
