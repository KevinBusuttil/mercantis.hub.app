import Foundation
import MercantisCore

/// Phase 2 — applies `HubTaxEngine` to a transactional document.
///
/// This policy is the bridge between persisted master data and the pure
/// engine. It resolves each line's effective tax code through the
/// fallback chain
///
///   line.tax_code → item master tax_code → document tax_code → party tax_code
///
/// computes the tax via `HubTaxEngine`, then writes `net_total`,
/// `total_taxes`, `grand_total`, `total_qty`, and the `taxes` child rows
/// back onto the document.
///
/// `applied(to:docType:engine:)` is the production entry point used in the
/// save / submit paths. `computeAndApply(...)` is the pure core (no
/// `DocumentEngine`) so the calculation is unit-testable with in-memory
/// documents and closure lookups.
enum HubTaxCalculationPolicy {

    /// DocTypes that carry a `taxes` table and tax-aware totals.
    static let supportedDocTypes: Set<String> = ["SalesInvoice", "PurchaseInvoice", "POSInvoice"]

    /// The line-item child table key for a supported DocType.
    private static let lineTableKey = "items"

    // MARK: - Production entry point

    /// Recompute taxes/totals for the document using master data loaded
    /// from `engine`. No-ops (returns the document unchanged) for DocTypes
    /// without a tax table, or when there are no line items to tax.
    static func applied(
        to document: Document,
        docType: DocType,
        engine: DocumentEngine
    ) -> Document {
        guard supportedDocTypes.contains(docType.id) else { return document }
        guard let rows = document.children[lineTableKey], !rows.isEmpty else { return document }

        // Default VAT account fallback from the single Business Profile.
        let businessProfile = (try? engine.list(docType: "Company"))?.first
        let defaultTaxAccount = nonEmptyString(businessProfile?.fields["default_vat_account"])

        // Tax code master → rate info, applying the default account fallback.
        let codeRecords = (try? engine.list(docType: "TaxCode")) ?? []
        var rateByCode: [String: HubTaxEngine.TaxRateInfo] = [:]
        for record in codeRecords {
            guard boolValue(record.fields["enabled"], default: true) else { continue }
            rateByCode[record.id] = rateInfo(from: record, defaultTaxAccount: defaultTaxAccount)
        }

        // Item master tax-code lookup, cached across lines.
        var itemCache: [String: Document?] = [:]
        let itemTaxCode: (String) -> String? = { itemId in
            if let cached = itemCache[itemId] {
                return cached.flatMap { nonEmptyString($0.fields["tax_code"]) }
            }
            let item = try? engine.fetch(docType: "Item", id: itemId)
            itemCache[itemId] = item
            return item.flatMap { nonEmptyString($0.fields["tax_code"]) }
        }

        let partyCode = partyTaxCode(document: document, docTypeId: docType.id, engine: engine)

        return computeAndApply(
            document: document,
            rateByCode: rateByCode,
            documentTaxCode: nonEmptyString(document.fields["tax_code"]),
            partyTaxCode: partyCode,
            itemTaxCode: itemTaxCode
        )
    }

    // MARK: - Pure core (testable without a DocumentEngine)

