import SwiftUI

struct EngineGridView: View {
    let engines: [SearchEngine]
    let selectedID: String?
    let opensOnTap: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let onSelect: (SearchEngine) -> Void

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: ESUI.Space.xs), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: ESUI.Space.xs) {
            ForEach(engines) { engine in
                Button {
                    onSelect(engine)
                } label: {
                    EngineTile(engine: engine, isSelected: engine.id == selectedID)
                }
                .buttonStyle(ESCardButtonStyle())
                .accessibilityAddTraits(engine.id == selectedID ? .isSelected : [])
                .accessibilityLabel(engine.name)
                .accessibilityHint(opensOnTap ? "在此平台搜索" : "选用此平台并输入关键词")
            }
        }
    }
}

private struct EngineTile: View {
    let engine: SearchEngine
    let isSelected: Bool
    @State private var iconImage: UIImage?

    var body: some View {
        HStack(spacing: ESUI.Space.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: ESUI.Radius.md, style: .continuous)
                    .fill(ESUI.fill)
                    .frame(width: 32, height: 32)

                if let iconImage {
                    Image(uiImage: iconImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: ESUI.Radius.md, style: .continuous))
                } else {
                    Image(systemName: fallbackIcon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Text(engine.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(ESUI.Space.xs)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ESUI.tileCornerRadius, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : ESUI.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ESUI.tileCornerRadius, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
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
