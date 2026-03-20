import SwiftUI

public struct ImageTranslateFeature: AppFeature {
    public var id: String = "image-translate"
    public var title: String = "截图翻译"
    public var summary: String = "支持拍照、选图或粘贴截图，先 OCR 再用 DeepSeek 翻译，并可继续追问优化。"
    public var iconName: String = "text.viewfinder"
    public var color: Color = .cyan
    public var placement: AppFeaturePlacement = .moduleList

    public init() {}

    public var entryView: AnyView {
        AnyView(ImageTranslateView())
    }
}
