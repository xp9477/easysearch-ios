import SwiftUI

struct QingLongEmptyState: View {
    let icon: String
    let title: String
    let description: String?
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        icon: String,
        title: String,
        description: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.description = description?.isEmpty == true ? nil : description
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        if let actionTitle, let action {
            ESEmptyState(
                title: title,
                message: description,
                systemImage: icon,
                actionTitle: actionTitle,
                action: action
            )
        } else {
            ESEmptyState(
                title: title,
                message: description,
                systemImage: icon
            )
        }
    }
}

struct QingLongSearchField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: ESUI.Space.sm) {
            Image(systemName: "magnifyingglass")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .font(.subheadline)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, ESUI.Space.sm)
        .padding(.vertical, ESUI.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                .fill(ESUI.fill)
        )
    }
}

struct QingLongFilterBar<Option: Identifiable & Hashable>: View {
    @Binding var selection: Option
    let options: [Option]
    let title: KeyPath<Option, String>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ESUI.Space.sm) {
                ForEach(options) { option in
                    Button {
                        selection = option
                    } label: {
                        Text(option[keyPath: title])
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selection == option ? Color.accentColor : Color.primary)
                            .padding(.horizontal, ESUI.Space.sm)
                            .padding(.vertical, ESUI.Space.xs)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(selection == option ? Color.accentColor.opacity(0.12) : ESUI.fill)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct QingLongTag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, ESUI.Space.xs)
            .padding(.vertical, ESUI.Space.xxs)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.12))
            )
    }
}

extension View {
    /// QingLong card chrome aligned with ESUI surfaces.
    func cardStyle() -> some View {
        esSurface(cornerRadius: ESUI.cardCornerRadius)
    }
}
