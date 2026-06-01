import XCTest
import MercantisCore
@testable import Mercantis_Hub

final class POSCheckoutBuilderTests: XCTestCase {

    // MARK: - Pricing

    private func priceList(_ rates: [(String, Double)]) -> Document {
        let rows = rates.enumerated().map { idx, pair in
            ChildRow(id: "ip-\(idx)", rowIndex: idx,
                     fields: ["item": .string(pair.0), "rate": .double(pair.1)])
        }
        return Document(id: "PL-1", docType: "PriceList", company: "", status: "",
                        createdAt: Date(), updatedAt: Date(), syncVersion: 0, syncState: .local,
                        fields: [:], children: ["items": rows])
    }

    func test_price_prefers_price_list_over_standard_rate() {
        let pl = priceList([("ITEM-1", 9.50), ("ITEM-2", 4.00)])
        XCTAssertEqual(POSCheckoutBuilder.price(forItem: "ITEM-1", in: pl, standardRate: 99), 9.50, accuracy: 0.0001)
    }

    func test_price_falls_back_to_standard_rate() {
        let pl = priceList([("ITEM-1", 9.50)])
        XCTAssertEqual(POSCheckoutBuilder.price(forItem: "ITEM-X", in: pl, standardRate: 12.0), 12.0, accuracy: 0.0001)
        XCTAssertEqual(POSCheckoutBuilder.price(forItem: "ITEM-X", in: nil, standardRate: 7.0), 7.0, accuracy: 0.0001)
    }

    // MARK: - Tender / change

    func test_change_is_difference_and_never_negative() {
        let tenders = [POSCheckoutBuilder.Tender(type: "Cash", amount: 20, reference: nil)]
        XCTAssertEqual(POSCheckoutBuilder.change(tenders: tenders, grandTotal: 17.40), 2.60, accuracy: 0.0001)
        XCTAssertEqual(POSCheckoutBuilder.change(tenders: tenders, grandTotal: 25), 0, accuracy: 0.0001)
    }

    func test_tendered_sums_all_tenders() {
        let tenders = [
            POSCheckoutBuilder.Tender(type: "Cash", amount: 10, reference: nil),
            POSCheckoutBuilder.Tender(type: "Card", amount: 5.5, reference: "auth-1"),
        ]
        XCTAssertEqual(POSCheckoutBuilder.tendered(tenders), 15.5, accuracy: 0.0001)
    }

    func test_is_fully_paid_requires_tender_to_cover_grand_total() {
        let exact = [POSCheckoutBuilder.Tender(type: "Cash", amount: 15.5, reference: nil)]
        let short = [POSCheckoutBuilder.Tender(type: "Cash", amount: 15.49, reference: nil)]

        XCTAssertTrue(POSCheckoutBuilder.isFullyPaid(tenders: exact, grandTotal: 15.5))
        XCTAssertFalse(POSCheckoutBuilder.isFullyPaid(tenders: short, grandTotal: 15.5))
    }

    // MARK: - Build

    func test_build_pos_invoice_shapes_items_and_tenders() {
        let doc = POSCheckoutBuilder.buildPOSInvoice(
            profileId: "POS-1", sessionId: "SES-1", customer: "CUST-1",
            postingDate: Date(timeIntervalSince1970: 0), currency: "EUR",
            warehouse: "Main", cashAccount: "Cash", incomeAccount: "Sales",
            defaultTaxCode: "STD",
            lines: [
                .init(itemId: "ITEM-1", qty: 2, rate: 5, taxCode: "STD", warehouse: "Main"),
                .init(itemId: "ITEM-2", qty: 1, rate: 3, taxCode: nil, warehouse: "Main"),
            ],
            tenders: [.init(type: "Cash", amount: 20, reference: nil)]
        )

        XCTAssertEqual(doc.docType, "POSInvoice")
        XCTAssertTrue(doc.id.isEmpty)
        XCTAssertEqual(doc.status, "Draft")
        XCTAssertEqual(stringValue(doc.fields["pos_profile"]), "POS-1")
        XCTAssertEqual(stringValue(doc.fields["pos_session"]), "SES-1")
        XCTAssertEqual(stringValue(doc.fields["warehouse"]), "Main")
        XCTAssertEqual(stringValue(doc.fields["cash_account"]), "Cash")
        XCTAssertEqual(doubleValue(doc.fields["paid_amount"]), 20, accuracy: 0.0001)

        let items = doc.children["items"] ?? []
        XCTAssertEqual(items.count, 2)
        // Lines use the shared SalesItem shape so tax + stock derivation reuse.
        XCTAssertEqual(stringValue(items[0].fields["item"]), "ITEM-1")
        XCTAssertEqual(doubleValue(items[0].fields["qty"]), 2, accuracy: 0.0001)
        XCTAssertEqual(stringValue(items[0].fields["tax_code"]), "STD")
        XCTAssertEqual(stringValue(items[0].fields["warehouse"]), "Main")

        let tenders = doc.children["tenders"] ?? []
        XCTAssertEqual(tenders.count, 1)
        XCTAssertEqual(stringValue(tenders[0].fields["tender_type"]), "Cash")
        XCTAssertEqual(doubleValue(tenders[0].fields["amount"]), 20, accuracy: 0.0001)
    }

    func test_build_omits_empty_optionals() {
        let doc = POSCheckoutBuilder.buildPOSInvoice(
            profileId: nil, sessionId: nil, customer: nil,
            postingDate: Date(), currency: nil, warehouse: "Main",
            cashAccount: nil, incomeAccount: nil, defaultTaxCode: nil,
            lines: [.init(itemId: "ITEM-1", qty: 1, rate: 5, taxCode: nil, warehouse: "Main")],
            tenders: []
        )
        XCTAssertNil(doc.fields["customer"])
        XCTAssertNil(doc.fields["currency"])
        XCTAssertNil(doc.fields["pos_profile"])
        XCTAssertEqual(doubleValue(doc.fields["paid_amount"]), 0, accuracy: 0.0001)
    }

    // MARK: - Helpers

    private func stringValue(_ v: FieldValue?) -> String? {
        if case .string(let s) = v { return s }
        return nil
    }
    private func doubleValue(_ v: FieldValue?) -> Double {
        switch v {
        case .double(let d): return d
        case .int(let i):    return Double(i)
        default:             return .nan
        }
    }
}
