import Foundation
import MercantisCore

/// Builds a draft of a downstream document from a confirmed Sales Order, so an
/// operator can convert an order into a Delivery or an Invoice in one click
/// rather than re-keying the lines. The result is an ordinary Draft (docStatus
/// 0) — the caller applies the Business Profile defaults and saves it, and the
/// normal tax / submit flow takes over from there.
enum HubDocumentConversion {

    /// Sales Order → Sales Delivery draft. Header (customer / date / currency /
    /// default warehouse) and item lines (item / qty / uom / rate / warehouse)
    /// are carried over; each line links back to the originating order.
    static func salesOrderToDelivery(_ order: Document) -> Document {
        var fields: [String: FieldValue] = [
            "transaction_date": .date(Date()),
            "sales_order": .string(order.id),
        ]
        copy(["customer", "currency", "conversion_rate"], from: order.fields, into: &fields)
        if let warehouse = order.fields["set_warehouse"] ?? order.fields["warehouse"] {
            fields["set_warehouse"] = warehouse
        }
        let items = (order.children["items"] ?? []).enumerated().map { index, row -> ChildRow in
            var lineFields: [String: FieldValue] = ["sales_order": .string(order.id)]
            copy(["item", "description", "qty", "uom", "rate", "warehouse"], from: row.fields, into: &lineFields)
            return ChildRow(id: UUID().uuidString, rowIndex: index, fields: lineFields)
        }
        return draft(docType: "SalesDelivery", company: order.company, fields: fields, items: items)
    }

    /// Sales Order → Sales Invoice draft. Header and item lines (the Sales
    /// Invoice shares the SalesItem child shape) are carried over. The posting
    /// accounts and totals are filled by the Business Profile defaults / tax
    /// policy when the caller saves and submits it.
    static func salesOrderToInvoice(_ order: Document) -> Document {
        var fields: [String: FieldValue] = [
            "transaction_date": .date(Date()),
        ]
        copy(["customer", "currency", "conversion_rate", "price_list", "tax_code"], from: order.fields, into: &fields)
        let items = (order.children["items"] ?? []).enumerated().map { index, row -> ChildRow in
            var lineFields: [String: FieldValue] = [:]
            copy(["item", "description", "qty", "uom", "rate", "tax_code", "warehouse"], from: row.fields, into: &lineFields)
            return ChildRow(id: UUID().uuidString, rowIndex: index, fields: lineFields)
        }
        return draft(docType: "SalesInvoice", company: order.company, fields: fields, items: items)
    }

    // MARK: - Helpers

    private static func copy(_ keys: [String], from source: [String: FieldValue], into target: inout [String: FieldValue]) {
        for key in keys where target[key] == nil {
            if let value = source[key] { target[key] = value }
        }
    }

    private static func draft(docType: String, company: String, fields: [String: FieldValue], items: [ChildRow]) -> Document {
        Document(
            id: "", docType: docType, company: company, status: "",
            createdAt: Date(), updatedAt: Date(), syncVersion: 0, syncState: .local,
            docStatus: 0, fields: fields, children: ["items": items]
        )
    }
}
