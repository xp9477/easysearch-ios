import SwiftUI

public struct UtilitiesView: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard
                toolsSection
            }
            .padding(.horizontal, ESUI.screenHorizontalPadding)
            .padding(.top, 14)
            .padding(.bottom, 32)
        }
        .esScreenBackground()
        .navigationTitle("实用工具")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Utilities")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("实用工具")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.primary)

            Text("这里会承载后续扩展的小工具，保持主搜索体验足够专注。")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(.secondarySystemGroupedBackground),
                            Color.orange.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ESSectionHeader(title: "工具列表", subtitle: "轻量实用，即开即用")

            NavigationLink {
                CurrencyConverterView()
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.orange.opacity(0.14))
                            .frame(width: 48, height: 48)

                        Image(systemName: "arrow.left.arrow.right.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.orange)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("汇率换算")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text("人民币 ↔ 新台币实时换算")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .esCard()
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    NavigationStack {
        UtilitiesView()
    }
}
