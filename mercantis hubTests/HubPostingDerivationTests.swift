import XCTest
import MercantisCore
@testable import Mercantis_Hub

/// Phase 2 — unit tests for the atomic posting derivation.
///
/// `PostingCoordinator`'s row builders are pure functions of the source
/// document (plus pre-resolved accounts / cost basis), so they are tested here
/// directly — no database, no submit transaction. These lock in the invariants
/// the code review verified: balanced GL, reversal-to-zero, COGS at
/// moving-average cost (never the selling rate), the GRNI loop, and the
/// two-warehouse Stock Entry legs.
final class HubPostingDerivationTests: XCTestCase {

    // MARK: - Fixtures

    private func doc(
        _ id: String, _ docType: String, company: String = "TestCo",
        fields: [String: FieldValue], children: [String: [ChildRow]] = [:]
    ) -> Document {
        Document(
            id: id, docType: docType, company: company, status: "",
            createdAt: Date(), updatedAt: Date(), syncVersion: 0, syncState: .local,
            fields: fields, children: children
        )
    }

    private func row(_ idx: Int, _ fields: [String: FieldValue]) -> ChildRow {
        ChildRow(id: "r\(idx)", rowIndex: idx, fields: fields)
    }

    private func dbl(_ v: FieldValue?) -> Double? {
        switch v {
        case .double(let d): return d
        case .int(let i):    return Double(i)
        default:             return nil
        }
    }

    private func str(_ v: FieldValue?) -> String? {
        if case .string(let s)? = v { return s }
        return nil
    }

    /// Assert an optional amount equals `expected`; a missing value (nil) fails
    /// rather than silently coalescing — `XCTAssertEqual(_:_:accuracy:)` itself
    /// can't take a `Double?`.
    private func assertAmount(
        _ actual: Double?, _ expected: Double, accuracy: Double = 0.001,
        _ message: String = "", file: StaticString = #filePath, line: UInt = #line
    ) {
        guard let actual else {
            return XCTFail("expected \(expected) but the value was missing. \(message)", file: file, line: line)
        }
        XCTAssertEqual(actual, expected, accuracy: accuracy, file: file, line: line)
    }

    private func gl(_ rows: [Document]) -> [Document] { rows.filter { $0.docType == "GLEntry" } }
    private func sle(_ rows: [Document]) -> [Document] { rows.filter { $0.docType == "StockLedgerEntry" } }
    private func totalDebit(_ rows: [Document]) -> Double { gl(rows).reduce(0) { $0 + (dbl($1.fields["debit"]) ?? 0) } }
    private func totalCredit(_ rows: [Document]) -> Double { gl(rows).reduce(0) { $0 + (dbl($1.fields["credit"]) ?? 0) } }
    private func glFor(_ rows: [Document], account: String) -> Document? {
        gl(rows).first { str($0.fields["account"]) == account }
    }

    // MARK: - Journal Entry: balanced + reversal nets to zero

    func test_journalEntry_balancedAndReversalSwapsLegs() {
        let je = doc("JE-1", "JournalEntry", fields: ["posting_date": .date(Date())], children: ["accounts": [
            row(0, ["account": .string("Cash"),  "debit": .double(100), "credit": .double(0)]),
            row(1, ["account": .string("Sales"), "debit": .double(0),   "credit": .double(100)]),
        ]])

        let posted = PostingCoordinator.journalEntryRows(je, reversal: false)
        XCTAssertEqual(gl(posted).count, 2)
        XCTAssertEqual(totalDebit(posted), 100, accuracy: 0.001)
        XCTAssertEqual(totalCredit(posted), 100, accuracy: 0.001)

        let reversed = PostingCoordinator.journalEntryRows(je, reversal: true)
        // Reversal swaps debit/credit, so the Cash leg flips Dr 100 → Cr 100.
        let cashRev = glFor(reversed, account: "Cash")
        assertAmount(dbl(cashRev?.fields["credit"]), 100)
        assertAmount(dbl(cashRev?.fields["debit"]), 0)
        XCTAssertEqual(totalDebit(reversed), 100, accuracy: 0.001)
        XCTAssertEqual(totalCredit(reversed), 100, accuracy: 0.001)
        // Reversal rows are id-suffixed so they never collide with the originals.
        XCTAssertTrue(reversed.allSatisfy { $0.id.hasSuffix("-reversal") })
    }

    // MARK: - Sales Invoice: Dr AR gross / Cr Income net / Cr VAT

