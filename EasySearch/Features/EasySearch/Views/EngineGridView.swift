import SwiftUI
import UIKit

struct EngineGridView: View {
    let engines: [SearchEngine]
    let onTap: (SearchEngine) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 156, maximum: 240), spacing: 10)
    ]

    var body: some View {
        if engines.isEmpty {
            ESEmptyState(
                title: "暂无平台",
                message: "这个分类下还没有可用入口。",
                systemImage: "square.grid.2x2",
                minHeight: 160
            )
        } else {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(engines) { engine in
                    EngineButton(engine: engine) {
                        onTap(engine)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: engines)
        }
    }
}

struct EngineButton: View {
    let engine: SearchEngine
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                EngineFaviconView(engine: engine)

                VStack(alignment: .leading, spacing: 3) {
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

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(ESUI.elevatedBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
        }
        .buttonStyle(ESCardButtonStyle())
        .accessibilityLabel("使用 \(engine.name) 搜索")
    }
}

private struct EngineFaviconView: View {
    private enum Phase {
        case loading
        case success(UIImage)
        case failure
    }

    let engine: SearchEngine

    @State private var phase: Phase = .loading

    var body: some View {
        Group {
            switch phase {
            case let .success(image):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(6)
            case .loading:
                if engine.faviconURL != nil {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    fallbackIcon
                }
            case .failure:
                fallbackIcon
            }
        }
        .frame(width: 42, height: 42)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .accessibilityHidden(true)
        .task(id: engine.faviconURL) {
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        phase = .loading

        guard let url = engine.faviconURL else {
            phase = .failure
            return
        }

        do {
            let data = try await SearchEngineIconCache.shared.data(for: url)
            try Task.checkCancellation()
            guard let loadedImage = UIImage(data: data) else {
                phase = .failure
                return
            }
            phase = .success(loadedImage)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failure
        }
    }

    private var fallbackIcon: some View {
        Image(systemName: engine.symbolName)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Color.accentColor)
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
