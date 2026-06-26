import XCTest
import MercantisCore
@testable import Mercantis_Hub

final class HubTaxCalculationPolicyTests: XCTestCase {

    // MARK: - Fixtures

    private let standard = HubTaxEngine.TaxRateInfo(
        codeId: "STD", description: "Standard (18%)", rate: 18, account: "OUT-VAT"
    )
    private let reduced = HubTaxEngine.TaxRateInfo(
        codeId: "RED", description: "Reduced (7%)", rate: 7, account: "OUT-VAT"
    )

    private func itemRow(_ index: Int, item: String, qty: Double, rate: Double, taxCode: String? = nil) -> ChildRow {
        var fields: [String: FieldValue] = [
            "item": .string(item),
            "qty":  .double(qty),
            "rate": .double(rate),
        ]
        if let taxCode { fields["tax_code"] = .string(taxCode) }
        return ChildRow(id: "row-\(index)", rowIndex: index, fields: fields)
    }

    private func invoice(items: [ChildRow], fields: [String: FieldValue] = [:]) -> Document {
        Document(
            id: "SINV-1",
            docType: "SalesInvoice",
            company: "Acme",
            status: "Draft",
            createdAt: Date(),
            updatedAt: Date(),
            syncVersion: 0,
            syncState: .local,
            fields: fields,
            children: ["items": items]
        )
    }

    // MARK: - Tests

    func test_document_level_tax_code_applies_to_all_lines() {
        let doc = invoice(items: [
            itemRow(0, item: "A", qty: 2, rate: 50),   // 100
            itemRow(1, item: "B", qty: 1, rate: 100),  // 100
        ])

        let result = HubTaxCalculationPolicy.computeAndApply(
            document: doc,
            rateByCode: ["STD": standard],
            documentTaxCode: "STD",
            partyTaxCode: nil,
            itemTaxCode: { _ in nil }
        )

        XCTAssertEqual(asDouble(result.fields["net_total"]), 200, accuracy: 0.0001)
        XCTAssertEqual(asDouble(result.fields["total_taxes"]), 36, accuracy: 0.0001)
        XCTAssertEqual(asDouble(result.fields["grand_total"]), 236, accuracy: 0.0001)
        XCTAssertEqual(asDouble(result.fields["total_qty"]), 3, accuracy: 0.0001)

        let taxes = result.children["taxes"] ?? []
        XCTAssertEqual(taxes.count, 1)
        XCTAssertEqual(asString(taxes[0].fields["tax_code"]), "STD")
        XCTAssertEqual(asString(taxes[0].fields["tax_account"]), "OUT-VAT")
        XCTAssertEqual(asDouble(taxes[0].fields["tax_amount"]), 36, accuracy: 0.0001)
    }

    func test_line_tax_code_overrides_document_default_and_groups_per_code() {
        let doc = invoice(items: [
            itemRow(0, item: "A", qty: 1, rate: 100, taxCode: "RED"),  // reduced
            itemRow(1, item: "B", qty: 1, rate: 100),                  // falls back to doc STD
        ])

        let result = HubTaxCalculationPolicy.computeAndApply(
            document: doc,
            rateByCode: ["STD": standard, "RED": reduced],
            documentTaxCode: "STD",
            partyTaxCode: nil,
            itemTaxCode: { _ in nil }
        )

        let taxes = result.children["taxes"] ?? []
        XCTAssertEqual(taxes.count, 2)
        // 7% of 100 + 18% of 100 = 7 + 18 = 25
        XCTAssertEqual(asDouble(result.fields["total_taxes"]), 25, accuracy: 0.0001)
        XCTAssertEqual(asDouble(result.fields["grand_total"]), 225, accuracy: 0.0001)
    }

    func test_item_master_tax_code_is_used_when_line_has_none() {
        let doc = invoice(items: [itemRow(0, item: "ITEM-RED", qty: 1, rate: 100)])

        let result = HubTaxCalculationPolicy.computeAndApply(
            document: doc,
            rateByCode: ["RED": reduced],
            documentTaxCode: nil,
            partyTaxCode: nil,
            itemTaxCode: { $0 == "ITEM-RED" ? "RED" : nil }
        )

        let taxes = result.children["taxes"] ?? []
        XCTAssertEqual(taxes.count, 1)
        XCTAssertEqual(asString(taxes[0].fields["tax_code"]), "RED")
        XCTAssertEqual(asDouble(result.fields["total_taxes"]), 7, accuracy: 0.0001)
    }

