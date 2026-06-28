import XCTest
import MercantisCore
@testable import Mercantis_Hub

/// Phase 3 (Accounting Autopilot) — guards for compliance & accountant
/// collaboration: tax-return box maths, the year-end closing entry (always
/// balanced, profit/loss rolled to retained earnings), the books-lock rule, the
/// report-pack writer, and DocType registration.
final class ComplianceFoundationTests: XCTestCase {

    // MARK: - Registration

    func test_compliance_doctypes_registered() {
        for id in ["TaxFiling", "TaxFilingBox"] {
            XCTAssertNotNil(HubManifest.docType(for: id), "Compliance DocType \(id) must be registered")
        }
        let filing = HubManifest.docType(for: "TaxFiling")
        XCTAssertTrue(Set(filing?.fields.map(\.key) ?? [])
            .isSuperset(of: ["period_label", "output_tax", "input_tax", "net_payable", "status"]))
    }

    // MARK: - Tax return boxes

    func test_tax_return_splits_output_and_input_and_nets() {
        let date = day(2026, 5, 15)
        let trans = [
            taxTrans(code: "VAT18", voucher: "SalesInvoice",    base: 1000, tax: 180, rate: 18, date: date),
            taxTrans(code: "VAT18", voucher: "PurchaseInvoice", base: 500,  tax: 90,  rate: 18, date: date),
        ]
        let ret = TaxReturnBuilder.build(taxTrans: trans, codeNames: ["VAT18": "Standard 18%"],
                                         style: .vat, from: nil, to: nil)
        XCTAssertEqual(ret.lines.count, 1)
        XCTAssertEqual(ret.totalOutputTax, 180, accuracy: 0.001)
        XCTAssertEqual(ret.totalInputTax, 90, accuracy: 0.001)
        XCTAssertEqual(ret.totalOutputBase, 1000, accuracy: 0.001)
        XCTAssertEqual(ret.netPayable, 90, accuracy: 0.001)   // owes 90
        XCTAssertFalse(ret.isEmpty)
    }

    func test_tax_return_respects_period_bounds() {
        let inRange  = taxTrans(code: "VAT", voucher: "SalesInvoice", base: 100, tax: 20, rate: 20, date: day(2026, 1, 15))
        let outRange = taxTrans(code: "VAT", voucher: "SalesInvoice", base: 100, tax: 20, rate: 20, date: day(2026, 3, 15))
        let ret = TaxReturnBuilder.build(taxTrans: [inRange, outRange], codeNames: [:],
                                         style: .vat, from: day(2026, 1, 1), to: day(2026, 1, 31))
        XCTAssertEqual(ret.totalOutputTax, 20, accuracy: 0.001)   // only the in-range row
    }

    func test_tax_return_reversals_net_out() {
        let date = day(2026, 2, 1)
        let trans = [
            taxTrans(code: "VAT", voucher: "SalesInvoice", base: 1000, tax: 200, rate: 20, date: date),
            // Cancelled invoice carries negative base / tax.
            taxTrans(code: "VAT", voucher: "SalesInvoice", base: -1000, tax: -200, rate: 20, date: date),
        ]
        let ret = TaxReturnBuilder.build(taxTrans: trans, codeNames: [:], style: .vat, from: nil, to: nil)
        XCTAssertTrue(ret.isEmpty, "fully reversed activity should leave no lines")
        XCTAssertEqual(ret.netPayable, 0, accuracy: 0.001)
    }

    func test_tax_style_vocabulary_and_regime_mapping() {
        XCTAssertEqual(TaxReturnBuilder.vocabulary(for: .vat).noun, "VAT")
        XCTAssertEqual(TaxReturnBuilder.vocabulary(for: .gstHst).noun, "GST / HST")
        XCTAssertEqual(TaxReturnBuilder.style(forRegime: "GST/HST"), .gstHst)
        XCTAssertEqual(TaxReturnBuilder.style(forRegime: "Sales Tax"), .salesTax)
        XCTAssertEqual(TaxReturnBuilder.style(forRegime: nil), .vat)   // default
    }

    // MARK: - Year-end close

