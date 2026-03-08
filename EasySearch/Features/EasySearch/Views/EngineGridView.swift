import SwiftUI

/// 搜索引擎按钮网格
struct EngineGridView: View {
    let engines: [SearchEngine]
    let onTap: (SearchEngine) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)
    ]

    var body: some View {
        if engines.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "square.grid.2x2")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                Text("暂无平台")
                    .font(.headline)

                Text("这个分类下还没有可用入口。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        } else {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(engines) { engine in
                    EngineButton(engine: engine) {
                        onTap(engine)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.3), value: engines)
        }
    }
}

/// 单个搜索引擎按钮
struct EngineButton: View {
    let engine: SearchEngine
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 28, height: 28)

                    Image(systemName: engine.symbolName)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }

                Text(engine.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(.separator).opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(EngineButtonStyle())
    }
}

/// 引擎按钮的自定义按压样式
struct EngineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

private extension SearchEngine {
    var symbolName: String {
        switch category ?? SearchCategory.search.rawValue {
        case SearchCategory.ai.rawValue:
            return "sparkles"
        case SearchCategory.entertainment.rawValue:
            return "play.rectangle.fill"
        case SearchCategory.shopping.rawValue:
            return "bag.fill"
        default:
            return urlScheme == nil ? "magnifyingglass" : "app.fill"
        }
    }
}

#Preview {
    EngineGridView(
        engines: [
            SearchEngine(name: "百度", url: "https://baidu.com", urlScheme: nil, category: "搜索"),
            SearchEngine(name: "Google", url: "https://google.com", urlScheme: nil, category: "搜索"),
            SearchEngine(name: "知乎", url: "https://zhihu.com", urlScheme: nil, category: "搜索"),
        ],
        onTap: { _ in }
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}