    func test_party_tax_code_is_lowest_priority_fallback() {
        let doc = invoice(items: [itemRow(0, item: "A", qty: 1, rate: 100)])

        let result = HubTaxCalculationPolicy.computeAndApply(
            document: doc,
            rateByCode: ["STD": standard],
            documentTaxCode: nil,
            partyTaxCode: "STD",
            itemTaxCode: { _ in nil }
        )

        XCTAssertEqual(asDouble(result.fields["total_taxes"]), 18, accuracy: 0.0001)
        XCTAssertEqual(asDouble(result.fields["grand_total"]), 118, accuracy: 0.0001)
    }

    func test_no_tax_code_anywhere_still_sets_totals_without_vat() {
        let doc = invoice(items: [itemRow(0, item: "A", qty: 3, rate: 10)])

        let result = HubTaxCalculationPolicy.computeAndApply(
            document: doc,
            rateByCode: [:],
            documentTaxCode: nil,
            partyTaxCode: nil,
            itemTaxCode: { _ in nil }
        )

        XCTAssertEqual(asDouble(result.fields["net_total"]), 30, accuracy: 0.0001)
        XCTAssertEqual(asDouble(result.fields["total_taxes"]), 0, accuracy: 0.0001)
        XCTAssertEqual(asDouble(result.fields["grand_total"]), 30, accuracy: 0.0001)
        XCTAssertTrue((result.children["taxes"] ?? []).isEmpty)
    }

    // MARK: - Totals-only documents (Quotation / Sales Order / Delivery / Receipt)

    func test_totalsOnly_quotation_sumsQtyAndAmountWithoutTaxTable() {
        // Quotation carries total_qty + grand_total but no `taxes` table, so it
        // takes the totals-only path. 2 * 3.5 + 1 * 10 = 17 over 3 units.
        let quote = Document(
            id: "SQTN-1", docType: "Quotation", company: "Acme", status: "Draft",
            createdAt: Date(), updatedAt: Date(), syncVersion: 0, syncState: .local,
            fields: [:],
            children: ["items": [
                itemRow(0, item: "A", qty: 2, rate: 3.5),
                itemRow(1, item: "B", qty: 1, rate: 10),
            ]]
        )

        let result = HubTaxCalculationPolicy.appliedTotalsOnly(to: quote, docType: Selling.quotation)

        XCTAssertEqual(asDouble(result.fields["total_qty"]), 3, accuracy: 0.0001)
        XCTAssertEqual(asDouble(result.fields["grand_total"]), 17, accuracy: 0.0001)
        // No tax table is written on the totals-only path.
        XCTAssertNil(result.children["taxes"])
    }

    func test_totalsOnly_prefersStoredLineAmountOverQtyTimesRate() {
        // The grid stores `amount` per line (qty * rate); the totals use it
        // directly when present.
        var row = itemRow(0, item: "A", qty: 4, rate: 5)
        row.fields["amount"] = .double(20)
        let quote = Document(
            id: "SQTN-2", docType: "Quotation", company: "Acme", status: "Draft",
            createdAt: Date(), updatedAt: Date(), syncVersion: 0, syncState: .local,
            fields: [:], children: ["items": [row]]
        )

        let result = HubTaxCalculationPolicy.appliedTotalsOnly(to: quote, docType: Selling.quotation)
        XCTAssertEqual(asDouble(result.fields["total_qty"]), 4, accuracy: 0.0001)
        XCTAssertEqual(asDouble(result.fields["grand_total"]), 20, accuracy: 0.0001)
    }

    // MARK: - Helpers

    private func asDouble(_ value: FieldValue?) -> Double {
        switch value {
        case .double(let d): return d
        case .int(let i):    return Double(i)
        default:             return .nan
        }
    }

    private func asString(_ value: FieldValue?) -> String? {
        if case .string(let s) = value { return s }
        return nil
    }
}
