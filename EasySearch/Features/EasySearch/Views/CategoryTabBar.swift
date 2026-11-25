import SwiftUI

/// 分类切换:系统分段控件质感 —— 灰色轨道 + 滑动白色/深色胶囊。
struct CategoryTabBar: View {
    let categories: [SearchCategory]
    @Binding var selectedCategory: SearchCategory

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Namespace private var indicatorNamespace

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        layout {
            ForEach(categories, id: \.self) { category in
                let isSelected = category == selectedCategory

                Button {
                    guard !isSelected else { return }
                    ESHaptics.selection()
                    withAnimation(reduceMotion ? nil : ESMotion.quick) {
                        selectedCategory = category
                    }
                } label: {
                    Text(category.displayName)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, ESUI.Space.xxs)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: ESUI.Radius.sm, style: .continuous)
                                    .fill(ESUI.surface)
                                    .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: ESUI.Radius.sm, style: .continuous)
                                            .stroke(Color.primary.opacity(0.04), lineWidth: 0.5)
                                    )
                                    .matchedGeometryEffect(id: "category-indicator", in: indicatorNamespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(ESUI.Space.xxs)
        .background(
            RoundedRectangle(cornerRadius: ESUI.Radius.md, style: .continuous)
                .fill(ESUI.fill)
        )
    }
}
