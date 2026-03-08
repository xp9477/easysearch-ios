import SwiftUI

/// 主界面 - EasySearch
struct EasySearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @State private var showSettings = false

    var body: some View {
        ZStack {
            // 背景渐变
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color.accentColor.opacity(0.05),
                    Color.accentColor.opacity(0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // MARK: - Header
                    headerView
                        .padding(.top, 20)

                    // MARK: - Search Bar
                    SearchBar(text: $viewModel.searchQuery)
                        .padding(.horizontal)

                    // MARK: - Category Tabs
                    CategoryTabBar(selectedCategory: $viewModel.selectedCategory)
                        .padding(.horizontal)

                    // MARK: - Engine Grid
                    EngineGridView(
                        engines: viewModel.filteredEngines,
                        isEnabled: viewModel.hasValidQuery
                    ) { engine in
                        viewModel.performSearch(engine: engine)
                    }
                    .padding(.horizontal)

                    // MARK: - Footer
                    footerView
                        .padding(.top, 20)
                        .padding(.bottom, 40)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .overlay(alignment: .topTrailing) {
            settingsButton
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(viewModel: viewModel)
        }
    }

    // MARK: - Sub Views

    private var headerView: some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                Text("Easy")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("Search")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
            }

            Text("一键搜索多个平台")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var settingsButton: some View {
        Button {
            showSettings = true
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .padding(12)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                )
        }
        .padding(.trailing, 16)
        .padding(.top, 8)
    }

    private var footerView: some View {
        Text("Search across multiple platforms with one click")
            .font(.footnote)
            .foregroundStyle(.tertiary)
    }
}

#Preview {
    EasySearchView()
}
