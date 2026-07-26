import SwiftUI

/// AI 助手壳:顶部原生分段切换翻译 / 邮件,内部复用既有模块视图。
public struct AIAssistantView: View {
    private enum Tool: String, CaseIterable, Identifiable {
        case translate
        case email

        var id: String { rawValue }

        var title: String {
            switch self {
            case .translate: return "翻译"
            case .email: return "邮件"
            }
        }
    }

    @State private var selectedTool: Tool = .translate

    public init() {}

    public var body: some View {
        Group {
            switch selectedTool {
            case .translate:
                ImageTranslateView()
            case .email:
                EmailAssistantView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("工具", selection: $selectedTool) {
                    ForEach(Tool.allCases) { tool in
                        Text(tool.title).tag(tool)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
            }
        }
    }
}
