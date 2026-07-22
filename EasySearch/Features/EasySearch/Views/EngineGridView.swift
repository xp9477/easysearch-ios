import SwiftUI

struct EngineGridView: View {
    let engines: [SearchEngine]
    var isEnabled: Bool = true
    let onSelect: (SearchEngine) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: ESUI.Space.sm),
        GridItem(.flexible(), spacing: ESUI.Space.sm)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: ESUI.Space.sm) {
            ForEach(engines) { engine in
                Button {
                    onSelect(engine)
                } label: {
                    EngineTile(engine: engine)
                        .opacity(isEnabled ? 1 : 0.45)
                }
                .buttonStyle(ESCardButtonStyle())
                .disabled(!isEnabled)
                .accessibilityLabel(engine.name)
                .accessibilityHint(isEnabled ? "打开搜索" : "请先输入搜索内容")
            }
        }
    }
}

private struct EngineTile: View {
    let engine: SearchEngine
    @State private var iconImage: UIImage?

    var body: some View {
        HStack(spacing: ESUI.Space.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                categoryColor.opacity(0.95),
                                categoryColor.opacity(0.65)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 42, height: 42)

                if let iconImage {
                    Image(uiImage: iconImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 42, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Image(systemName: fallbackIcon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(engine.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !engine.displayHost.isEmpty {
                    Text(engine.displayHost)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(ESUI.Space.sm)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                .fill(ESUI.surface)
                .shadow(color: Color.black.opacity(0.04), radius: 8, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                .stroke(categoryColor.opacity(0.18), lineWidth: 1)
        )
        .task(id: engine.faviconURL) {
            await loadIcon()
        }
    }

    private var fallbackIcon: String {
        if let category = engine.category,
           let searchCategory = SearchCategory(rawValue: category) {
            return searchCategory.icon
        }
        return "globe"
    }

    private var categoryColor: Color {
        switch engine.category {
        case SearchCategory.ai.rawValue: return Color(red: 0.56, green: 0.35, blue: 0.98)
        case SearchCategory.entertainment.rawValue: return Color(red: 0.95, green: 0.40, blue: 0.55)
        case SearchCategory.shopping.rawValue: return Color(red: 0.98, green: 0.58, blue: 0.18)
        default: return ESUI.brandStart
        }
    }

    private func loadIcon() async {
        guard let url = engine.faviconURL else {
            iconImage = nil
            return
        }
        do {
            let data = try await SearchEngineIconCache.shared.data(for: url)
            if let image = UIImage(data: data) {
                iconImage = image
            }
        } catch {
            iconImage = nil
        }
    }
}
