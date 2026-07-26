import Foundation
import Combine

@MainActor
final class CurrencyConverterViewModel: ObservableObject {
    @Published var topCurrency: ConverterCurrency = .cny {
        didSet {
            guard oldValue != topCurrency else { return }
            if topCurrency == bottomCurrency {
                bottomCurrency = oldValue
            }
            recalculateFromSourceField()
        }
    }

    @Published var bottomCurrency: ConverterCurrency = .twd {
        didSet {
            guard oldValue != bottomCurrency else { return }
            if bottomCurrency == topCurrency {
                topCurrency = oldValue
            }
            recalculateFromSourceField()
        }
    }

    @Published private(set) var topAmount: String = ""
    @Published private(set) var bottomAmount: String = ""
    @Published private(set) var rateSnapshot: ExchangeRateResult?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?

    /// Which field the user last edited; used by swap and rate refresh.
    private enum SourceField {
        case top
        case bottom
    }

    private var sourceField: SourceField = .top
    private let service: ExchangeRateService

    init(service: ExchangeRateService = .shared) {
        self.service = service
    }

    // MARK: - Derived

    var rateUpdatedAt: Date? { rateSnapshot?.updatedAt }
    var rateSource: ExchangeRateSource? { rateSnapshot?.source }

    /// Units of bottom currency per 1 top currency.
    var pairRate: Double? {
        guard let snapshot = rateSnapshot else { return nil }
        return snapshot.convert(amount: 1, from: topCurrency, to: bottomCurrency)
    }

    /// Units of top currency per 1 bottom currency.
    var inversePairRate: Double? {
        guard let rate = pairRate, rate > 0 else { return nil }
        return 1 / rate
    }

    // MARK: - Rate

    func fetchRate(force: Bool = false) async {
        isLoading = true
        errorMessage = nil

        do {
            let result = try await service.fetchRate(force: force)
            apply(result)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Applies a rate result and recalculates conversion fields.
    func apply(_ result: ExchangeRateResult) {
        rateSnapshot = result
        // If cache is TWD-only legacy and bottom is unsupported, fall back to TWD.
        if result.rate(of: bottomCurrency) == nil, result.rate(of: .twd) != nil {
            bottomCurrency = .twd
        }
        recalculateFromSourceField()
    }

    // MARK: - Input

    func updateTopAmount(_ text: String) {
        let sanitized = Self.sanitizeAmountInput(text)
        topAmount = sanitized
        sourceField = .top
        convertFromTop()
    }

    func updateBottomAmount(_ text: String) {
        let sanitized = Self.sanitizeAmountInput(text)
        bottomAmount = sanitized
        sourceField = .bottom
        convertFromBottom()
    }

    /// Move the currently entered number to the other currency field, then recalculate.
    func swapFields() {
        guard rateSnapshot != nil else { return }

        let previousTop = topCurrency
        topCurrency = bottomCurrency
        bottomCurrency = previousTop

        switch sourceField {
        case .top:
            let amount = topAmount
            sourceField = .bottom
            bottomAmount = amount
            convertFromBottom()
        case .bottom:
            let amount = bottomAmount
            sourceField = .top
            topAmount = amount
            convertFromTop()
        }
    }

    // MARK: - Conversion

    private func convertFromTop() {
        guard let snapshot = rateSnapshot else {
            bottomAmount = topAmount.isEmpty ? "" : "--"
            return
        }
        guard let value = Double(topAmount) else {
            bottomAmount = topAmount.isEmpty ? "" : ""
            return
        }
        guard let converted = snapshot.convert(amount: value, from: topCurrency, to: bottomCurrency) else {
            bottomAmount = "--"
            return
        }
        bottomAmount = Self.formatAmount(converted)
    }

    private func convertFromBottom() {
        guard let snapshot = rateSnapshot else {
            topAmount = bottomAmount.isEmpty ? "" : "--"
            return
        }
        guard let value = Double(bottomAmount) else {
            topAmount = bottomAmount.isEmpty ? "" : ""
            return
        }
        guard let converted = snapshot.convert(amount: value, from: bottomCurrency, to: topCurrency) else {
            topAmount = "--"
            return
        }
        topAmount = Self.formatAmount(converted)
    }

    private func recalculateFromSourceField() {
        switch sourceField {
        case .top:
            convertFromTop()
        case .bottom:
            convertFromBottom()
        }
    }

    static func formatAmount(_ value: Double) -> String {
        // JPY/KRW often shown without decimals; keep 2 for consistency across currencies.
        String(format: "%.2f", value)
    }

    /// Keep digits and at most one decimal point.
    static func sanitizeAmountInput(_ text: String) -> String {
        var result = ""
        var hasDecimal = false

        for character in text {
            if character.isNumber {
                result.append(character)
            } else if character == ".", !hasDecimal {
                result.append(character)
                hasDecimal = true
            }
        }

        return result
    }
}

// MARK: - Backward-compatible test aliases

extension CurrencyConverterViewModel {
    var cnyAmount: String { topCurrency == .cny ? topAmount : (bottomCurrency == .cny ? bottomAmount : topAmount) }
    var twdAmount: String { topCurrency == .twd ? topAmount : (bottomCurrency == .twd ? bottomAmount : bottomAmount) }

    func updateCNYAmount(_ text: String) {
        if topCurrency != .cny { topCurrency = .cny }
        if bottomCurrency == .cny { bottomCurrency = .twd }
        updateTopAmount(text)
    }

    func updateTWDAmount(_ text: String) {
        if bottomCurrency != .twd { bottomCurrency = .twd }
        if topCurrency == .twd { topCurrency = .cny }
        updateBottomAmount(text)
    }
}
