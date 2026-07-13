import SwiftUI

struct EasySearchView: View {
    @ObservedObject var viewModel: SearchViewModel
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    searchCommandCard
                    engineSection
                }
                .padding(.horizontal, ESUI.screenHorizontalPadding)
                .padding(.top, 14)
            }
            .esBottomTabPadding()
            .esScreenBackground()
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var searchCommandCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            ESSectionHeader(
                title: "搜索内容",
                trailing: viewModel.selectedCategory.displayName
            )

            SearchBar(text: $viewModel.searchQuery, isFocused: $isSearchFieldFocused) {
                if viewModel.performDefaultSearch() {
                    isSearchFieldFocused = false
                } else {
                    isSearchFieldFocused = true
                }
            }

            Picker("分类", selection: $viewModel.selectedCategory) {
                ForEach(SearchCategory.allCases, id: \.self) { category in
                    Text(category.displayName).tag(category)
                }
            }
            .pickerStyle(.segmented)
        }
        .esCard()
    }

    private var engineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ESSectionHeader(
                title: "平台入口",
                trailing: "\(viewModel.filteredEngines.count)"
            )

            EngineGridView(
                engines: viewModel.filteredEngines
            ) { engine in
                if viewModel.hasValidQuery {
                    viewModel.performSearch(engine: engine)
                } else {
                    isSearchFieldFocused = true
                }
            }
        }
    }
}

#Preview {
    EasySearchView(viewModel: SearchViewModel())
}
