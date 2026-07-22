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
            ESHeroHeader(
                eyebrow: "搜索",
                title: "快速打开平台",
                subtitle: "输入关键词，一点即达"
            )

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
                        .frame(width: 52, height: 52)
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
        }
    }

    private var enginesSection: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            ESSectionHeader(
                title: viewModel.selectedCategory.displayName,
                trailing: viewModel.filteredEngines.isEmpty ? nil : "\(viewModel.filteredEngines.count)"
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
    }
}

#Preview {
    EasySearchView(viewModel: SearchViewModel())
}
