import SwiftUI

struct CategoryTabBar: View {
    @Binding var selectedCategory: SearchCategory

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SearchCategory.allCases, id: \.self) { category in
                CategoryTab(
                    category: category,
                    isSelected: selectedCategory == category
                ) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selectedCategory = category
                    }
                }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color(.tertiarySystemFill))
        )
    }
}

struct CategoryTab: View {
    let category: SearchCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: category.icon)
                    .font(.system(size: 12, weight: .semibold))

                Text(category.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.16) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    CategoryTabBar(selectedCategory: .constant(.search))
        .padding()
}
