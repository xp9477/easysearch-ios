import SwiftUI

struct CurrencyConverterView: View {
    @StateObject private var viewModel = CurrencyConverterViewModel()
    @FocusState private var focusedField: Field?

    private enum Field {
        case cny
        case twd
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                rateHeaderCard
                conversionSection
                dataSourceFooter
            }
            .padding(.horizontal, ESUI.screenHorizontalPadding)
            .padding(.top, 14)
            .padding(.bottom, 32)
        }
        .esScreenBackground()
        .navigationTitle("汇率换算")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.fetchRate(force: true) }
                } label: {
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(viewModel.isLoading)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { focusedField = nil }
            }
        }
        .task {
            await viewModel.fetchRate()
        }
    }

    // MARK: - Rate Header

    private var rateHeaderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.tint)
                Text("实时汇率")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            if let rate = viewModel.rate {
                Text("1 CNY = \(rate, specifier: "%.4f") TWD")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("1 TWD = \(1.0 / rate, specifier: "%.4f") CNY")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            } else if viewModel.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("加载中…")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("暂无汇率数据")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red)
            }

            HStack(spacing: 6) {
                if let updatedAt = viewModel.rateUpdatedAt {
                    Text("更新时间：\(updatedAt, format: .dateTime.month().day().hour().minute())")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                if viewModel.rateSource == .cache {
                    Text("· 离线数据")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.orange)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .esCard()
    }

    // MARK: - Conversion Section

    private var conversionSection: some View {
        VStack(spacing: 0) {
            currencyInputRow(
                flag: "🇨🇳",
                code: "CNY",
                label: "人民币",
                text: viewModel.cnyAmount,
                field: .cny,
                onChange: viewModel.updateCNYAmount
            )

            swapButton

            currencyInputRow(
                flag: "🇹🇼",
                code: "TWD",
                label: "新台币",
                text: viewModel.twdAmount,
                field: .twd,
                onChange: viewModel.updateTWDAmount
            )
        }
    }

    private func currencyInputRow(
        flag: String,
        code: String,
        label: String,
        text: String,
        field: Field,
        onChange: @escaping (String) -> Void
    ) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(flag)
                        .font(.system(size: 24))
                    Text(code)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 80, alignment: .leading)

            TextField(
                "输入金额",
                text: Binding(
                    get: { text == "--" ? "" : text },
                    set: onChange
                )
            )
            .keyboardType(.decimalPad)
            .font(.system(size: 28, weight: .semibold, design: .rounded))
            .multilineTextAlignment(.trailing)
            .focused($focusedField, equals: field)
            .foregroundStyle(text == "--" ? .secondary : .primary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: ESUI.cardCornerRadius, style: .continuous)
                .fill(ESUI.elevatedBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ESUI.cardCornerRadius, style: .continuous)
                .stroke(
                    focusedField == field ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.05),
                    lineWidth: focusedField == field ? 2 : 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            focusedField = field
        }
    }

    private var swapButton: some View {
        HStack {
            Spacer()
            Button {
                viewModel.swapFields()
            } label: {
                Image(systemName: "arrow.up.arrow.down.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.tint)
                    .background(Circle().fill(ESUI.appBackground).padding(2))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.vertical, -12)
        .zIndex(1)
    }

    // MARK: - Footer

    private var dataSourceFooter: some View {
        HStack(spacing: 4) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
            Text("数据来源：ExchangeRate-API · 输入任一侧金额即可换算")
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(.quaternary)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

#Preview {
    NavigationStack {
        CurrencyConverterView()
    }
}