    func test_salesInvoice_grossAR_netIncome_vat_andSubledger() {
        let si = doc("SI-1", "SalesInvoice", fields: [
            "debit_to":         .string("AR"),
            "income_account":   .string("Sales"),
            "transaction_date": .date(Date()),
            "grand_total":      .double(115),
            "net_total":        .double(100),
            "customer":         .string("CUST-1"),
        ], children: ["taxes": [
            row(0, ["tax_amount": .double(15), "taxable_amount": .double(100), "tax_account": .string("VAT")]),
        ]])

        let rows = PostingCoordinator.salesInvoiceRows(si, reversal: false, fallbackVatAccount: nil)
        XCTAssertEqual(totalDebit(rows), totalCredit(rows), accuracy: 0.001)
        assertAmount(dbl(glFor(rows, account: "AR")?.fields["debit"]), 115)
        assertAmount(dbl(glFor(rows, account: "Sales")?.fields["credit"]), 100)
        assertAmount(dbl(glFor(rows, account: "VAT")?.fields["credit"]), 15)
        // Customer subledger row is booked at gross.
        let custTrans = rows.first { $0.docType == "CustTrans" }
        assertAmount(dbl(custTrans?.fields["amount"]), 115)
    }

    // MARK: - COGS at moving-average cost, never the selling rate

    func test_salesDelivery_cogsUsesMovingAverageNotSellingRate() {
        // Line carries selling rate 50 — it must be ignored. COGS uses the
        // pre-resolved moving-average cost basis (8/unit).
        let sd = doc("SD-1", "SalesDelivery", fields: ["set_warehouse": .string("WH")], children: ["items": [
            row(0, ["item": .string("ITEM-1"), "qty": .double(5), "warehouse": .string("WH"), "rate": .double(50)]),
        ]])

        let rows = PostingCoordinator.stockIssueRows(
            sd, voucherType: "SalesDelivery", reversal: false,
            costBasis: [0: 8], cogsAccount: "COGS", inventoryAccount: "Stock"
        )
        let issue = sle(rows).first
        assertAmount(dbl(issue?.fields["qty_change"]), -5)        // stock leaves
        assertAmount(dbl(issue?.fields["valuation_rate"]), 8)
        // 5 × 8 = 40, NOT 5 × 50 (the selling rate).
        assertAmount(dbl(glFor(rows, account: "COGS")?.fields["debit"]), 40)
        assertAmount(dbl(glFor(rows, account: "Stock")?.fields["credit"]), 40)
        XCTAssertEqual(totalDebit(rows), totalCredit(rows), accuracy: 0.001)
    }

    func test_stockIssue_reversalNetsToZero() {
        let sd = doc("SD-2", "SalesDelivery", fields: ["set_warehouse": .string("WH")], children: ["items": [
            row(0, ["item": .string("ITEM-1"), "qty": .double(5), "warehouse": .string("WH")]),
        ]])
        let posted = PostingCoordinator.stockIssueRows(
            sd, voucherType: "SalesDelivery", reversal: false,
            costBasis: [0: 8], cogsAccount: "COGS", inventoryAccount: "Stock")
        let reversed = PostingCoordinator.stockIssueRows(
            sd, voucherType: "SalesDelivery", reversal: true,
            costBasis: [0: 8], cogsAccount: "COGS", inventoryAccount: "Stock")

        let qtyNet = (dbl(sle(posted).first?.fields["qty_change"]) ?? 0)
            + (dbl(sle(reversed).first?.fields["qty_change"]) ?? 0)
        XCTAssertEqual(qtyNet, 0, accuracy: 0.001)
        // COGS debited on submit, credited on reversal at the same cost → nets out.
        let cogsNet = (dbl(glFor(posted, account: "COGS")?.fields["debit"]) ?? 0)
            - (dbl(glFor(reversed, account: "COGS")?.fields["credit"]) ?? 0)
        XCTAssertEqual(cogsNet, 0, accuracy: 0.001)
    }

    func test_uomConversion_scalesQtyAndCogsToStockUnit() {
        // 2 cases delivered; a case = 12 stock units; unit cost 5.
        let sd = doc("SD-3", "SalesDelivery", fields: ["set_warehouse": .string("WH")], children: ["items": [
            row(0, ["item": .string("ITEM-1"), "qty": .double(2), "warehouse": .string("WH"), "uom": .string("Case")]),
        ]])
        let rows = PostingCoordinator.stockIssueRows(
            sd, voucherType: "SalesDelivery", reversal: false,
            costBasis: [0: 5], cogsAccount: "COGS", inventoryAccount: "Stock",
            uomFactors: [0: 12])
        // Stock leaves in stock units: 2 × 12 = 24.
        assertAmount(dbl(sle(rows).first?.fields["qty_change"]), -24)
        // COGS at unit cost: 24 × 5 = 120.
        assertAmount(dbl(glFor(rows, account: "COGS")?.fields["debit"]), 120)
    }

    // MARK: - GRNI loop: receipt accrues, invoice clears, nets to zero

