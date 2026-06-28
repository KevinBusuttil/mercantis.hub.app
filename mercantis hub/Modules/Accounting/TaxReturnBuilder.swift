import Foundation
import MercantisCore

/// Phase 3 (Accounting Autopilot) — turns the `TaxTrans` subledger into a plain
/// tax **return**: the few numbers an owner actually files (tax collected on
/// sales, tax paid on purchases, and the net to pay or reclaim) for a chosen
/// period. Pure (no `DocumentEngine`) so the box maths is unit-tested; the
/// guided view loads the `TaxTrans` rows and renders the result.
///
/// It distils the same source the VAT Summary report reads, but bounded to a
/// filing period and reduced to the headline boxes — so a non-accountant sees
/// "you owe €X" instead of a ledger.
enum TaxReturnBuilder {

    /// One tax band (rate / code) within the period, split output vs input.
    struct Line: Equatable {
        let code: String
        let name: String
        var rate: Double
        var outputBase: Double   // taxable sales at this band
        var outputTax: Double    // tax collected on those sales
        var inputBase: Double    // taxable purchases at this band
        var inputTax: Double     // tax paid on those purchases
    }

    /// A complete return for a period, with the headline totals derived from the
    /// per-band lines.
    struct Return: Equatable {
        let style: HubTaxStyle
        let periodStart: Date?
        let periodEnd: Date?
        let lines: [Line]

        var totalOutputBase: Double { round2(lines.reduce(0) { $0 + $1.outputBase }) }
        var totalOutputTax:  Double { round2(lines.reduce(0) { $0 + $1.outputTax }) }
        var totalInputBase:  Double { round2(lines.reduce(0) { $0 + $1.inputBase }) }
        var totalInputTax:   Double { round2(lines.reduce(0) { $0 + $1.inputTax }) }

        /// Net tax due (positive = pay the authority) or reclaimable (negative).
        var netPayable: Double { round2(totalOutputTax - totalInputTax) }

        /// True when there is nothing to file (no taxed activity in the period).
        var isEmpty: Bool { lines.isEmpty }
    }

    /// The source voucher types that represent tax *collected* on sales
    /// (output). Everything else (purchases, expenses) is input tax. Matches the
    /// classification used by `HubReports.runVatSummary`.
    static let outputVoucherTypes: Set<String> = ["SalesInvoice", "POSInvoice", "POSSale"]

    /// Build the return from raw `TaxTrans` documents, bounded to
    /// `[from, to]` (inclusive; either bound may be nil for open-ended).
    /// `codeNames` maps a tax-code id to its friendly name. Reversal rows carry
    /// negative base / tax so cancelled invoices net out automatically.
    static func build(
        taxTrans: [Document],
        codeNames: [String: String],
        style: HubTaxStyle,
        from: Date?,
        to: Date?
    ) -> Return {
        var byCode: [String: Line] = [:]
        var order: [String] = []

        for entry in taxTrans {
            if let date = asDate(entry.fields["posting_date"]) {
                if let from, date < startOfDay(from) { continue }
                if let to, date > endOfDay(to) { continue }
            }
            let code = asString(entry.fields["tax"]) ?? "(none)"
            let base = asDouble(entry.fields["base_amount"]) ?? 0
            let tax  = asDouble(entry.fields["tax_amount"]) ?? 0
            let rate = asDouble(entry.fields["rate"]) ?? 0
            let voucher = asString(entry.fields["voucher_type"]) ?? ""
            let isOutput = outputVoucherTypes.contains(voucher)

            if byCode[code] == nil {
                order.append(code)
                byCode[code] = Line(code: code, name: codeNames[code] ?? code, rate: rate,
                                    outputBase: 0, outputTax: 0, inputBase: 0, inputTax: 0)
            }
            var line = byCode[code]!
            if rate != 0 { line.rate = rate }
            if isOutput {
                line.outputBase += base
                line.outputTax  += tax
            } else {
                line.inputBase += base
                line.inputTax  += tax
            }
            byCode[code] = line
        }

        // Keep only bands with any activity, rounded for display stability.
        let lines: [Line] = order.compactMap { code in
            guard var line = byCode[code] else { return nil }
            line.outputBase = round2(line.outputBase)
            line.outputTax  = round2(line.outputTax)
            line.inputBase  = round2(line.inputBase)
            line.inputTax   = round2(line.inputTax)
            let touched = abs(line.outputBase) + abs(line.outputTax)
                + abs(line.inputBase) + abs(line.inputTax)
            return touched > 0.0001 ? line : nil
        }
        return Return(style: style, periodStart: from, periodEnd: to, lines: lines)
    }

    /// Jurisdiction-aware vocabulary for the headline boxes, so the same maths
    /// reads as VAT, Sales Tax, or GST/HST depending on the business.
    struct Vocabulary: Equatable {
        let noun: String        // "VAT"
        let outputLabel: String // "VAT on sales (collected)"
        let inputLabel: String  // "VAT on purchases (reclaimable)"
        let netDueLabel: String // "VAT to pay"
        let netReclaimLabel: String
    }

    static func vocabulary(for style: HubTaxStyle) -> Vocabulary {
        switch style {
        case .vat:
            return Vocabulary(noun: "VAT",
                              outputLabel: "VAT on sales (collected)",
                              inputLabel: "VAT on purchases (reclaimable)",
                              netDueLabel: "VAT to pay",
                              netReclaimLabel: "VAT to reclaim")
        case .salesTax:
            return Vocabulary(noun: "Sales Tax",
                              outputLabel: "Sales tax collected",
                              inputLabel: "Sales tax paid",
                              netDueLabel: "Sales tax to remit",
                              netReclaimLabel: "Sales tax credit")
        case .gstHst:
            return Vocabulary(noun: "GST / HST",
                              outputLabel: "GST/HST collected",
                              inputLabel: "Input tax credits (ITC)",
                              netDueLabel: "GST/HST to remit",
                              netReclaimLabel: "GST/HST refund")
        case .none:
            return Vocabulary(noun: "Tax",
                              outputLabel: "Tax collected",
                              inputLabel: "Tax paid",
                              netDueLabel: "Tax to pay",
                              netReclaimLabel: "Tax to reclaim")
        }
    }

    /// Map a stored Business-Profile tax-regime label to a tax style, defaulting
    /// to VAT (the most common). Tolerant of free-text variations.
    static func style(forRegime regime: String?) -> HubTaxStyle {
        let r = (regime ?? "").lowercased()
        if r.contains("gst") || r.contains("hst") { return .gstHst }
        if r.contains("sales") { return .salesTax }
        if r.contains("vat")  { return .vat }
        if r.isEmpty { return .vat }
        return .vat
    }

    // MARK: - Helpers

    static func round2(_ value: Double) -> Double { (value * 100).rounded() / 100 }

    private static func startOfDay(_ date: Date) -> Date { Calendar.current.startOfDay(for: date) }
    private static func endOfDay(_ date: Date) -> Date {
        let start = Calendar.current.startOfDay(for: date)
        return Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }

    private static func asDouble(_ v: FieldValue?) -> Double? {
        switch v {
        case .double(let d): return d
        case .int(let i):    return Double(i)
        case .string(let s): return Double(s)
        default:             return nil
        }
    }
    private static func asString(_ v: FieldValue?) -> String? {
        if case .string(let s) = v {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        return nil
    }
    private static func asDate(_ v: FieldValue?) -> Date? {
        switch v {
        case .date(let d), .dateTime(let d): return d
        default: return nil
        }
    }
}
