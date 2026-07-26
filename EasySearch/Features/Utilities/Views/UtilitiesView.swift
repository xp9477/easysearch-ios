import SwiftUI

struct UtilitiesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ESUI.sectionSpacing) {
                ESModuleHero(
                    title: "实用工具",
                    subtitle: "轻量小工具",
                    featureID: "utilities",
                    systemImage: "hammer.fill"
                )

                NavigationLink {
                    CurrencyConverterView()
                } label: {
                    ESFeatureEntryRow(
                        title: "人民币 / 新台币",
                        summary: "实时汇率换算",
                        systemImage: "yensign.circle",
                        color: .gray
                    )
                }
                .buttonStyle(ESCardButtonStyle())
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
