import XCTest
@testable import Mercantis_Hub

final class HubTaxEngineTests: XCTestCase {

    private func rate(_ id: String, _ pct: Double, account: String? = "VAT-Account")
        -> HubTaxEngine.TaxRateInfo
    {
        HubTaxEngine.TaxRateInfo(codeId: id, description: "\(id)", rate: pct, account: account)
    }

    func test_single_standard_rate_adds_vat_to_grand_total() {
        let computation = HubTaxEngine.compute(
            lines: [
                .init(netAmount: 100, taxCodeId: "STD"),
                .init(netAmount: 50,  taxCodeId: "STD"),
            ],
            rates: ["STD": rate("STD", 18)]
        )

        XCTAssertEqual(computation.netTotal, 150, accuracy: 0.0001)
        XCTAssertEqual(computation.taxRows.count, 1)
        XCTAssertEqual(computation.taxRows[0].taxableAmount, 150, accuracy: 0.0001)
        XCTAssertEqual(computation.taxRows[0].taxAmount, 27, accuracy: 0.0001) // 18% of 150
        XCTAssertEqual(computation.totalTax, 27, accuracy: 0.0001)
        XCTAssertEqual(computation.grandTotal, 177, accuracy: 0.0001)
    }

    func test_multiple_rates_produce_one_row_per_code_in_first_seen_order() {
        let computation = HubTaxEngine.compute(
            lines: [
                .init(netAmount: 200, taxCodeId: "STD"),
                .init(netAmount: 100, taxCodeId: "RED"),
                .init(netAmount: 100, taxCodeId: "STD"),
            ],
            rates: [
                "STD": rate("STD", 18),
                "RED": rate("RED", 7),
            ]
        )

        XCTAssertEqual(computation.taxRows.count, 2)
        XCTAssertEqual(computation.taxRows[0].taxCode, "STD")
        XCTAssertEqual(computation.taxRows[0].taxableAmount, 300, accuracy: 0.0001)
        XCTAssertEqual(computation.taxRows[0].taxAmount, 54, accuracy: 0.0001)  // 18% of 300
        XCTAssertEqual(computation.taxRows[1].taxCode, "RED")
        XCTAssertEqual(computation.taxRows[1].taxAmount, 7, accuracy: 0.0001)   // 7% of 100
        XCTAssertEqual(computation.netTotal, 400, accuracy: 0.0001)
        XCTAssertEqual(computation.totalTax, 61, accuracy: 0.0001)
        XCTAssertEqual(computation.grandTotal, 461, accuracy: 0.0001)
    }

    func test_zero_rated_code_still_produces_a_row_with_zero_tax() {
        let computation = HubTaxEngine.compute(
            lines: [.init(netAmount: 80, taxCodeId: "ZERO")],
            rates: ["ZERO": rate("ZERO", 0)]
        )

        XCTAssertEqual(computation.taxRows.count, 1, "Zero-rated turnover must still appear for the VAT return")
        XCTAssertEqual(computation.taxRows[0].taxableAmount, 80, accuracy: 0.0001)
        XCTAssertEqual(computation.taxRows[0].taxAmount, 0, accuracy: 0.0001)
        XCTAssertEqual(computation.grandTotal, 80, accuracy: 0.0001)
    }

    func test_lines_without_a_code_contribute_to_net_but_not_to_tax() {
        let computation = HubTaxEngine.compute(
            lines: [
                .init(netAmount: 100, taxCodeId: nil),
                .init(netAmount: 100, taxCodeId: "STD"),
            ],
            rates: ["STD": rate("STD", 18)]
        )

        XCTAssertEqual(computation.netTotal, 200, accuracy: 0.0001)
        XCTAssertEqual(computation.taxRows.count, 1)
        XCTAssertEqual(computation.taxRows[0].taxableAmount, 100, accuracy: 0.0001)
        XCTAssertEqual(computation.totalTax, 18, accuracy: 0.0001)
        XCTAssertEqual(computation.grandTotal, 218, accuracy: 0.0001)
    }

    func test_unknown_code_is_treated_as_no_tax() {
        let computation = HubTaxEngine.compute(
            lines: [.init(netAmount: 100, taxCodeId: "MISSING")],
            rates: [:]
        )
        XCTAssertTrue(computation.taxRows.isEmpty)
        XCTAssertEqual(computation.totalTax, 0, accuracy: 0.0001)
        XCTAssertEqual(computation.grandTotal, 100, accuracy: 0.0001)
    }

    func test_tax_amount_is_rounded_to_two_decimals() {
        // 99.99 @ 18% = 17.9982 → 18.00
        let computation = HubTaxEngine.compute(
            lines: [.init(netAmount: 99.99, taxCodeId: "STD")],
            rates: ["STD": rate("STD", 18)]
        )
        XCTAssertEqual(computation.taxRows[0].taxAmount, 18.0, accuracy: 0.0001)
        XCTAssertEqual(computation.grandTotal, 117.99, accuracy: 0.0001)
    }

    func test_empty_lines_produce_empty_computation() {
        let computation = HubTaxEngine.compute(lines: [], rates: [:])
        XCTAssertEqual(computation.netTotal, 0)
        XCTAssertEqual(computation.grandTotal, 0)
        XCTAssertTrue(computation.taxRows.isEmpty)
    }
}
