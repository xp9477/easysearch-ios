import XCTest
@testable import EasySearch

@MainActor
final class CurrencyConverterViewModelTests: XCTestCase {
    private var viewModel: CurrencyConverterViewModel!

    override func setUp() {
        super.setUp()
        viewModel = CurrencyConverterViewModel()
    }

    func testConvertCNYToTWD() {
        viewModel.apply(
            ExchangeRateResult(rate: 4.5, updatedAt: Date(), source: .network)
        )
        viewModel.beginEditing(.cny)
        viewModel.cnyAmount = "100"

        XCTAssertEqual(viewModel.twdAmount, "450.00")
    }

    func testConvertTWDToCNY() {
        viewModel.apply(
            ExchangeRateResult(rate: 4.5, updatedAt: Date(), source: .network)
        )
        viewModel.beginEditing(.twd)
        viewModel.twdAmount = "450"

        XCTAssertEqual(viewModel.cnyAmount, "100.00")
    }

    func testInvalidInputClearsResult() {
        viewModel.apply(
            ExchangeRateResult(rate: 4.5, updatedAt: Date(), source: .network)
        )
        viewModel.beginEditing(.cny)
        viewModel.cnyAmount = "100"
        XCTAssertEqual(viewModel.twdAmount, "450.00")

        viewModel.cnyAmount = "abc"
        XCTAssertEqual(viewModel.twdAmount, "")
    }

    func testNilRateShowsPlaceholder() {
        viewModel.beginEditing(.cny)
        viewModel.cnyAmount = "100"

        XCTAssertEqual(viewModel.twdAmount, "--")
    }

    func testSwapFieldsExchangesValues() {
        viewModel.apply(
            ExchangeRateResult(rate: 4.5, updatedAt: Date(), source: .network)
        )
        viewModel.beginEditing(.cny)
        viewModel.cnyAmount = "100"
        XCTAssertEqual(viewModel.twdAmount, "450.00")

        viewModel.swapFields()

        XCTAssertEqual(viewModel.cnyAmount, "450.00")
        XCTAssertEqual(viewModel.twdAmount, "100")
    }
}