    func test_year_end_close_rolls_profit_to_retained_earnings() {
        let balances = [
            YearEndCloseBuilder.AccountBalance(account: "Sales", debit: 0, credit: 1000),
            YearEndCloseBuilder.AccountBalance(account: "COGS",  debit: 400, credit: 0),
        ]
        XCTAssertEqual(YearEndCloseBuilder.netIncome(balances), 600, accuracy: 0.001)

        let je = YearEndCloseBuilder.closingEntry(
            plBalances: balances, retainedEarningsAccount: "RetainedEarnings",
            date: day(2026, 12, 31), yearName: "FY 2026", currency: "EUR")
        let rows = je?.children["accounts"] ?? []
        XCTAssertEqual(rows.count, 3, "two P&L accounts + the retained-earnings plug")
        XCTAssertEqual(doubleField(je?.fields["total_debit"]), doubleField(je?.fields["total_credit"]))
        // Income reversed to a debit; expense reversed to a credit.
        XCTAssertEqual(doubleField(row(rows, "Sales")?.fields["debit"]), 1000)
        XCTAssertEqual(doubleField(row(rows, "COGS")?.fields["credit"]), 400)
        // Profit credits retained earnings by the net.
        XCTAssertEqual(doubleField(row(rows, "RetainedEarnings")?.fields["credit"]), 600)
    }

    func test_year_end_close_loss_debits_retained_earnings() {
        let balances = [
            YearEndCloseBuilder.AccountBalance(account: "Sales", debit: 0, credit: 200),
            YearEndCloseBuilder.AccountBalance(account: "Rent",  debit: 500, credit: 0),
        ]
        let je = YearEndCloseBuilder.closingEntry(
            plBalances: balances, retainedEarningsAccount: "RetainedEarnings",
            date: day(2026, 12, 31), yearName: "FY 2026", currency: nil)
        let rows = je?.children["accounts"] ?? []
        XCTAssertEqual(doubleField(je?.fields["total_debit"]), doubleField(je?.fields["total_credit"]))
        XCTAssertEqual(doubleField(row(rows, "RetainedEarnings")?.fields["debit"]), 300)  // loss of 300
    }

    func test_year_end_close_no_activity_is_nil() {
        XCTAssertNil(YearEndCloseBuilder.closingEntry(
            plBalances: [], retainedEarningsAccount: "RetainedEarnings",
            date: Date(), yearName: "FY 2026", currency: nil))
        XCTAssertFalse(YearEndCloseBuilder.hasActivity([
            YearEndCloseBuilder.AccountBalance(account: "Sales", debit: 0, credit: 0)
        ]))
    }

    // MARK: - Books lock

    func test_books_lock_blocks_on_and_before_only() {
        let lock = day(2026, 3, 31)
        XCTAssertTrue(BooksLockPolicy.isLocked(postingDate: day(2026, 3, 15), lockDate: lock))
        XCTAssertTrue(BooksLockPolicy.isLocked(postingDate: day(2026, 3, 31), lockDate: lock))
        XCTAssertFalse(BooksLockPolicy.isLocked(postingDate: day(2026, 4, 1), lockDate: lock))
        XCTAssertFalse(BooksLockPolicy.isLocked(postingDate: day(2026, 3, 15), lockDate: nil))
    }

    // MARK: - Report pack writer

    func test_report_pack_writes_one_csv_per_report() throws {
        let reports = [
            HubReportPackExporter.NamedReport(name: "Trial Balance",
                                              result: ReportResult(columns: ["A", "B"], rows: [["1", "2"]])),
            HubReportPackExporter.NamedReport(name: "Profit & Loss",
                                              result: ReportResult(columns: ["X"], rows: [["9"]])),
        ]
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pack-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let urls = try HubReportPackExporter.write(reports, toDirectory: dir)
        XCTAssertEqual(urls.count, 2)
        for url in urls {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }
    }

    // MARK: - Helpers

    private func taxTrans(code: String, voucher: String, base: Double, tax: Double,
                          rate: Double, date: Date) -> Document {
        Document(id: "TT-\(code)-\(voucher)-\(Int(base))", docType: "TaxTrans", company: "", status: "",
                 createdAt: Date(), updatedAt: Date(), syncVersion: 0, syncState: .local,
                 fields: [
                    "tax": .string(code),
                    "voucher_type": .string(voucher),
                    "base_amount": .double(base),
                    "tax_amount": .double(tax),
                    "rate": .double(rate),
                    "posting_date": .date(date),
                 ], children: [:])
    }

    private func row(_ rows: [ChildRow], _ account: String) -> ChildRow? {
        rows.first { stringField($0.fields["account"]) == account }
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    private func stringField(_ value: FieldValue?) -> String? {
        if case .string(let s)? = value { return s }
        return nil
    }
    private func doubleField(_ value: FieldValue?) -> Double? {
        switch value { case .double(let d): return d; case .int(let i): return Double(i); default: return nil }
    }
}
