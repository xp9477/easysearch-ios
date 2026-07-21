import SwiftUI

public struct UtilitiesView: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ESUI.sectionSpacing) {
                ESSectionHeader(
                    title: "工具列表",
                    subtitle: "轻量实用，即开即用"
                )

                NavigationLink {
                    CurrencyConverterView()
                } label: {
                    ESFeatureEntryRow(
                        title: "汇率换算",
                        summary: "人民币 ↔ 新台币实时换算",
                        systemImage: "arrow.left.arrow.right.circle.fill",
                        color: .orange
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, ESUI.screenHorizontalPadding)
            .padding(.top, ESUI.Space.md)
            .padding(.bottom, ESUI.Space.lg)
        }
        .esScreenBackground()
        .navigationTitle("实用工具")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        UtilitiesView()
    }
}
