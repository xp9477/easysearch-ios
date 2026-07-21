import SwiftUI

struct EngineGridView: View {
    let engines: [SearchEngine]
    var isEnabled: Bool = true
    let onSelect: (SearchEngine) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 96, maximum: 140), spacing: ESUI.Space.sm)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: ESUI.Space.sm) {
            ForEach(engines) { engine in
                Button {
                    onSelect(engine)
                } label: {
                    VStack(spacing: ESUI.Space.xs) {
                        ESFeatureIcon(
                            systemName: iconName(for: engine),
                            color: .accentColor,
                            size: 44
                        )
                        Text(engine.name)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, ESUI.Space.sm)
                    .padding(.horizontal, ESUI.Space.xs)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                            .fill(ESUI.surface)
                    )
                    .opacity(isEnabled ? 1 : 0.45)
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
                .accessibilityLabel(engine.name)
                .accessibilityHint(isEnabled ? "打开搜索" : "请先输入搜索内容")
            }
        }
    }

    private func iconName(for engine: SearchEngine) -> String {
        if let category = engine.category,
           let searchCategory = SearchCategory(rawValue: category) {
            return searchCategory.icon
        }
        return "globe"
    }
}
