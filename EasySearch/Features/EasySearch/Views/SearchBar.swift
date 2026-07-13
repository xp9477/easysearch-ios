import SwiftUI

/// 自定义搜索框组件
struct SearchBar: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.semibold))
                .foregroundStyle(isFocused.wrappedValue ? Color.accentColor : .secondary)

            TextField("输入要搜索的内容", text: $text)
                .font(.body)
                .focused(isFocused)
                .submitLabel(.done)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit(onSubmit)

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
        .frame(minHeight: 54)
        .background(
            RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                .stroke(isFocused.wrappedValue ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: isFocused.wrappedValue ? Color.accentColor.opacity(0.08) : .clear, radius: 12, x: 0, y: 6)
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
