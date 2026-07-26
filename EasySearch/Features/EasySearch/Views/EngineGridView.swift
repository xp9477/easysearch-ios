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
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(ESUI.fill)
                    .frame(width: 40, height: 40)

                if let iconImage {
                    Image(uiImage: iconImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    Image(systemName: fallbackIcon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
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
            RoundedRectangle(cornerRadius: ESUI.tileCornerRadius, style: .continuous)
                .fill(ESUI.surface)
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
