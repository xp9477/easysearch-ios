import SwiftUI

struct SearchBar: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var onSubmit: () -> Void

    var body: some View {
        HStack(spacing: ESUI.Space.sm) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.semibold))
                .foregroundStyle(isFocused.wrappedValue ? ESUI.brandStart : .secondary)
                .accessibilityHidden(true)

            TextField("输入搜索内容", text: $text)
                .font(.body.weight(.medium))
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
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(
            RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                .fill(ESUI.surface)
                .shadow(color: Color.black.opacity(0.04), radius: 8, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                .stroke(
                    isFocused.wrappedValue
                        ? ESUI.brandStart.opacity(0.45)
                        : Color.primary.opacity(0.05),
                    lineWidth: 1
                )
        )
        .animation(.easeOut(duration: 0.15), value: isFocused.wrappedValue)
        .accessibilityElement(children: .contain)
    }
}
