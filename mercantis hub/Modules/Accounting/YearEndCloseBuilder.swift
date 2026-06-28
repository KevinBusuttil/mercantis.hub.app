import Foundation
import MercantisCore

/// Phase 3 (Accounting Autopilot) — builds the year-end **closing entry**: the
/// single balanced Journal Entry that zeroes every income and expense account
/// and rolls the year's net profit (or loss) into Retained Earnings, so the new
/// year starts with a clean Profit & Loss. Pure (no `DocumentEngine`) so the
/// double-entry maths is unit-tested; the guided view computes the P&L account
/// balances from the ledger and posts the produced entry through the normal
/// submit path.
///
/// The owner never sees debits and credits — they click "Close the year" and the
/// app records this for them, exactly as it does for opening balances.
enum YearEndCloseBuilder {

    /// One profit-or-loss account's debit / credit totals for the year, as read
    /// from the general ledger.
    struct AccountBalance: Equatable {
        let account: String
        let debit: Double
        let credit: Double

        /// The amount this account contributes to net income: income accounts
        /// carry a net credit (positive), expense accounts a net debit
        /// (negative). Contra accounts fall out naturally from the sign.
        var netIncomeContribution: Double { credit - debit }
    }

    /// Net profit (positive) or loss (negative) implied by the P&L balances.
    static func netIncome(_ balances: [AccountBalance]) -> Double {
        round2(balances.reduce(0) { $0 + $1.netIncomeContribution })
    }

    /// Whether there is any P&L activity worth closing.
    static func hasActivity(_ balances: [AccountBalance]) -> Bool {
        balances.contains { abs($0.debit) + abs($0.credit) > 0.0001 }
    }

    /// The closing Journal Entry's child rows: each P&L account is reversed
    /// (its debit/credit swapped) so it nets to zero, and the balancing figure —
    /// the year's net result — lands on `retainedEarningsAccount`. Returns an
    /// empty array when nothing needs closing.
    static func rows(plBalances: [AccountBalance], retainedEarningsAccount: String) -> [ChildRow] {
        let active = plBalances.filter { abs($0.debit) + abs($0.credit) > 0.0001 }
        guard !active.isEmpty else { return [] }

        var rows: [ChildRow] = []
        for balance in active {
            // Swap to zero the account: post its credit total as a debit and its
            // debit total as a credit.
            rows.append(row(index: rows.count, account: balance.account,
                            debit: round2(balance.credit), credit: round2(balance.debit)))
        }

        // Plug to Retained Earnings. Closing debits = Σ credit totals; closing
        // credits = Σ debit totals; their difference is net income.
        let closingDebits = active.reduce(0.0) { $0 + round2($1.credit) }
        let closingCredits = active.reduce(0.0) { $0 + round2($1.debit) }
        let plug = round2(closingDebits - closingCredits)   // = net income
        if abs(plug) > 0.0001 {
            if plug > 0 {
                // Profit increases equity → credit Retained Earnings.
                rows.append(row(index: rows.count, account: retainedEarningsAccount, debit: 0, credit: plug))
            } else {
                rows.append(row(index: rows.count, account: retainedEarningsAccount, debit: -plug, credit: 0))
            }
        }
        return rows
    }

    /// The balanced closing Journal Entry, ready to save + submit, or nil when
    /// there is no P&L activity to close.
    static func closingEntry(
        plBalances: [AccountBalance],
        retainedEarningsAccount: String,
        date: Date,
        yearName: String,
        currency: String?
    ) -> Document? {
        let children = rows(plBalances: plBalances, retainedEarningsAccount: retainedEarningsAccount)
        guard !children.isEmpty else { return nil }
        let total = children.reduce(0.0) { $0 + (doubleValue($1.fields["debit"]) ?? 0) }

        var fields: [String: FieldValue] = [
            "voucher_type": .string("Journal Entry"),
            "posting_date": .date(date),
            "total_debit": .double(round2(total)),
            "total_credit": .double(round2(total)),
            "user_remark": .string("Year-end close — \(yearName)"),
        ]
        if let currency, !currency.isEmpty { fields["company_currency"] = .string(currency) }

        return Document(
            id: "", docType: "JournalEntry", company: "", status: "Draft",
            createdAt: Date(), updatedAt: Date(), syncVersion: 0, syncState: .local,
            fields: fields, children: ["accounts": children]
        )
    }

    // MARK: - Helpers

    private static func row(index: Int, account: String, debit: Double, credit: Double) -> ChildRow {
        ChildRow(id: "yec-\(index)", rowIndex: index, fields: [
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
