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
                        Text(category.displayName)
                            .font(.subheadline.weight(isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? Color.white : .secondary)
                            .padding(.horizontal, ESUI.Space.sm + 2)
                            .padding(.vertical, ESUI.Space.xs)
                            .background {
                                if isSelected {
                                    Capsule().fill(ESBrandGradient.linear)
                                } else {
                                    Capsule().fill(ESUI.fill)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }
}
