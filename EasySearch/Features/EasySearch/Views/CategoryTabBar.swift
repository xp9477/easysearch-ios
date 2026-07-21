import SwiftUI

struct CategoryTabBar: View {
    let categories: [SearchCategory]
    @Binding var selectedCategory: SearchCategory

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ESUI.Space.xs) {
                ForEach(categories, id: \.self) { category in
                    let isSelected = category == selectedCategory
                    Button {
                        selectedCategory = category
                    } label: {
                        Label(category.displayName, systemImage: category.icon)
                            .labelStyle(.titleOnly)
                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                            .padding(.horizontal, ESUI.Space.sm)
                            .padding(.vertical, ESUI.Space.xs)
                            .background(
                                Capsule()
                                    .fill(isSelected ? Color.accentColor.opacity(0.12) : ESUI.fill)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }
}
