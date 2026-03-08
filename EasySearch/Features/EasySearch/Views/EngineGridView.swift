import SwiftUI

/// 搜索引擎按钮网格
struct EngineGridView: View {
    let engines: [SearchEngine]
    let isEnabled: Bool
    let onTap: (SearchEngine) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        if engines.isEmpty {
            emptyState
        } else {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(engines) { engine in
                    EngineButton(engine: engine, isEnabled: isEnabled) {
                        onTap(engine)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.3), value: engines)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.quaternary)
            Text("该分类下暂无搜索引擎")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

/// 单个搜索引擎按钮
struct EngineButton: View {
    let engine: SearchEngine
    let isEnabled: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Text(engine.name)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isEnabled ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
                        .shadow(color: .black.opacity(0.02), radius: 1, x: 0, y: 0)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.separator).opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(EngineButtonStyle())
        .disabled(!isEnabled)
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

#Preview {
    EngineGridView(
        engines: [
            SearchEngine(name: "百度", url: "https://baidu.com", urlScheme: nil, category: "搜索"),
            SearchEngine(name: "Google", url: "https://google.com", urlScheme: nil, category: "搜索"),
            SearchEngine(name: "知乎", url: "https://zhihu.com", urlScheme: nil, category: "搜索"),
        ],
        isEnabled: true,
        onTap: { _ in }
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}
