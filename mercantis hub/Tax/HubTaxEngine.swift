import Foundation

/// Phase 2 (VAT / Tax Foundation) — the shared, dependency-free tax engine.
///
/// `HubTaxEngine` is intentionally pure: it knows nothing about
/// `DocumentEngine`, persistence, or SwiftUI. It takes already-resolved
/// line amounts plus their effective tax code and a rate lookup, then
/// produces the document's net total, one tax row per distinct tax code,
/// the total tax, and the grand total.
///
/// Keeping it pure is what lets Sales Invoice, Purchase Invoice, and (later)
/// POS all reuse the exact same calculation: each caller resolves its own
/// line/party/item tax defaults, then hands flat numbers to this engine.
public enum HubTaxEngine {

    /// Resolved information about a single tax code, as needed for
    /// calculation. Built by the caller from a `TaxCode` master record.
    public struct TaxRateInfo: Equatable, Sendable {
        public let codeId: String
        public let description: String
        /// Percentage, e.g. `18` for 18% VAT. `0` for Zero / Exempt codes.
        public let rate: Double
        /// Posting account for the tax amount (output/input VAT account).
        public let account: String?
        /// "VAT", "SalesTax", … — mirrors `TaxTrans.tax_type`.
        public let taxType: String

        public init(
            codeId: String,
            description: String,
            rate: Double,
            account: String?,
            taxType: String = "VAT"
        ) {
            self.codeId = codeId
            self.description = description
            self.rate = rate
            self.account = account
            self.taxType = taxType
        }
    }

    /// One taxable line as seen by the engine: its net (pre-tax) amount and
    /// the tax code that applies to it (already resolved through the
    /// line → item → document → party fallback chain by the caller).
    public struct TaxLine: Equatable, Sendable {
        public let netAmount: Double
        public let taxCodeId: String?

        public init(netAmount: Double, taxCodeId: String?) {
            self.netAmount = netAmount
            self.taxCodeId = taxCodeId
        }
    }

    /// One computed tax row, grouped by tax code. Becomes a `TaxCharge`
    /// child row on the invoice and a `TaxTrans` ledger row on submit.
    public struct ComputedTaxRow: Equatable, Sendable {
        public let taxCode: String
        public let description: String
        public let rate: Double
        public let account: String?
        public let taxType: String
        public let taxableAmount: Double
        public let taxAmount: Double
    }

    /// The full result of a tax calculation for one document.
    public struct TaxComputation: Equatable, Sendable {
        public let netTotal: Double
        public let taxRows: [ComputedTaxRow]
        public let totalTax: Double
        public let grandTotal: Double

        public static let empty = TaxComputation(
            netTotal: 0, taxRows: [], totalTax: 0, grandTotal: 0
        )
    }

    /// Compute the net total, per-code tax rows, total tax, and grand total.
    ///
    /// - Lines whose effective code is `nil` (or unknown in `rates`) still
    ///   contribute to the net total but produce no tax row.
    /// - Zero / Exempt codes (rate `0`) DO produce a tax row with a `0`
    ///   tax amount so their taxable base is still captured for the VAT
    ///   return. This is deliberate: VAT reporting needs zero-rated and
    ///   exempt turnover, not just standard-rated sales.
    /// - Tax rows are ordered by first appearance of the code across the
    ///   lines, so the output is deterministic and stable across re-saves.
    public static func compute(
        lines: [TaxLine],
        rates: [String: TaxRateInfo]
    ) -> TaxComputation {
        var netTotal = 0.0
        // Preserve first-seen order of codes for deterministic output.
        var orderedCodes: [String] = []
        var taxableByCode: [String: Double] = [:]

        for line in lines {
            netTotal += line.netAmount
            guard let codeId = line.taxCodeId,
                  rates[codeId] != nil else { continue }
            if taxableByCode[codeId] == nil {
                orderedCodes.append(codeId)
            }
            taxableByCode[codeId, default: 0] += line.netAmount
        }

        var rows: [ComputedTaxRow] = []
        var totalTax = 0.0
        for codeId in orderedCodes {
            guard let info = rates[codeId] else { continue }
            let taxable = round2(taxableByCode[codeId] ?? 0)
            let taxAmount = round2(taxable * info.rate / 100.0)
            totalTax += taxAmount
            rows.append(ComputedTaxRow(
                taxCode: info.codeId,
                description: info.description,
                rate: info.rate,
                account: info.account,
                taxType: info.taxType,
                taxableAmount: taxable,
                taxAmount: taxAmount
            ))
        }

        let net = round2(netTotal)
        let tax = round2(totalTax)
        return TaxComputation(
            netTotal: net,
            taxRows: rows,
            totalTax: tax,
            grandTotal: round2(net + tax)
        )
    }

    /// Round to 2 decimal places (currency precision). Tax math is rounded
    /// per tax row, mirroring how invoices present each VAT line.
    static func round2(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}
