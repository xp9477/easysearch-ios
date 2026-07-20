import Foundation
import Combine

@MainActor
final class CurrencyConverterViewModel: ObservableObject {
    // MARK: - Published state

    @Published var cnyAmount: String = ""
    @Published var twdAmount: String = ""
    @Published private(set) var rate: Double?
    @Published private(set) var rateUpdatedAt: Date?
    @Published private(set) var rateSource: ExchangeRateSource?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?

    // MARK: - Internal

    enum EditingField { case cny, twd, none }
    private(set) var editingField: EditingField = .none
    private var cancellables = Set<AnyCancellable>()
    private let service: ExchangeRateService

    // MARK: - Init

    init(service: ExchangeRateService = .shared) {
        self.service = service

        $cnyAmount
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in self?.cnyDidChange() }
            .store(in: &cancellables)

        $twdAmount
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in self?.twdDidChange() }
            .store(in: &cancellables)
    }

    // MARK: - Actions

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
    /// Exposed for unit tests to avoid network calls.
    func apply(_ result: ExchangeRateResult) {
        rate = result.rate
        rateUpdatedAt = result.updatedAt
        rateSource = result.source
        recalculateAfterRateUpdate()
    }

    func swapFields() {
        let oldCNY = cnyAmount
        let oldTWD = twdAmount
        editingField = .none
        cnyAmount = oldTWD
        twdAmount = oldCNY
    }

    func beginEditing(_ field: EditingField) {
        editingField = field
    }

    func endEditing() {
        editingField = .none
    }

    // MARK: - Conversion logic

    private func cnyDidChange() {
        guard editingField == .cny else { return }
        guard let rate else {
            twdAmount = cnyAmount.isEmpty ? "" : "--"
            return
        }
        guard let value = Double(cnyAmount), !cnyAmount.isEmpty else {
            twdAmount = ""
            return
        }
        twdAmount = formatAmount(value * rate)
    }

    private func twdDidChange() {
        guard editingField == .twd else { return }
        guard let rate, rate > 0 else {
            cnyAmount = twdAmount.isEmpty ? "" : "--"
            return
        }
        guard let value = Double(twdAmount), !twdAmount.isEmpty else {
            cnyAmount = ""
            return
        }
        cnyAmount = formatAmount(value / rate)
    }

    private func recalculateAfterRateUpdate() {
        guard let rate else { return }

        if editingField == .twd, let value = Double(twdAmount), rate > 0 {
            cnyAmount = formatAmount(value / rate)
        } else if let value = Double(cnyAmount) {
            twdAmount = formatAmount(value * rate)
        } else if let value = Double(twdAmount), rate > 0 {
            cnyAmount = formatAmount(value / rate)
        }
    }

    private func formatAmount(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
