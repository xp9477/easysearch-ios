import SwiftUI

struct EasySearchView: View {
    @ObservedObject var viewModel: SearchViewModel
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    searchWorkspace
                    platformSection
                }
                .frame(maxWidth: 760)
                .padding(.horizontal, ESUI.screenHorizontalPadding)
                .padding(.top, 12)
                .frame(maxWidth: .infinity)
            }
            .esBottomTabPadding()
            .esScreenBackground()
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var searchWorkspace: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                SearchBar(text: $viewModel.searchQuery, isFocused: $isSearchFieldFocused) {
                    performDefaultSearch()
                }

                Button {
                    performDefaultSearch()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(viewModel.hasValidQuery ? Color.white : Color.secondary)
                        .frame(width: 52, height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(viewModel.hasValidQuery ? Color.accentColor : Color(.tertiarySystemFill))
                        )
                }
                .buttonStyle(ESCardButtonStyle())
                .disabled(!viewModel.hasValidQuery)
                .accessibilityLabel("使用默认平台搜索")
            }

            CategoryTabBar(selectedCategory: $viewModel.selectedCategory)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                .fill(ESUI.elevatedBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    private var platformSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(viewModel.selectedCategory.displayName)
                    .font(.title3.weight(.bold))

                Spacer(minLength: 8)

                Text("\(viewModel.filteredEngines.count) 个平台")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }

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

    private func performDefaultSearch() {
        if viewModel.performDefaultSearch() {
            isSearchFieldFocused = false
        } else {
            isSearchFieldFocused = true
        }
    }
}

#Preview {
    EasySearchView(viewModel: SearchViewModel())
}
