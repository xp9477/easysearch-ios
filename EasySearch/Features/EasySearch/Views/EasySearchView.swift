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
                                showsClipboardAction: clipboardHasText,
                                onSubmit: { submitDefaultSearch() },
                                onPasteClipboard: { pasteClipboard() }
                            )

                            Button {
                                submitDefaultSearch()
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

                    if !viewModel.history.isEmpty && !viewModel.hasValidQuery {
                        historySection
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
            .animation(ESMotion.content, value: viewModel.selectedCategory)
            .animation(ESMotion.content, value: viewModel.hasValidQuery)
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

    private func pasteClipboard() {
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            clipboardHasText = false
            ESHaptics.warning()
            return
        }

        withAnimation(ESMotion.quick) {
            viewModel.searchQuery = text
        }
        isSearchFieldFocused = true
        ESHaptics.tap()
    }

    private func submitDefaultSearch() {
        if viewModel.performDefaultSearch() {
            ESHaptics.tap()
        } else {
            ESHaptics.warning()
        }
    }

    private func refreshClipboardState() {
        // hasStrings 不读取内容,不触发系统粘贴提示。
        let hasStrings = UIPasteboard.general.hasStrings
        withAnimation(ESMotion.quick) {
            clipboardHasText = hasStrings
        }
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
                    ESHaptics.tap()
                    withAnimation(ESMotion.content) {
                        viewModel.clearHistory()
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ESUI.Space.xs) {
                    ForEach(viewModel.history.prefix(8)) { entry in
                        Button {
                            ESHaptics.tap()
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

#Preview {
    EasySearchView(viewModel: SearchViewModel())
        .environmentObject(AppNavigationState())
}
