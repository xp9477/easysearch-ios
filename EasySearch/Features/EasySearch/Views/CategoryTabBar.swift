import SwiftUI

struct CategoryTabBar: View {
    let categories: [SearchCategory]
    @Binding var selectedCategory: SearchCategory

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: ESUI.Space.xs) {
                HStack(spacing: ESUI.Space.xs) {
                    ForEach(categories, id: \.self) { category in
                        let isSelected = category == selectedCategory
                        Button {
                            selectedCategory = category
                        } label: {
                            Text(category.displayName)
                                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? Color.white : .primary)
                                .padding(.horizontal, ESUI.Space.sm + 2)
                                .padding(.vertical, ESUI.Space.xs)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(
                            isSelected ? .regular.tint(.blue).interactive() : .regular.interactive(),
                            in: .capsule
                        )
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}
