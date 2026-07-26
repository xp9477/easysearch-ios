import SwiftUI
import UIKit

struct EasySearchView: View {
    @ObservedObject var viewModel: SearchViewModel
    @EnvironmentObject private var navigationState: AppNavigationState
    @FocusState private var isSearchFieldFocused: Bool
    @State private var clipboardHasText = false
    @State private var didAutoFocus = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ESUI.Space.md) {
                    GlassEffectContainer(spacing: ESUI.Space.sm) {
                        HStack(spacing: ESUI.Space.sm) {
                            SearchBar(
                                text: $viewModel.searchQuery,
                                isFocused: $isSearchFieldFocused,
                                onSubmit: { _ = viewModel.performDefaultSearch() }
                            )

                            Button {
                                _ = viewModel.performDefaultSearch()
                            } label: {
                                Image(systemName: "arrow.right")
                                    .font(.body.weight(.semibold))
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.glassProminent)
                            .disabled(!viewModel.hasValidQuery)
                            .accessibilityLabel("默认搜索")
                        }
                    }

                    if clipboardHasText && !viewModel.hasValidQuery {
                        clipboardSuggestionChip
                    }

                    if !viewModel.history.isEmpty && !viewModel.hasValidQuery {
                        historySection
                    }

                    if !viewModel.frequentEngines.isEmpty {
                        frequentEnginesRow
                    }

                    CategoryTabBar(
                        categories: SearchCategory.allCases,
                        selectedCategory: $viewModel.selectedCategory
                    )

                    if viewModel.filteredEngines.isEmpty {
                        ESEmptyState(
                            title: "暂无可用平台",
                            message: viewModel.searchEngines.isEmpty
                                ? "搜索引擎配置尚未加载。"
                                : "当前分类下没有匹配平台。",
                            systemImage: "globe"
                        )
                    } else {
                        EngineGridView(
                            engines: viewModel.filteredEngines,
                            isEnabled: viewModel.hasValidQuery,
                            onSelect: { engine in
                                viewModel.performSearch(engine: engine)
                            }
                        )
                    }
                }
                .padding(.horizontal, ESUI.screenHorizontalPadding)
                .padding(.top, ESUI.Space.sm)
                .padding(.bottom, ESUI.Space.lg)
            }
            .esScreenBackground()
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.large)
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            refreshClipboardState()
            autoFocusOnColdLaunch()
        }
        .onChange(of: navigationState.searchActivationToken) { _ in
            focusSearchField()
        }
        .onChange(of: navigationState.pendingSearchQuery) { query in
            guard let query else { return }
            viewModel.searchQuery = query
            navigationState.pendingSearchQuery = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            refreshClipboardState()
        }
    }

    // MARK: - Clipboard

    private var clipboardSuggestionChip: some View {
        Button {
            if let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                viewModel.searchQuery = text
                isSearchFieldFocused = true
            }
            clipboardHasText = false
        } label: {
            HStack(spacing: ESUI.Space.xs) {
                Image(systemName: "doc.on.clipboard")
                    .font(.caption.weight(.semibold))
                Text("搜索剪贴板内容")
                    .font(.subheadline)
                Image(systemName: "arrow.up.left")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, ESUI.Space.sm)
            .padding(.vertical, ESUI.Space.xs)
        }
        .buttonStyle(.glass)
        .accessibilityHint("将剪贴板文本填入搜索框")
    }

    private func refreshClipboardState() {
        // hasStrings 不读取内容,不触发系统粘贴提示。
        clipboardHasText = UIPasteboard.general.hasStrings
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.xs) {
            HStack {
                Text("最近搜索")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("清空") {
                    viewModel.clearHistory()
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ESUI.Space.xs) {
                    ForEach(viewModel.history.prefix(8)) { entry in
                        Button {
                            viewModel.searchFromHistory(entry)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(entry.query)
                                    .font(.subheadline)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, ESUI.Space.sm)
                            .padding(.vertical, ESUI.Space.xs)
                            .background(Capsule().fill(ESUI.fill))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("删除", role: .destructive) {
                                viewModel.removeHistory(entry)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Frequent Engines

    private var frequentEnginesRow: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.xs) {
            Text("常用")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ESUI.Space.sm) {
                    ForEach(viewModel.frequentEngines) { engine in
                        Button {
                            viewModel.performSearch(engine: engine)
                        } label: {
                            FrequentEngineTile(engine: engine)
                                .opacity(viewModel.hasValidQuery ? 1 : 0.5)
                        }
                        .buttonStyle(ESCardButtonStyle())
                        .disabled(!viewModel.hasValidQuery)
                        .accessibilityLabel(engine.name)
                    }
                }
            }
        }
    }

    // MARK: - Focus

    private func autoFocusOnColdLaunch() {
        guard !didAutoFocus else { return }
        didAutoFocus = true
        guard navigationState.selectedTab == .search else { return }
        focusSearchField()
    }

    private func focusSearchField() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            isSearchFieldFocused = true
        }
    }
}

private struct FrequentEngineTile: View {
    let engine: SearchEngine
    @State private var iconImage: UIImage?

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(ESUI.fill)
                    .frame(width: 54, height: 54)

                if let iconImage {
                    Image(uiImage: iconImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 54, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Text(engine.name)
                .font(.caption2)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: 58)
        }
        .task(id: engine.faviconURL) {
            guard let url = engine.faviconURL else { return }
            if let data = try? await SearchEngineIconCache.shared.data(for: url),
               let image = UIImage(data: data) {
                iconImage = image
            }
        }
    }
}

#Preview {
    EasySearchView(viewModel: SearchViewModel())
        .environmentObject(AppNavigationState())
}
