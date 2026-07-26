import XCTest
@testable import EasySearch

@MainActor
final class CurrencyConverterViewModelTests: XCTestCase {
    private var viewModel: CurrencyConverterViewModel!

    override func setUp() {
        super.setUp()
        viewModel = CurrencyConverterViewModel()
        viewModel.apply(
            ExchangeRateResult(
                ratesAgainstCNY: [
                    .cny: 1,
                    .twd: 4.5,
                    .usd: 0.14,
                    .jpy: 21.0,
                    .krw: 190.0,
                    .tryLira: 4.8,
                    .inr: 11.5
                ],
                updatedAt: Date(),
                source: .network
            )
        )
    }

    func testConvertCNYToTWD() {
        viewModel.updateCNYAmount("100")
        XCTAssertEqual(viewModel.bottomAmount, "450.00")
        XCTAssertEqual(viewModel.topAmount, "100")
        XCTAssertEqual(viewModel.topCurrency, .cny)
        XCTAssertEqual(viewModel.bottomCurrency, .twd)
    }

    func testConvertTWDToCNY() {
        viewModel.updateTWDAmount("450")
        XCTAssertEqual(viewModel.topAmount, "100.00")
        XCTAssertEqual(viewModel.bottomAmount, "450")
    }

    func testConvertCNYToUSD() {
        viewModel.bottomCurrency = .usd
        viewModel.updateTopAmount("100")
        XCTAssertEqual(viewModel.bottomAmount, "14.00")
    }

    func testConvertUSDToJPY() {
        viewModel.topCurrency = .usd
        viewModel.bottomCurrency = .jpy
        viewModel.updateTopAmount("1")
        // 1 USD = 1/0.14 CNY * 21 JPY ≈ 150
        XCTAssertEqual(viewModel.bottomAmount, "150.00")
    }

    func testInvalidInputClearsResult() {
        viewModel.updateCNYAmount("100")
        XCTAssertEqual(viewModel.bottomAmount, "450.00")

        viewModel.updateCNYAmount("abc")
        XCTAssertEqual(viewModel.topAmount, "")
        XCTAssertEqual(viewModel.bottomAmount, "")
    }

    func testNilRateShowsPlaceholder() {
        let emptyViewModel = CurrencyConverterViewModel()
        emptyViewModel.updateCNYAmount("100")
        XCTAssertEqual(emptyViewModel.bottomAmount, "--")
    }

    func testSwapMovesAmountToOtherCurrencyAndRecalculates() {
        // 100 CNY = 450 TWD
        viewModel.updateCNYAmount("100")
        XCTAssertEqual(viewModel.bottomAmount, "450.00")

        // Swap: treat 100 as TWD -> 22.22 CNY
        viewModel.swapFields()
        XCTAssertEqual(viewModel.topCurrency, .twd)
        XCTAssertEqual(viewModel.bottomCurrency, .cny)
        XCTAssertEqual(viewModel.bottomAmount, "100")
        XCTAssertEqual(viewModel.topAmount, "22.22")

        // Swap back: treat 100 as CNY -> 450 TWD
        viewModel.swapFields()
        XCTAssertEqual(viewModel.topCurrency, .cny)
        XCTAssertEqual(viewModel.bottomCurrency, .twd)
        XCTAssertEqual(viewModel.topAmount, "100")
        XCTAssertEqual(viewModel.bottomAmount, "450.00")
    }

    func testSanitizeKeepsSingleDecimal() {
        viewModel.updateCNYAmount("12.3.4")
        XCTAssertEqual(viewModel.topAmount, "12.34")
        XCTAssertEqual(viewModel.bottomAmount, "55.53")
    }

    func testSupportedCurrenciesIncludeRequestedCodes() {
        let codes = Set(ConverterCurrency.allCases.map(\.rawValue))
        XCTAssertEqual(codes, Set(["CNY", "TWD", "USD", "JPY", "KRW", "TRY", "INR"]))
    }
}
