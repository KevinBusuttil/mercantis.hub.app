import Foundation
import MercantisCore

/// Builds a draft of a downstream document from a confirmed Sales Order (or a
/// submitted Sales Delivery), so an operator can convert an order into a
/// Delivery or an Invoice — or invoice a delivery — in one click rather than
/// re-keying the lines. The result is an ordinary Draft (docStatus 0) — the
/// caller applies the Business Profile defaults and saves it, and the normal
/// tax / submit flow takes over from there.
///
/// Order → Delivery / Invoice conversions default each line to the **remaining**
/// (un-fulfilled) quantity, given the qty already delivered / billed against the
/// order (passed in by the caller, which has the engine to total it). A line
/// with nothing left is dropped, so re-converting a partially-fulfilled order
/// proposes only the balance.
enum HubDocumentConversion {

    /// Quotation → Sales Order draft. Header (customer / date / currency /
    /// price list / tax code / default warehouse) and the full item lines are
    /// carried over; the order links back to the originating quotation. Totals
    /// and posting defaults are filled by the tax policy / Business Profile when
    /// the caller saves it.
    static func quotationToSalesOrder(_ quote: Document) -> Document {
        var fields: [String: FieldValue] = [
            "transaction_date": .date(Date()),
            "quotation": .string(quote.id),
        ]
        copy(["customer", "currency", "conversion_rate", "price_list", "tax_code",
              "set_warehouse", "delivery_date"], from: quote.fields, into: &fields)
        let items = (quote.children["items"] ?? []).enumerated().map { index, row -> ChildRow in
            var lineFields: [String: FieldValue] = [:]
            copy(["item", "description", "qty", "uom", "rate", "tax_code", "warehouse", "delivery_date"],
                 from: row.fields, into: &lineFields)
            return ChildRow(id: UUID().uuidString, rowIndex: index, fields: lineFields)
        }
        return draft(docType: "SalesOrder", company: quote.company, fields: fields, items: items)
    }

    /// Sales Order → Sales Delivery draft. Header (customer / date / currency /
    /// default warehouse) and item lines (item / qty / uom / rate / warehouse)
    /// are carried over; each line links back to the originating order. Each
    /// line defaults to the qty still to deliver (ordered − already delivered),
    /// and fully-delivered lines are dropped.
    static func salesOrderToDelivery(_ order: Document, deliveredByItem: [String: Double] = [:]) -> Document {
        var fields: [String: FieldValue] = [
            "transaction_date": .date(Date()),
            "sales_order": .string(order.id),
        ]
        copy(["customer", "currency", "conversion_rate"], from: order.fields, into: &fields)
        if let warehouse = order.fields["set_warehouse"] ?? order.fields["warehouse"] {
            fields["set_warehouse"] = warehouse
        }
        let items = remainingLines(
            order.children["items"] ?? [],
            fulfilledByItem: deliveredByItem,
            carryKeys: ["item", "description", "uom", "rate", "warehouse"],
            backLink: (key: "sales_order", value: order.id)
        )
        return draft(docType: "SalesDelivery", company: order.company, fields: fields, items: items)
    }

    /// Sales Order → Sales Invoice draft. Header and item lines (the Sales
    /// Invoice shares the SalesItem child shape) are carried over. Each line
    /// defaults to the qty still to bill (ordered − already billed), and
    /// fully-billed lines are dropped. The posting accounts and totals are
    /// filled by the Business Profile defaults / tax policy when the caller
    /// saves and submits it.
    static func salesOrderToInvoice(_ order: Document, billedByItem: [String: Double] = [:]) -> Document {
        var fields: [String: FieldValue] = [
            "transaction_date": .date(Date()),
            "sales_order": .string(order.id),
        ]
        copy(["customer", "currency", "conversion_rate", "price_list", "tax_code"], from: order.fields, into: &fields)
        let items = remainingLines(
            order.children["items"] ?? [],
            fulfilledByItem: billedByItem,
            carryKeys: ["item", "description", "uom", "rate", "tax_code", "warehouse"],
            backLink: (key: "sales_order", value: order.id)
        )
        return draft(docType: "SalesInvoice", company: order.company, fields: fields, items: items)
    }

    /// Sales Delivery → Sales Invoice draft (deliver-then-invoice). Bills the
    /// goods that physically shipped: the delivery's lines (item / qty / uom /
    /// rate / warehouse) are carried over verbatim, the invoice links back to
    /// the delivery, and the order link is threaded through when the delivery
    /// itself came from an order. Posting accounts / totals are filled by the
    /// Business Profile defaults when the caller saves it.
    static func deliveryToInvoice(_ delivery: Document) -> Document {
        var fields: [String: FieldValue] = [
            "transaction_date": .date(Date()),
            "sales_delivery": .string(delivery.id),
        ]
        copy(["customer", "currency", "conversion_rate"], from: delivery.fields, into: &fields)
        // Thread the order link through when the delivery fulfils an order, so
        // billing progress still rolls up to the Sales Order.
        if let order = delivery.fields["sales_order"] { fields["sales_order"] = order }
        let items = (delivery.children["items"] ?? []).enumerated().map { index, row -> ChildRow in
            var lineFields: [String: FieldValue] = [:]
            copy(["item", "description", "qty", "uom", "rate", "warehouse"], from: row.fields, into: &lineFields)
            return ChildRow(id: UUID().uuidString, rowIndex: index, fields: lineFields)
        }
        return draft(docType: "SalesInvoice", company: delivery.company, fields: fields, items: items)
    }

    // MARK: - Helpers

    /// Carry source lines into a downstream table, defaulting each line's qty to
    /// the amount still un-fulfilled (ordered − already fulfilled for that
    /// item). `fulfilledByItem` is consumed greedily across lines of the same
    /// item, and a line with nothing left is dropped. Each surviving line gets
    /// the `backLink` field set to the source id.
    static func remainingLines(
        _ rows: [ChildRow],
        fulfilledByItem: [String: Double],
        carryKeys: [String],
        backLink: (key: String, value: String)
    ) -> [ChildRow] {
        var pool = fulfilledByItem
        var result: [ChildRow] = []
        for row in rows {
            let orderedQty = double(row.fields["qty"]) ?? 0
            var remaining = orderedQty
            if let itemId = string(row.fields["item"]), let already = pool[itemId], already > 0 {
                let netted = Swift.min(already, orderedQty)
                remaining = orderedQty - netted
                pool[itemId] = already - netted
            }
            guard remaining > 0.0000001 else { continue }
            var lineFields: [String: FieldValue] = [backLink.key: .string(backLink.value)]
            copy(carryKeys, from: row.fields, into: &lineFields)
            lineFields["qty"] = .double(remaining)
            result.append(ChildRow(id: UUID().uuidString, rowIndex: result.count, fields: lineFields))
        }
        return result
    }

    private static func copy(_ keys: [String], from source: [String: FieldValue], into target: inout [String: FieldValue]) {
        for key in keys where target[key] == nil {
            if let value = source[key] { target[key] = value }
        }
    }

    private static func string(_ value: FieldValue?) -> String? {
        guard case .string(let s)? = value else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func double(_ value: FieldValue?) -> Double? {
        switch value {
        case .double(let d): return d
        case .int(let i):    return Double(i)
        default:             return nil
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
