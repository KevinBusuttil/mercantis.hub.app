import XCTest
import MercantisCore
@testable import Mercantis_Hub

/// Phase 2 (Accounting Autopilot) — guards for opening balances + banking:
/// statement CSV parsing, match suggestions, the categorise/opening-balance
/// Journal Entry shapes (always balanced), and DocType registration.
final class BankingFoundationTests: XCTestCase {

    // MARK: - Registration

    func test_banking_doctypes_registered() {
        for id in ["BankAccount", "BankStatementLine", "BankReconciliation"] {
            XCTAssertNotNil(HubManifest.docType(for: id), "Banking DocType \(id) must be registered")
        }
        let bank = HubManifest.docType(for: "BankAccount")
        XCTAssertTrue(Set(bank?.fields.map(\.key) ?? []).isSuperset(of: ["account_name", "gl_account", "account_kind"]))
    }

    // MARK: - CSV importer

    func test_csv_two_column_money_in_out() {
        let csv = """
        Date,Description,Money Out,Money In,Balance
        2026-01-05,Coffee Supplier,45.00,,955.00
        2026-01-06,Customer Payment,,500.00,1455.00
        """
        let result = BankStatementCSVImporter.parseAutodetecting(csv)
        XCTAssertNotNil(result)
        let lines = result!.lines
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].amount, -45.00, accuracy: 0.001)   // money out → negative
        XCTAssertEqual(lines[1].amount, 500.00, accuracy: 0.001)   // money in → positive
        XCTAssertEqual(lines[1].balance, 1455.00)
    }

    func test_csv_single_signed_amount_and_date_formats() {
        let csv = """
        Date,Description,Amount
        05/01/2026,Bank Charge,-12.50
        """
        let result = BankStatementCSVImporter.parseAutodetecting(csv)
        XCTAssertEqual(result?.lines.first?.amount, -12.50)
        XCTAssertNotNil(result?.lines.first?.date)
    }

    func test_amount_parsing_edge_cases() {
        XCTAssertEqual(BankStatementCSVImporter.parseAmount("(123.45)"), -123.45)
        XCTAssertEqual(BankStatementCSVImporter.parseAmount("€1,234.56"), 1234.56)
        XCTAssertEqual(BankStatementCSVImporter.parseAmount("-50"), -50)
        XCTAssertNil(BankStatementCSVImporter.parseAmount(""))
    }

    // MARK: - Matching

    func test_match_suggestions_rank_amount_then_date() {
        let date = Date()
        let exact = payment(id: "PE-1", amount: 500, party: "Acme", date: date)
        let off = payment(id: "PE-2", amount: 499, party: "Other", date: date)
        let suggestions = BankMatchingService.suggestions(forAmount: 500, date: date, payments: [exact, off])
        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions.first?.id, "PE-1")
    }

    // MARK: - Categorise Journal Entry

    func test_categorise_money_out_debits_category_credits_bank() {
        let je = BankMatchingService.categoriseJournalEntry(
            amount: -45, date: Date(), bankGLAccount: "Bank",
            categoryAccount: "BankCharges", memo: "fee", currency: "EUR")
        let rows = je.children["accounts"] ?? []
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(doubleField(je.fields["total_debit"]), doubleField(je.fields["total_credit"]))
        // Money out: category is debited, bank is credited.
        let debited = rows.first { (doubleField($0.fields["debit"]) ?? 0) > 0 }
        let credited = rows.first { (doubleField($0.fields["credit"]) ?? 0) > 0 }
        XCTAssertEqual(stringField(debited?.fields["account"]), "BankCharges")
        XCTAssertEqual(stringField(credited?.fields["account"]), "Bank")
    }

    func test_categorise_money_in_debits_bank_credits_category() {
        let je = BankMatchingService.categoriseJournalEntry(
            amount: 500, date: Date(), bankGLAccount: "Bank",
            categoryAccount: "Sales", memo: "sale", currency: "EUR")
        let rows = je.children["accounts"] ?? []
        let debited = rows.first { (doubleField($0.fields["debit"]) ?? 0) > 0 }
        XCTAssertEqual(stringField(debited?.fields["account"]), "Bank")
    }

    // MARK: - Opening balances

    func test_opening_balance_journal_is_balanced_with_equity_plug() {
        let lines = [
            OpeningBalanceBuilder.Line(account: "Bank", amount: 1000, isDebit: true),
            OpeningBalanceBuilder.Line(account: "Creditors", amount: 300, isDebit: false),
        ]
        let je = OpeningBalanceBuilder.journalEntry(
            lines: lines, equityAccount: "OpeningBalanceEquity", date: Date(), currency: "EUR")
        let rows = je.children["accounts"] ?? []
        XCTAssertEqual(rows.count, 3, "two figures + the equity balancing line")
        XCTAssertEqual(doubleField(je.fields["total_debit"]), 1000)
        XCTAssertEqual(doubleField(je.fields["total_debit"]), doubleField(je.fields["total_credit"]))
        // Equity plug = assets(1000) - liabilities(300) = 700, credited.
        let equity = rows.first { stringField($0.fields["account"]) == "OpeningBalanceEquity" }
        XCTAssertEqual(doubleField(equity?.fields["credit"]), 700)
    }

    func test_opening_balance_hasFigures() {
        XCTAssertFalse(OpeningBalanceBuilder.hasFigures([]))
        XCTAssertTrue(OpeningBalanceBuilder.hasFigures([.init(account: "Bank", amount: 5, isDebit: true)]))
    }

    // MARK: - Fixtures / helpers

    private func payment(id: String, amount: Double, party: String, date: Date) -> Document {
        Document(id: id, docType: "PaymentEntry", company: "", status: "",
                 createdAt: Date(), updatedAt: Date(), syncVersion: 0, syncState: .local,
                 fields: ["paid_amount": .double(amount), "party": .string(party), "posting_date": .date(date)],
                 children: [:])
    }

    private func stringField(_ value: FieldValue?) -> String? {
        if case .string(let s)? = value { return s }
        return nil
    }
    private func doubleField(_ value: FieldValue?) -> Double? {
        switch value { case .double(let d): return d; case .int(let i): return Double(i); default: return nil }
    }
}
