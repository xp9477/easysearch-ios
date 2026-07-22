import SwiftUI

struct EasySearchView: View {
    @ObservedObject var viewModel: SearchViewModel
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ESUI.Space.md) {
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
                                .font(.body.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 48, height: 48)
                                .background(ESBrandGradient.fill(cornerRadius: 14))
                        }
                        .buttonStyle(ESCardButtonStyle())
                        .disabled(!viewModel.hasValidQuery)
                        .opacity(viewModel.hasValidQuery ? 1 : 0.45)
                        .accessibilityLabel("默认搜索")
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
                .padding(.horizontal, ESUI.screenHorizontalPadding)
                .padding(.top, ESUI.Space.sm)
                .padding(.bottom, ESUI.Space.lg)
            }
            .esBottomTabPadding()
            .esScreenBackground()
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

#Preview {
    EasySearchView(viewModel: SearchViewModel())
}
