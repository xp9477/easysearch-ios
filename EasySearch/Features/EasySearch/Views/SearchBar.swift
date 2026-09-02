import SwiftUI

struct SearchBar: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var showsClipboardAction: Bool = false
    var onSubmit: () -> Void
    var onPasteClipboard: () -> Void = {}

    var body: some View {
        HStack(spacing: ESUI.Space.sm) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.medium))
                .foregroundStyle(isFocused.wrappedValue ? Color.accentColor : .secondary)
                .accessibilityHidden(true)

            TextField("输入搜索内容", text: $text)
                .font(.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .submitLabel(.search)
                .focused(isFocused)
                .onSubmit(onSubmit)

            if !text.isEmpty {
                Button {
                    text = ""
                    ESHaptics.tap()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(ESMotion.pop)
                .accessibilityLabel("清除")
            } else if showsClipboardAction {
                Button(action: onPasteClipboard) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(ESMotion.pop)
                .accessibilityLabel("粘贴剪贴板内容")
            }
        }
        .padding(.horizontal, ESUI.Space.md)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(
            RoundedRectangle(cornerRadius: ESUI.Radius.md, style: .continuous)
                .fill(ESUI.fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ESUI.Radius.md, style: .continuous)
                .stroke(
                    isFocused.wrappedValue ? Color.accentColor.opacity(0.4) : Color.clear,
                    lineWidth: 1
                )
        )
        .animation(ESMotion.quick, value: text.isEmpty)
        .animation(ESMotion.quick, value: isFocused.wrappedValue)
        .accessibilityElement(children: .contain)
    }
}
