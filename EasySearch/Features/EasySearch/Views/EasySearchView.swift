import SwiftUI

struct EasySearchView: View {
    @ObservedObject var viewModel: SearchViewModel
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ESUI.sectionSpacing) {
                    searchSection
                    enginesSection
                }
                .padding(.horizontal, ESUI.screenHorizontalPadding)
                .padding(.top, ESUI.Space.md)
                .padding(.bottom, ESUI.Space.lg)
            }
            .esBottomTabPadding()
            .esScreenBackground()
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.large)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            ESSectionHeader(
                title: "快速搜索",
                subtitle: "输入关键词，一键打开目标平台"
            )

            SearchBar(
                text: $viewModel.searchQuery,
                isFocused: $isSearchFieldFocused,
                onSubmit: {
                    _ = viewModel.performDefaultSearch()
                }
            )

            CategoryTabBar(
                categories: SearchCategory.allCases,
                selectedCategory: $viewModel.selectedCategory
            )
        }
    }

    private var enginesSection: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            ESSectionHeader(
                title: "平台入口",
                trailing: viewModel.filteredEngines.isEmpty ? nil : "\(viewModel.filteredEngines.count)"
            )

            if viewModel.filteredEngines.isEmpty {
                ESEmptyState(
                    title: "暂无可用平台",
                    message: viewModel.searchEngines.isEmpty
                        ? "搜索引擎配置尚未加载，请稍后重试。"
                        : "当前分类下没有匹配的平台。",
                    systemImage: "globe"
                )
                .esCard()
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
    }
}

#Preview {
    EasySearchView(viewModel: SearchViewModel())
}
