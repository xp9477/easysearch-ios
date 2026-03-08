import SwiftUI

/// 自定义搜索框组件
struct SearchBar: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField("输入要搜索的内容", text: $text)
                .font(.body)
                .focused(isFocused)
                .submitLabel(.done)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !text.isEmpty {
                Button {
                    text = ""
                    isFocused.wrappedValue = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isFocused.wrappedValue ? Color.accentColor.opacity(0.35) : Color(.separator).opacity(0.12), lineWidth: 1)
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
