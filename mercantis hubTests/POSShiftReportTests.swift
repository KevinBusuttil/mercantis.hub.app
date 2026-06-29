import XCTest
import MercantisCore
@testable import Mercantis_Hub

/// Guards for the POS X / Z shift-report maths: sales/tax aggregation, tender
/// split, the cash-drawer reconciliation (expected vs counted → over/short),
/// derived change, and report registration.
final class POSShiftReportTests: XCTestCase {

    func test_shift_summary_aggregates_sales_tenders_and_cash() {
        let session = posSession(status: "Closed", openingFloat: 100, closingAmount: 250)
        let invoices = [
            posInvoice(net: 80, tax: 20, grand: 100, qty: 2, change: 0, tenders: [("Cash", 100)]),
            posInvoice(net: 40, tax: 10, grand: 50, qty: 1, change: 10, tenders: [("Cash", 60)]),
            posInvoice(net: 80, tax: 20, grand: 100, qty: 1, change: 0, tenders: [("Card", 100)]),
        ]
        let s = POSShiftReportBuilder.summarize(session: session, invoices: invoices, profileName: "Main Till")

        XCTAssertEqual(s.transactions, 3)
        XCTAssertEqual(s.grossSales, 250, accuracy: 0.001)
        XCTAssertEqual(s.netSales, 200, accuracy: 0.001)
        XCTAssertEqual(s.tax, 50, accuracy: 0.001)
        XCTAssertEqual(s.itemsSold, 4, accuracy: 0.001)
        XCTAssertEqual(s.changeGiven, 10, accuracy: 0.001)

        // Tenders ordered Cash, Card; Cash = 100 + 60.
        XCTAssertEqual(s.tenders.map(\.type), ["Cash", "Card"])
        XCTAssertEqual(s.cashTaken, 160, accuracy: 0.001)
        XCTAssertEqual(s.totalTaken, 260, accuracy: 0.001)

        // Expected drawer = float 100 + cash 160 − change 10 = 250; counted 250 → square.
        XCTAssertEqual(s.expectedCash, 250, accuracy: 0.001)
        XCTAssertEqual(s.overShort ?? .nan, 0, accuracy: 0.001)
        XCTAssertEqual(s.profile, "Main Till")
    }

    func test_open_shift_has_no_counted_cash_or_over_short() {
        let session = posSession(status: "Open", openingFloat: 50, closingAmount: nil)
        let s = POSShiftReportBuilder.summarize(session: session, invoices: [])
        XCTAssertNil(s.countedCash)
        XCTAssertNil(s.overShort)
        XCTAssertEqual(s.expectedCash, 50, accuracy: 0.001)
        XCTAssertEqual(s.status, "Open")
    }

    func test_over_short_when_counted_differs_from_expected() {
        let session = posSession(status: "Closed", openingFloat: 0, closingAmount: 95)
        let invoices = [posInvoice(net: 100, tax: 0, grand: 100, qty: 1, change: 0, tenders: [("Cash", 100)])]
        let s = POSShiftReportBuilder.summarize(session: session, invoices: invoices)
        // Expected 100, counted 95 → short 5.
        XCTAssertEqual(s.overShort ?? .nan, -5, accuracy: 0.001)
    }

    func test_change_derived_from_paid_when_not_stamped() {
        let session = posSession(status: "Open", openingFloat: 0, closingAmount: nil)
        let invoice = posInvoiceNoChange(grand: 100, paid: 120, tenders: [("Cash", 120)])
        let s = POSShiftReportBuilder.summarize(session: session, invoices: [invoice])
        XCTAssertEqual(s.changeGiven, 20, accuracy: 0.001)   // 120 paid − 100 due
        XCTAssertEqual(s.expectedCash, 100, accuracy: 0.001) // 120 cash − 20 change
    }

    func test_pos_reports_registered() {
        for id in ["pos-x-report", "pos-z-report", "pos-shifts"] {
            XCTAssertNotNil(HubReports.report(forId: id), "POS report \(id) must be registered")
        }
    }

    // MARK: - Fixtures

    private func posSession(status: String, openingFloat: Double, closingAmount: Double?) -> Document {
        var fields: [String: FieldValue] = [
            "pos_profile": .string("PROFILE-1"),
            "status": .string(status),
            "opening_amount": .double(openingFloat),
            "opening_date": .dateTime(Date()),
        ]
        if let closingAmount {
            fields["closing_amount"] = .double(closingAmount)
            fields["closing_date"] = .dateTime(Date())
        }
        return doc(id: "SESSION-1", type: "POSSession", fields: fields, children: [:])
    }

    private func posInvoice(net: Double, tax: Double, grand: Double, qty: Double,
                            change: Double, tenders: [(String, Double)]) -> Document {
        doc(id: "POS", type: "POSInvoice", fields: [
            "net_total": .double(net),
            "total_taxes": .double(tax),
            "grand_total": .double(grand),
            "total_qty": .double(qty),
            "change_amount": .double(change),
            "paid_amount": .double(tenders.reduce(0) { $0 + $1.1 }),
        ], children: ["tenders": tenderRows(tenders)])
    }

    private func posInvoiceNoChange(grand: Double, paid: Double, tenders: [(String, Double)]) -> Document {
        doc(id: "POS", type: "POSInvoice", fields: [
            "grand_total": .double(grand),
            "paid_amount": .double(paid),
        ], children: ["tenders": tenderRows(tenders)])
    }

    private func tenderRows(_ tenders: [(String, Double)]) -> [ChildRow] {
        tenders.enumerated().map { index, tender in
            ChildRow(id: "t\(index)", rowIndex: index,
                     fields: ["tender_type": .string(tender.0), "amount": .double(tender.1)])
        }
    }

    private func doc(id: String, type: String, fields: [String: FieldValue], children: [String: [ChildRow]]) -> Document {
        Document(id: id, docType: type, company: "", status: "",
                 createdAt: Date(), updatedAt: Date(), syncVersion: 0, syncState: .local,
                 fields: fields, children: children)
    }
}
