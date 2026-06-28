import Foundation
import MercantisCore

/// Phase 2 — matching a bank-statement line to existing records, and turning an
/// uncategorised line into a balanced Journal Entry. Pure (no `DocumentEngine`)
/// so the suggestion ranking and the GL shape are unit-tested; the view loads
/// the candidate documents and persists the produced Journal Entry.
enum BankMatchingService {

    struct Suggestion: Identifiable, Equatable {
        let id: String          // candidate document id
        let docType: String     // "PaymentEntry"
        let label: String
        let amount: Double
        let date: Date?
        /// 0…1 — higher is a closer match (exact amount + near date ranks top).
        let score: Double
    }

    /// Rank existing payments as candidate matches for a statement line, by
    /// amount equality first, then date proximity. Only same-magnitude amounts
    /// (within a cent) are offered.
    static func suggestions(
        forAmount amount: Double,
        date: Date?,
        payments: [Document]
    ) -> [Suggestion] {
        let target = abs(round2(amount))
        guard target > 0.0001 else { return [] }
        return payments.compactMap { doc -> Suggestion? in
            let paid = abs(round2(doubleValue(doc.fields["paid_amount"])
                               ?? doubleValue(doc.fields["received_amount"]) ?? 0))
            guard abs(paid - target) < 0.011 else { return nil }
            let pDate = dateValue(doc.fields["posting_date"])
            let dayGap = dayDistance(date, pDate)
            let score = max(0, 1.0 - Double(min(dayGap, 30)) / 30.0)
            let party = stringValue(doc.fields["party"]) ?? doc.id
            return Suggestion(id: doc.id, docType: "PaymentEntry",
                              label: "\(party) · \(money(paid))", amount: paid, date: pDate, score: score)
        }
        .sorted { $0.score > $1.score }
    }

    /// Build a balanced Journal Entry that categorises an uncategorised bank
    /// line: money in (amount > 0) → Dr Bank / Cr category; money out → Dr
    /// category / Cr Bank. The category account is whatever the owner picks
    /// (Bank Charges, Sales, Rent…), so they never touch debits/credits.
    static func categoriseJournalEntry(
        amount: Double,
        date: Date,
        bankGLAccount: String,
        categoryAccount: String,
        memo: String,
        currency: String?
    ) -> Document {
        let magnitude = abs(round2(amount))
        let moneyIn = amount > 0

        // money in: Dr bank, Cr category. money out: Dr category, Cr bank.
        let rows: [ChildRow] = [
            journalRow(index: 0,
                       account: moneyIn ? bankGLAccount : categoryAccount,
                       debit: magnitude, credit: 0),
            journalRow(index: 1,
                       account: moneyIn ? categoryAccount : bankGLAccount,
                       debit: 0, credit: magnitude),
        ]

        var fields: [String: FieldValue] = [
            "voucher_type": .string("Bank Entry"),
            "posting_date": .date(date),
            "total_debit": .double(magnitude),
            "total_credit": .double(magnitude),
            "user_remark": .string(memo.isEmpty ? "Bank transaction" : memo),
        ]
        if let currency, !currency.isEmpty { fields["company_currency"] = .string(currency) }

        return Document(
            id: "", docType: "JournalEntry", company: "", status: "Draft",
            createdAt: Date(), updatedAt: Date(), syncVersion: 0, syncState: .local,
            fields: fields, children: ["accounts": rows]
        )
    }

    // MARK: - Helpers

    static func journalRow(index: Int, account: String, debit: Double, credit: Double) -> ChildRow {
        ChildRow(id: "je-\(index)", rowIndex: index, fields: [
            "account": .string(account),
            "debit": .double(round2(debit)),
            "credit": .double(round2(credit)),
        ])
    }

    static func round2(_ value: Double) -> Double { (value * 100).rounded() / 100 }

    private static func money(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func dayDistance(_ a: Date?, _ b: Date?) -> Int {
        guard let a, let b else { return 30 }
        return abs(Calendar.current.dateComponents([.day], from: a, to: b).day ?? 30)
    }

    private static func doubleValue(_ value: FieldValue?) -> Double? {
        switch value {
        case .double(let d): return d
        case .int(let i):    return Double(i)
        case .string(let s): return Double(s)
        default:             return nil
        }
    }

    private static func stringValue(_ value: FieldValue?) -> String? {
        guard case .string(let s) = value else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private static func dateValue(_ value: FieldValue?) -> Date? {
        switch value {
        case .date(let d), .dateTime(let d): return d
        default: return nil
        }
    }
}
