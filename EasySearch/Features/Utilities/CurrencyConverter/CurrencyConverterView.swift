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
            VStack(alignment: .leading, spacing: ESUI.sectionSpacing) {
                rateHeaderCard
                conversionSection
                dataSourceFooter
            }
            .padding(.horizontal, ESUI.screenHorizontalPadding)
            .padding(.top, ESUI.Space.md)
            .padding(.bottom, ESUI.Space.lg)
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
                .accessibilityLabel("刷新汇率")
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

    private var rateHeaderCard: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            ESSectionHeader(title: "实时汇率")

            if let rate = viewModel.rate {
                Text("1 CNY = \(rate, specifier: "%.4f") TWD")
                    .font(.title3.weight(.semibold).monospacedDigit())
                Text("1 TWD = \(1.0 / rate, specifier: "%.4f") CNY")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else if viewModel.isLoading {
                ESLoadingState(message: "加载中…")
            } else {
                Text("暂无汇率数据")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = viewModel.errorMessage {
                ESStatusBanner(
                    title: errorMessage,
                    systemImage: "exclamationmark.triangle.fill",
                    tone: .danger
                )
            }

            HStack(spacing: ESUI.Space.xs) {
                if let updatedAt = viewModel.rateUpdatedAt {
                    Text("更新时间：\(updatedAt, format: .dateTime.month().day().hour().minute())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if viewModel.rateSource == .cache {
                    ESStatusBadge(text: "离线数据", tone: .warning)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .esCard()
    }

    private var conversionSection: some View {
        VStack(spacing: 0) {
            currencyInputRow(
                code: "CNY",
                label: "人民币",
                text: viewModel.cnyAmount,
                field: .cny,
                onChange: viewModel.updateCNYAmount
            )

            swapButton

            currencyInputRow(
                code: "TWD",
                label: "新台币",
                text: viewModel.twdAmount,
                field: .twd,
                onChange: viewModel.updateTWDAmount
            )
        }
    }

    private func currencyInputRow(
        code: String,
        label: String,
        text: String,
        field: Field,
        onChange: @escaping (String) -> Void
    ) -> some View {
        HStack(spacing: ESUI.Space.sm) {
            VStack(alignment: .leading, spacing: ESUI.Space.xxs) {
                Text(code)
                    .font(.body.weight(.semibold))
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 72, alignment: .leading)

            TextField(
                "输入金额",
                text: Binding(
                    get: { text == "--" ? "" : text },
                    set: onChange
                )
            )
            .keyboardType(.decimalPad)
            .font(.title2.weight(.semibold).monospacedDigit())
            .multilineTextAlignment(.trailing)
            .focused($focusedField, equals: field)
            .foregroundStyle(text == "--" ? .secondary : .primary)
        }
        .padding(ESUI.Space.md)
        .background(
            RoundedRectangle(cornerRadius: ESUI.cardCornerRadius, style: .continuous)
                .fill(ESUI.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ESUI.cardCornerRadius, style: .continuous)
                .stroke(
                    focusedField == field ? Color.accentColor.opacity(0.35) : Color.clear,
                    lineWidth: 1.5
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { focusedField = field }
    }

    private var swapButton: some View {
        HStack {
            Spacer()
            Button {
                viewModel.swapFields()
            } label: {
                Image(systemName: "arrow.up.arrow.down.circle.fill")
                    .font(.title)
                    .foregroundStyle(.tint)
                    .background(Circle().fill(ESUI.appBackground).padding(2))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("交换币种")
            Spacer()
        }
        .padding(.vertical, -ESUI.Space.sm)
        .zIndex(1)
    }

    private var dataSourceFooter: some View {
        Text("数据来源：ExchangeRate-API · 输入任一侧金额即可换算")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    NavigationStack {
        CurrencyConverterView()
    }
}
