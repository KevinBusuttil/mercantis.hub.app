import Foundation
import MercantisCore

/// Phase 2 — turns a non-accountant owner's opening figures (bank balance,
/// unpaid customer/supplier totals, inventory value, loans, owner's money) into
/// a single balanced opening Journal Entry. Pure (no `DocumentEngine`) so the
/// double-entry maths and the balancing-to-equity logic are unit-tested; the
/// wizard view posts the produced Journal Entry through the normal submit path.
enum OpeningBalanceBuilder {

    /// One opening figure entered by the owner, already resolved to a ledger
    /// account and a side. `isDebit` true for assets (what you own / are owed),
    /// false for liabilities (what you owe).
    struct Line: Equatable {
        let account: String
        let amount: Double
        let isDebit: Bool
    }

    /// The non-zero lines plus the balancing entry to the equity account, as
    /// Journal Entry child rows. The balancing figure (the owner's starting
    /// capital / accumulated position) goes to `equityAccount` so the entry is
    /// always balanced — the owner never computes it.
    static func rows(lines: [Line], equityAccount: String) -> [ChildRow] {
        let active = lines.filter { abs(round2($0.amount)) > 0.0001 }
        var debitTotal = 0.0
        var creditTotal = 0.0
        var rows: [ChildRow] = []
        for line in active {
            let amount = round2(line.amount)
            if line.isDebit {
                debitTotal += amount
                rows.append(row(index: rows.count, account: line.account, debit: amount, credit: 0))
            } else {
                creditTotal += amount
                rows.append(row(index: rows.count, account: line.account, debit: 0, credit: amount))
            }
        }
        let diff = round2(debitTotal - creditTotal)
        if abs(diff) > 0.0001 {
            // More assets than liabilities → credit equity (positive capital).
            if diff > 0 {
                rows.append(row(index: rows.count, account: equityAccount, debit: 0, credit: diff))
            } else {
                rows.append(row(index: rows.count, account: equityAccount, debit: -diff, credit: 0))
            }
        }
        return rows
    }

    /// The balanced opening Journal Entry document, ready to save + submit.
    static func journalEntry(
        lines: [Line],
        equityAccount: String,
        date: Date,
        currency: String?
    ) -> Document {
        let children = rows(lines: lines, equityAccount: equityAccount)
        let total = children.reduce(0.0) { $0 + (doubleValue($1.fields["debit"]) ?? 0) }

        var fields: [String: FieldValue] = [
            "voucher_type": .string("Journal Entry"),
            "posting_date": .date(date),
            "total_debit": .double(round2(total)),
            "total_credit": .double(round2(total)),
            "user_remark": .string("Opening balances"),
        ]
        if let currency, !currency.isEmpty { fields["company_currency"] = .string(currency) }

        return Document(
            id: "", docType: "JournalEntry", company: "", status: "Draft",
            createdAt: Date(), updatedAt: Date(), syncVersion: 0, syncState: .local,
            fields: fields, children: ["accounts": children]
        )
    }

    /// Whether the entered lines net to a meaningful opening position.
    static func hasFigures(_ lines: [Line]) -> Bool {
        lines.contains { abs(round2($0.amount)) > 0.0001 }
    }

    // MARK: - Helpers

    private static func row(index: Int, account: String, debit: Double, credit: Double) -> ChildRow {
        ChildRow(id: "ob-\(index)", rowIndex: index, fields: [
            "account": .string(account),
            "debit": .double(round2(debit)),
            "credit": .double(round2(credit)),
        ])
    }

    static func round2(_ value: Double) -> Double { (value * 100).rounded() / 100 }

    private static func doubleValue(_ value: FieldValue?) -> Double? {
        switch value {
        case .double(let d): return d
        case .int(let i):    return Double(i)
        default:             return nil
        }
    }
}
