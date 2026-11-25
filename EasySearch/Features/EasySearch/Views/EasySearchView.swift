import SwiftUI
import UIKit

struct EasySearchView: View {
    @ObservedObject var viewModel: SearchViewModel
    @EnvironmentObject private var navigationState: AppNavigationState
    @FocusState private var isSearchFieldFocused: Bool
    @State private var clipboardHasText = false
    @State private var isOpeningSearch = false
    @State private var failedPlatform: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ESUI.Space.xl) {
                    SearchComposer(
                        text: $viewModel.searchQuery,
                        isFocused: $isSearchFieldFocused,
                        showsClipboardAction: clipboardHasText,
                        platformName: viewModel.defaultSearchEngine?.name,
                        hasQuery: viewModel.hasValidQuery,
                        isOpening: isOpeningSearch,
                        onSubmit: submitDefaultSearch,
                        onPaste: pasteClipboard
                    )

                    VStack(alignment: .leading, spacing: ESUI.Space.sm) {
                        Text("搜索平台")
                            .font(.title3.bold())
                            .accessibilityAddTraits(.isHeader)
                        CategoryTabBar(categories: SearchCategory.allCases, selectedCategory: $viewModel.selectedCategory)
                        if viewModel.filteredEngines.isEmpty {
                            ESEmptyState(title: "这个分类暂无平台", systemImage: "globe")
                        } else {
                            EngineGridView(
                                engines: viewModel.filteredEngines,
                                selectedID: viewModel.defaultSearchEngine?.id,
                                opensOnTap: viewModel.hasValidQuery,
                                onSelect: selectPlatform
                            )
                            .disabled(isOpeningSearch)
                        }
                    }
                }
                .padding(.horizontal, ESUI.Space.lg)
                .padding(.top, ESUI.Space.sm)
                .padding(.bottom, ESUI.Space.lg)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .esScreenBackground()
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.large)
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            refreshClipboardState()
            consumePendingQuery()
        }
        .onChange(of: navigationState.searchActivationToken) {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                guard navigationState.selectedTab == .search else { return }
                isSearchFieldFocused = true
            }
        }
        .onChange(of: navigationState.pendingSearchQuery) { consumePendingQuery() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            refreshClipboardState()
        }
        .alert("无法打开搜索", isPresented: Binding(
            get: { failedPlatform != nil },
            set: { if !$0 { failedPlatform = nil } }
        )) {
            Button("好", role: .cancel) { failedPlatform = nil }
        } message: {
            Text("无法打开\(failedPlatform ?? "所选平台")。搜索词已保留，你可以换个平台再试。")
        }
    }

    private func consumePendingQuery() {
        guard let query = navigationState.pendingSearchQuery else { return }
        viewModel.searchQuery = query
        navigationState.pendingSearchQuery = nil
    }

    private func pasteClipboard() {
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            clipboardHasText = false
            return
        }
        viewModel.searchQuery = text
        isSearchFieldFocused = true
    }

    private func selectPlatform(_ engine: SearchEngine) {
        viewModel.selectPlatform(engine)
        if viewModel.hasValidQuery {
            openSearch(engine)
        } else {
            isSearchFieldFocused = true
        }
    }

    private func submitDefaultSearch() {
        guard let engine = viewModel.defaultSearchEngine else { return }
        guard viewModel.hasValidQuery else {
            isSearchFieldFocused = true
            return
        }
        openSearch(engine)
    }

    private func openSearch(_ engine: SearchEngine) {
        guard !isOpeningSearch else { return }
        isOpeningSearch = true
        isSearchFieldFocused = false
        Task {
            defer { isOpeningSearch = false }
            if !(await viewModel.performSearch(engine: engine)) { failedPlatform = engine.name }
        }
    }

    private func refreshClipboardState() {
        // hasStrings does not read the contents or trigger the paste prompt.
        clipboardHasText = UIPasteboard.general.hasStrings
    }
}

private struct SearchComposer: View {
    @Binding var text: String
    let isFocused: FocusState<Bool>.Binding
    let showsClipboardAction: Bool
    let platformName: String?
    let hasQuery: Bool
    let isOpening: Bool
    let onSubmit: () -> Void
    let onPaste: () -> Void

    var body: some View {
        VStack(spacing: ESUI.Space.xs) {
            SearchBar(
                text: $text, isFocused: isFocused, showsClipboardAction: showsClipboardAction,
                onSubmit: onSubmit, onPasteClipboard: onPaste
            )
            if let platformName {
                Button(action: onSubmit) {
                    HStack(spacing: ESUI.Space.xs) {
                        Text("在\(platformName)搜索").fontWeight(.semibold)
                        Image(systemName: "arrow.up.right").font(.footnote.weight(.semibold)).accessibilityHidden(true)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(hasQuery ? Color.white : Color.accentColor)
                .background(hasQuery ? ESUI.primaryActionFill : Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: ESUI.Radius.md))
                .disabled(isOpening)
                .accessibilityHint(hasQuery ? "打开所选搜索平台" : "聚焦关键词输入框")
            }
        }
        .padding(ESUI.Space.sm)
        .background(ESUI.surface, in: RoundedRectangle(cornerRadius: ESUI.Radius.xl))
    }
}

#Preview {
    EasySearchView(viewModel: SearchViewModel())
        .environmentObject(AppNavigationState())
}
