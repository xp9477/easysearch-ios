import SwiftUI

/// 分类切换:系统分段控件质感 —— 灰色轨道 + 滑动白色胶囊。
struct CategoryTabBar: View {
    let categories: [SearchCategory]
    @Binding var selectedCategory: SearchCategory

    @Namespace private var indicatorNamespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(categories, id: \.self) { category in
                let isSelected = category == selectedCategory

                Button {
                    guard !isSelected else { return }
                    ESHaptics.selection()
                    withAnimation(ESMotion.quick) {
                        selectedCategory = category
                    }
                } label: {
                    Text(category.displayName)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background {
                            if isSelected {
                                Capsule(style: .continuous)
                                    .fill(Color(.systemBackground))
                                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                                    .matchedGeometryEffect(id: "category-indicator", in: indicatorNamespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(
            Capsule(style: .continuous)
                .fill(Color(.tertiarySystemFill))
        )
    }
}