    func test_grniLoop_receiptAccruesAndInvoiceClears() {
        let pr = doc("PR-1", "PurchaseReceipt", fields: [
            "set_warehouse": .string("WH"), "transaction_date": .date(Date()),
        ], children: ["items": [
            row(0, ["item": .string("ITEM-1"), "qty": .double(10), "rate": .double(3), "warehouse": .string("WH")]),
        ]])
        let receipt = PostingCoordinator.purchaseReceiptRows(
            pr, reversal: false, stockItemFlags: ["ITEM-1": true],
            inventoryAccount: "Stock", grniAccount: "GRNI")
        assertAmount(dbl(glFor(receipt, account: "Stock")?.fields["debit"]), 30)
        assertAmount(dbl(glFor(receipt, account: "GRNI")?.fields["credit"]), 30)
        assertAmount(dbl(sle(receipt).first?.fields["qty_change"]), 10)   // stock in

        // Invoice for the same goods clears GRNI (Dr GRNI / Cr AP), no expense.
        let pi = doc("PI-1", "PurchaseInvoice", fields: [
            "credit_to":        .string("AP"),
            "expense_account":  .string("Expense"),
            "transaction_date": .date(Date()),
            "grand_total":      .double(30),
            "net_total":        .double(30),
            "supplier":         .string("SUP-1"),
        ], children: ["items": [
            row(0, ["item": .string("ITEM-1"), "amount": .double(30)]),
        ]])
        let invoice = PostingCoordinator.purchaseInvoiceRows(
            pi, reversal: false, fallbackVatAccount: nil,
            grniAccount: "GRNI", stockItemFlags: ["ITEM-1": true])
        assertAmount(dbl(glFor(invoice, account: "GRNI")?.fields["debit"]), 30)
        assertAmount(dbl(glFor(invoice, account: "AP")?.fields["credit"]), 30)
        XCTAssertNil(glFor(invoice, account: "Expense"))   // pure-stock invoice → no expense leg
        XCTAssertEqual(totalDebit(invoice), totalCredit(invoice), accuracy: 0.001)

        // GRNI credited on receipt, debited on invoice → the loop nets to zero.
        let grniNet = (dbl(glFor(receipt, account: "GRNI")?.fields["credit"]) ?? 0)
            - (dbl(glFor(invoice, account: "GRNI")?.fields["debit"]) ?? 0)
        XCTAssertEqual(grniNet, 0, accuracy: 0.001)
    }

    func test_purchaseReceipt_withoutGrniAccount_postsStockOnly() {
        let pr = doc("PR-2", "PurchaseReceipt", fields: [
            "set_warehouse": .string("WH"), "transaction_date": .date(Date()),
        ], children: ["items": [
            row(0, ["item": .string("ITEM-1"), "qty": .double(10), "rate": .double(3), "warehouse": .string("WH")]),
        ]])
        let rows = PostingCoordinator.purchaseReceiptRows(
            pr, reversal: false, stockItemFlags: ["ITEM-1": true],
            inventoryAccount: "Stock", grniAccount: nil)
        XCTAssertEqual(sle(rows).count, 1)   // stock still moves
        XCTAssertTrue(gl(rows).isEmpty)      // no GL when GRNI unmapped — legacy parity
    }

    func test_purchaseInvoice_serviceLineExpensesRatherThanClearsGRNI() {
        // is_stock_item == false → the line is a service, so it Dr Expense even
        // with a GRNI account mapped.
        let pi = doc("PI-2", "PurchaseInvoice", fields: [
            "credit_to":        .string("AP"),
            "expense_account":  .string("Expense"),
            "transaction_date": .date(Date()),
            "grand_total":      .double(40),
            "net_total":        .double(40),
            "supplier":         .string("SUP-1"),
        ], children: ["items": [
            row(0, ["item": .string("SVC-1"), "amount": .double(40)]),
        ]])
        let invoice = PostingCoordinator.purchaseInvoiceRows(
            pi, reversal: false, fallbackVatAccount: nil,
            grniAccount: "GRNI", stockItemFlags: ["SVC-1": false])
        assertAmount(dbl(glFor(invoice, account: "Expense")?.fields["debit"]), 40)
        XCTAssertNil(glFor(invoice, account: "GRNI"))    // nothing to clear
        XCTAssertEqual(totalDebit(invoice), totalCredit(invoice), accuracy: 0.001)
    }

    // MARK: - Stock Entry: two-warehouse transfer, no GL

    func test_stockEntry_transferHasOutAndInLegsNoGL() {
        let se = doc("SE-1", "StockEntry", fields: [
            "posting_date": .date(Date()), "purpose": .string("Material Transfer"),
        ], children: ["items": [
            row(0, ["item": .string("ITEM-1"), "qty": .double(4),
                    "source_warehouse": .string("WH-A"), "target_warehouse": .string("WH-B"),
                    "valuation_rate": .double(5)]),
        ]])
        let rows = PostingCoordinator.stockEntryRows(se, reversal: false)
        XCTAssertTrue(gl(rows).isEmpty)   // a transfer posts no GL
        let legs = sle(rows)
        XCTAssertEqual(legs.count, 2)
        let out = legs.first { str($0.fields["warehouse"]) == "WH-A" }
        let into = legs.first { str($0.fields["warehouse"]) == "WH-B" }
        assertAmount(dbl(out?.fields["qty_change"]), -4)    // leaves source
        assertAmount(dbl(into?.fields["qty_change"]), 4)    // enters target
        XCTAssertEqual(str(out?.fields["trans_type"]) ?? "", "Transfer")
    }
}
