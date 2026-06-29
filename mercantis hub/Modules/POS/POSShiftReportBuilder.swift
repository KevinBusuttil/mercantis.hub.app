import Foundation
import MercantisCore

/// POS shift (X / Z) report maths. Summarises one POS Session and its sales into
/// the figures a cashier reconciles a till with: sales and tax, payments split
/// by tender, and the cash drawer (opening float + cash taken − change =
/// expected; counted − expected = over/short). Pure (no `DocumentEngine`) so the
/// arithmetic is unit-tested; `HubReports` loads the session + its POS sales and
/// renders the result.
///
/// X-Report = a mid-shift read of the open session (no counted cash yet).
/// Z-Report = the end-of-shift close, including the counted-cash reconciliation.
///
/// `nonisolated` (it's pure value-level work) so it's callable regardless of the
/// caller's actor isolation.
nonisolated enum POSShiftReportBuilder {

    struct TenderTotal: Equatable {
        let type: String
        let amount: Double
    }

    struct Summary: Equatable {
        let sessionId: String
        let profile: String
        let status: String
        let opened: Date?
        let closed: Date?
        let openingFloat: Double
        let transactions: Int
        let itemsSold: Double
        let grossSales: Double
        let netSales: Double
        let tax: Double
        let changeGiven: Double
        let tenders: [TenderTotal]
        let cashTaken: Double
        /// The cash counted at close (POS Session `closing_amount`); nil while the
        /// shift is still open.
        let countedCash: Double?

        var totalTaken: Double { round2(tenders.reduce(0) { $0 + $1.amount }) }
        /// What the drawer should hold: float + cash sales − change handed back.
        var expectedCash: Double { round2(openingFloat + cashTaken - changeGiven) }
        /// Counted − expected (positive = over, negative = short); nil until counted.
        var overShort: Double? { countedCash.map { round2($0 - expectedCash) } }
    }

    /// Canonical tender ordering for display; unknown types follow alphabetically.
    static let tenderOrder = ["Cash", "Card", "Other"]

    /// Summarise a session and its submitted POS sales. `profileName` is the
    /// resolved POS-profile display name (the caller looks it up); when nil the
    /// session's profile id is used.
    static func summarize(session: Document, invoices: [Document], profileName: String? = nil) -> Summary {
        var gross = 0.0, net = 0.0, tax = 0.0, qty = 0.0, change = 0.0
        var tenderByType: [String: Double] = [:]

        for invoice in invoices {
            let grand = double(invoice.fields["grand_total"]) ?? 0
            gross += grand
            net += double(invoice.fields["net_total"]) ?? 0
            tax += double(invoice.fields["total_taxes"]) ?? 0
            qty += double(invoice.fields["total_qty"]) ?? 0
            // Prefer the stamped change; otherwise derive it from what was paid.
            let paid = double(invoice.fields["paid_amount"]) ?? 0
            change += double(invoice.fields["change_amount"]) ?? max(0, round2(paid - grand))
            for row in invoice.children["tenders"] ?? [] {
                let type = string(row.fields["tender_type"]) ?? "Other"
                tenderByType[type, default: 0] += double(row.fields["amount"]) ?? 0
            }
        }

        var tenders: [TenderTotal] = []
        for type in tenderOrder where tenderByType[type] != nil {
            tenders.append(TenderTotal(type: type, amount: round2(tenderByType[type]!)))
        }
        for type in tenderByType.keys.sorted() where !tenderOrder.contains(type) {
            tenders.append(TenderTotal(type: type, amount: round2(tenderByType[type]!)))
        }

        return Summary(
            sessionId: session.id,
            profile: profileName ?? string(session.fields["pos_profile"]) ?? "POS",
            status: string(session.fields["status"]) ?? "Open",
            opened: date(session.fields["opening_date"]),
            closed: date(session.fields["closing_date"]),
            openingFloat: double(session.fields["opening_amount"]) ?? 0,
            transactions: invoices.count,
            itemsSold: round2(qty),
            grossSales: round2(gross),
            netSales: round2(net),
            tax: round2(tax),
            changeGiven: round2(change),
            tenders: tenders,
            cashTaken: round2(tenderByType["Cash"] ?? 0),
            countedCash: double(session.fields["closing_amount"])
        )
    }

    // MARK: - Helpers

    static func round2(_ value: Double) -> Double { (value * 100).rounded() / 100 }

    private static func double(_ value: FieldValue?) -> Double? {
        switch value {
        case .double(let d): return d
        case .int(let i):    return Double(i)
        default:             return nil
        }
    }
    private static func string(_ value: FieldValue?) -> String? {
        guard case .string(let s)? = value else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    private static func date(_ value: FieldValue?) -> Date? {
        switch value {
        case .date(let d), .dateTime(let d): return d
        default: return nil
        }
    }
}
