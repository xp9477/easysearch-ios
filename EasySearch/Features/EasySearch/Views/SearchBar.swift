import SwiftUI

struct SearchBar: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var onSubmit: () -> Void

    var body: some View {
        HStack(spacing: ESUI.Space.sm) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.medium))
                .foregroundStyle(isFocused.wrappedValue ? Color.accentColor : .secondary)
                .accessibilityHidden(true)

            TextField("输入搜索内容", text: $text)
                .font(.body)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .submitLabel(.search)
                .focused(isFocused)
                .onSubmit(onSubmit)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除")
            }
        }
        .padding(.horizontal, ESUI.Space.md)
        .frame(maxWidth: .infinity, minHeight: 48)
        .glassEffect(.regular, in: .capsule)
        .animation(.easeOut(duration: 0.15), value: isFocused.wrappedValue)
        .accessibilityElement(children: .contain)
    }
}