    /// Compute taxes/totals and return a new document with `net_total`,
    /// `total_taxes`, `grand_total`, `total_qty`, and `taxes` rows written.
    ///
    /// `itemTaxCode` maps an item id to that item's default tax code (or
    /// `nil`). `rateByCode` maps a tax code id to its rate info.
    static func computeAndApply(
        document: Document,
        rateByCode: [String: HubTaxEngine.TaxRateInfo],
        documentTaxCode: String?,
        partyTaxCode: String?,
        itemTaxCode: (String) -> String?
    ) -> Document {
        let rows = document.children[lineTableKey] ?? []
        guard !rows.isEmpty else { return document }

        var totalQty = 0.0
        var lines: [HubTaxEngine.TaxLine] = []
        lines.reserveCapacity(rows.count)

        for row in rows {
            let qty  = doubleValue(row.fields["qty"]) ?? 0
            let rate = doubleValue(row.fields["rate"]) ?? 0
            totalQty += qty
            let net = qty * rate

            // line → item → document → party fallback chain.
            let lineCode = nonEmptyString(row.fields["tax_code"])
            let itemCode = lineCode == nil
                ? nonEmptyString(row.fields["item"]).flatMap(itemTaxCode)
                : nil
            let effective = lineCode ?? itemCode ?? documentTaxCode ?? partyTaxCode

            lines.append(HubTaxEngine.TaxLine(netAmount: net, taxCodeId: effective))
        }

        let computation = HubTaxEngine.compute(lines: lines, rates: rateByCode)

        var result = document
        result.fields["total_qty"]    = .double(HubTaxEngine.round2(totalQty))
        result.fields["net_total"]    = .double(computation.netTotal)
        result.fields["total_taxes"]  = .double(computation.totalTax)
        result.fields["grand_total"]  = .double(computation.grandTotal)
        result.children["taxes"]      = taxChildRows(from: computation.taxRows)
        return result
    }

    // MARK: - Helpers

    private static func taxChildRows(
        from rows: [HubTaxEngine.ComputedTaxRow]
    ) -> [ChildRow] {
        rows.enumerated().map { index, row in
            var fields: [String: FieldValue] = [
                "tax_code":       .string(row.taxCode),
                "tax_type":       .string(row.taxType),
                "description":    .string(row.description),
                "rate":           .double(row.rate),
                "taxable_amount": .double(row.taxableAmount),
                "tax_amount":     .double(row.taxAmount),
            ]
            if let account = row.account, !account.isEmpty {
                fields["tax_account"] = .string(account)
            }
            return ChildRow(id: "tax-row-\(index)", rowIndex: index, fields: fields)
        }
    }

    private static func rateInfo(
        from record: Document,
        defaultTaxAccount: String?
    ) -> HubTaxEngine.TaxRateInfo {
        let name = nonEmptyString(record.fields["tax_code_name"]) ?? record.id
        let rate = doubleValue(record.fields["rate"]) ?? 0
        let account = nonEmptyString(record.fields["tax_account"]) ?? defaultTaxAccount
        let taxType = nonEmptyString(record.fields["tax_type"]) ?? "VAT"
        let pct = String(format: rate == rate.rounded() ? "%.0f%%" : "%.2f%%", rate)
        return HubTaxEngine.TaxRateInfo(
            codeId: record.id,
            description: "\(name) (\(pct))",
            rate: rate,
            account: account,
            taxType: taxType
        )
    }

    /// Resolve the party's default tax code (Customer for sales, Supplier
    /// for purchases) as the lowest-priority fallback.
    private static func partyTaxCode(
        document: Document,
        docTypeId: String,
        engine: DocumentEngine
    ) -> String? {
        switch docTypeId {
        case "SalesInvoice", "POSInvoice":
            guard let id = nonEmptyString(document.fields["customer"]),
                  let customer = try? engine.fetch(docType: "Customer", id: id) else { return nil }
            return nonEmptyString(customer.fields["tax_code"])
        case "PurchaseInvoice":
            guard let id = nonEmptyString(document.fields["supplier"]),
                  let supplier = try? engine.fetch(docType: "Supplier", id: id) else { return nil }
            return nonEmptyString(supplier.fields["tax_code"])
        default:
            return nil
        }
    }

    // MARK: - Value coercion

    private static func nonEmptyString(_ value: FieldValue?) -> String? {
        guard case .string(let s)? = value else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func doubleValue(_ value: FieldValue?) -> Double? {
        switch value {
        case .double(let d): return d
        case .int(let i):    return Double(i)
        case .string(let s): return Double(s)
        default:             return nil
        }
    }

    private static func boolValue(_ value: FieldValue?, default fallback: Bool) -> Bool {
        guard case .bool(let b)? = value else { return fallback }
        return b
    }
}
