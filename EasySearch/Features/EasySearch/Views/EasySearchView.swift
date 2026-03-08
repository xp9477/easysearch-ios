import SwiftUI

struct EasySearchView: View {
    @ObservedObject var viewModel: SearchViewModel
    @FocusState private var isSearchFieldFocused: Bool
    @State private var didAutofocusOnLaunch = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SearchBar(text: $viewModel.searchQuery, isFocused: $isSearchFieldFocused)

                    Picker("分类", selection: $viewModel.selectedCategory) {
                        ForEach(SearchCategory.allCases, id: \.self) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                    .pickerStyle(.segmented)

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
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.large)
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                autofocusSearchFieldIfNeeded()
            }
        }
    }

    private func autofocusSearchFieldIfNeeded() {
        guard !didAutofocusOnLaunch else { return }
        didAutofocusOnLaunch = true

        DispatchQueue.main.async {
            isSearchFieldFocused = true
        }
    }
}

#Preview {
    EasySearchView(viewModel: SearchViewModel())
}
