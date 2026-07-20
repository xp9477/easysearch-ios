import XCTest
@testable import EasySearch

@MainActor
final class CurrencyConverterViewModelTests: XCTestCase {
    private var viewModel: CurrencyConverterViewModel!

    override func setUp() {
        super.setUp()
        viewModel = CurrencyConverterViewModel()
        viewModel.apply(
            ExchangeRateResult(rate: 4.5, updatedAt: Date(), source: .network)
        )
    }

    func testConvertCNYToTWD() {
        viewModel.updateCNYAmount("100")
        XCTAssertEqual(viewModel.twdAmount, "450.00")
        XCTAssertEqual(viewModel.cnyAmount, "100")
    }

    func testConvertTWDToCNY() {
        viewModel.updateTWDAmount("450")
        XCTAssertEqual(viewModel.cnyAmount, "100.00")
        XCTAssertEqual(viewModel.twdAmount, "450")
    }

    func testInvalidInputClearsResult() {
        viewModel.updateCNYAmount("100")
        XCTAssertEqual(viewModel.twdAmount, "450.00")

        viewModel.updateCNYAmount("abc")
        XCTAssertEqual(viewModel.cnyAmount, "")
        XCTAssertEqual(viewModel.twdAmount, "")
    }

    func testNilRateShowsPlaceholder() {
        let emptyViewModel = CurrencyConverterViewModel()
        emptyViewModel.updateCNYAmount("100")
        XCTAssertEqual(emptyViewModel.twdAmount, "--")
    }

    func testSwapMovesAmountToOtherCurrencyAndRecalculates() {
        // 100 CNY = 450 TWD
        viewModel.updateCNYAmount("100")
        XCTAssertEqual(viewModel.twdAmount, "450.00")

        // Swap: treat 100 as TWD -> 22.22 CNY
        viewModel.swapFields()
        XCTAssertEqual(viewModel.twdAmount, "100")
        XCTAssertEqual(viewModel.cnyAmount, "22.22")

        // Swap back: treat 100 as CNY -> 450 TWD
        viewModel.swapFields()
        XCTAssertEqual(viewModel.cnyAmount, "100")
        XCTAssertEqual(viewModel.twdAmount, "450.00")
    }

    func testSanitizeKeepsSingleDecimal() {
        viewModel.updateCNYAmount("12.3.4")
        XCTAssertEqual(viewModel.cnyAmount, "12.34")
        XCTAssertEqual(viewModel.twdAmount, "55.53")
    }
}
