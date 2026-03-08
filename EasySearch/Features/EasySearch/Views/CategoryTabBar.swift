import SwiftUI

/// 分类标签栏组件
struct CategoryTabBar: View {
    @Binding var selectedCategory: SearchCategory

    var body: some View {
        HStack(spacing: 0) {
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
        .padding(.horizontal, 4)
    }
}

/// 单个分类 Tab
struct CategoryTab: View {
    let category: SearchCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: category.icon)
                        .font(.system(size: 13, weight: .medium))
                    Text(category.displayName)
                        .font(.system(size: 15, weight: .medium))
                }
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                // 选中指示器
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isSelected ? Color.accentColor : .clear)
                    .frame(height: 3)
                    .padding(.horizontal, 8)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

#Preview {
    CategoryTabBar(selectedCategory: .constant(.search))
        .padding()
}
