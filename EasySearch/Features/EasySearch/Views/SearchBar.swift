import SwiftUI

struct SearchBar: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isFocused.wrappedValue ? Color.accentColor : .secondary)

            TextField("输入要搜索的内容", text: $text)
                .font(.body.weight(.medium))
                .focused(isFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit(onSubmit)

            if !text.isEmpty {
                Button {
                    text = ""
                    isFocused.wrappedValue = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索内容")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.tertiarySystemFill))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isFocused.wrappedValue ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.05), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.15), value: isFocused.wrappedValue)
        .animation(.easeInOut(duration: 0.15), value: text.isEmpty)
    }
}

#Preview {
    PreviewSearchBar()
        .padding()
        .background(Color(.systemGroupedBackground))
}

private struct PreviewSearchBar: View {
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        SearchBar(text: $text, isFocused: $isFocused)
    }
}
