import Foundation
import Combine

@MainActor
final class CurrencyConverterViewModel: ObservableObject {
    @Published private(set) var cnyAmount: String = ""
    @Published private(set) var twdAmount: String = ""
    @Published private(set) var rate: Double?
    @Published private(set) var rateUpdatedAt: Date?
    @Published private(set) var rateSource: ExchangeRateSource?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?

    /// Which field the user last edited; used by swap and rate refresh.
    private enum SourceField {
        case cny
        case twd
    }

    private var sourceField: SourceField = .cny
    private let service: ExchangeRateService
    init(service: ExchangeRateService = .shared) {
        self.service = service
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
        rate = result.rate
        rateUpdatedAt = result.updatedAt
        rateSource = result.source
        recalculateFromSourceField()
    }

    // MARK: - Input

    func updateCNYAmount(_ text: String) {
        let sanitized = Self.sanitizeAmountInput(text)
        setCNYAmount(sanitized)
        sourceField = .cny
        convertFromCNY()
    }

    func updateTWDAmount(_ text: String) {
        let sanitized = Self.sanitizeAmountInput(text)
        setTWDAmount(sanitized)
        sourceField = .twd
        convertFromTWD()
    }

    /// Move the currently entered number to the other currency, then recalculate.
    /// Example: 100 CNY -> 440 TWD, after swap becomes 100 TWD -> 22.71 CNY.
    func swapFields() {
        guard rate != nil else { return }

        switch sourceField {
        case .cny:
            let amount = cnyAmount
            sourceField = .twd
            setTWDAmount(amount)
            convertFromTWD()
        case .twd:
            let amount = twdAmount
            sourceField = .cny
            setCNYAmount(amount)
            convertFromCNY()
        }
    }

    // MARK: - Conversion

    private func convertFromCNY() {
        guard let rate else {
            setTWDAmount(cnyAmount.isEmpty ? "" : "--")
            return
        }
        guard let value = Double(cnyAmount) else {
            setTWDAmount(cnyAmount.isEmpty ? "" : "")
            return
        }
        setTWDAmount(Self.formatAmount(value * rate))
    }

    private func convertFromTWD() {
        guard let rate, rate > 0 else {
            setCNYAmount(twdAmount.isEmpty ? "" : "--")
            return
        }
        guard let value = Double(twdAmount) else {
            setCNYAmount(twdAmount.isEmpty ? "" : "")
            return
        }
        setCNYAmount(Self.formatAmount(value / rate))
    }

    private func recalculateFromSourceField() {
        switch sourceField {
        case .cny:
            convertFromCNY()
        case .twd:
            convertFromTWD()
        }
    }

    private func setCNYAmount(_ value: String) {
        cnyAmount = value
    }

    private func setTWDAmount(_ value: String) {
        twdAmount = value
    }

    static func formatAmount(_ value: Double) -> String {
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
