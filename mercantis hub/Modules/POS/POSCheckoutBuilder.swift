import Foundation
import MercantisCore

/// Phase 6 — pure construction logic for a POS sale. Free of
/// `DocumentEngine` / SwiftUI so pricing, tender, change, and the POS
/// Invoice shape are unit-testable; the checkout view supplies loaded
/// master records.
enum POSCheckoutBuilder {

    /// One line in the POS cart.
    struct CartLine: Equatable {
        let itemId: String
        let qty: Double
        let rate: Double
        let taxCode: String?
        let warehouse: String?
    }

    /// One payment tender taken at the till.
    struct Tender: Equatable {
        let type: String      // Cash / Card / Other
        let amount: Double
        let reference: String?
    }

    // MARK: - Pricing

    /// Resolve the unit price for an item: prefer a matching row in the
    /// profile's price list, otherwise the item's standard rate. Pure — the
    /// caller passes the loaded `PriceList` document (with its `items`
    /// child rows) and the item's standard rate.
    static func price(forItem itemId: String, in priceList: Document?, standardRate: Double) -> Double {
        if let rows = priceList?.children["items"] {
            for row in rows where stringValue(row.fields["item"]) == itemId {
                if let rate = doubleValue(row.fields["rate"]) { return rate }
            }
        }
        return standardRate
    }

    // MARK: - Tender / change

    static func tendered(_ tenders: [Tender]) -> Double {
        round2(tenders.reduce(0) { $0 + $1.amount })
    }

    static func isFullyPaid(tenders: [Tender], grandTotal: Double) -> Bool {
        tendered(tenders) >= round2(grandTotal)
    }

    /// Change owed to the customer (never negative).
    static func change(tenders: [Tender], grandTotal: Double) -> Double {
        max(0, round2(tendered(tenders) - grandTotal))
    }

    // MARK: - Build

    /// Build the draft POS Invoice. Totals (`net_total`, `taxes`,
    /// `total_taxes`, `grand_total`, `total_qty`) are left for
    /// `HubTaxCalculationPolicy` to stamp on save, exactly like Sales /
    /// Purchase invoices. Lines use the shared `SalesItem` shape.
    static func buildPOSInvoice(
        profileId: String?,
        sessionId: String?,
        customer: String?,
        postingDate: Date,
        currency: String?,
        warehouse: String?,
        cashAccount: String?,
        incomeAccount: String?,
        defaultTaxCode: String?,
        lines: [CartLine],
        tenders: [Tender]
    ) -> Document {
        var fields: [String: FieldValue] = [
            "transaction_date": .date(postingDate),
            "paid_amount":      .double(tendered(tenders)),
        ]
        setIfPresent(&fields, "pos_profile", profileId)
        setIfPresent(&fields, "pos_session", sessionId)
        setIfPresent(&fields, "customer", customer)
        setIfPresent(&fields, "currency", currency)
        setIfPresent(&fields, "warehouse", warehouse)
        setIfPresent(&fields, "cash_account", cashAccount)
        setIfPresent(&fields, "income_account", incomeAccount)
        setIfPresent(&fields, "tax_code", defaultTaxCode)

        let itemRows: [ChildRow] = lines.enumerated().map { index, line in
            var f: [String: FieldValue] = [
                "item": .string(line.itemId),
                "qty":  .double(line.qty),
                "rate": .double(line.rate),
            ]
            if let taxCode = line.taxCode, !taxCode.isEmpty { f["tax_code"] = .string(taxCode) }
            if let wh = line.warehouse, !wh.isEmpty { f["warehouse"] = .string(wh) }
            return ChildRow(id: "pos-item-\(index)", rowIndex: index, fields: f)
        }

        let tenderRows: [ChildRow] = tenders.enumerated().map { index, tender in
            var f: [String: FieldValue] = [
                "tender_type": .string(tender.type),
                "amount":      .double(tender.amount),
            ]
            if let ref = tender.reference, !ref.isEmpty { f["reference"] = .string(ref) }
            return ChildRow(id: "pos-tender-\(index)", rowIndex: index, fields: f)
        }

        return Document(
            id: "",
            docType: "POSInvoice",
            company: "",
            status: "Draft",
            createdAt: Date(),
            updatedAt: Date(),
            syncVersion: 0,
            syncState: .local,
            fields: fields,
            children: ["items": itemRows, "tenders": tenderRows]
        )
    }

    // MARK: - Helpers

    static func round2(_ value: Double) -> Double { (value * 100).rounded() / 100 }

    private static func setIfPresent(_ fields: inout [String: FieldValue], _ key: String, _ value: String?) {
        guard let value, !value.isEmpty else { return }
        fields[key] = .string(value)
    }

    private static func stringValue(_ value: FieldValue?) -> String? {
        if case .string(let s) = value { return s }
        return nil
    }

    private static func doubleValue(_ value: FieldValue?) -> Double? {
        switch value {
        case .double(let d): return d
        case .int(let i):    return Double(i)
        default:             return nil
        }
    }
}
