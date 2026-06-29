import Foundation
import MercantisCore

/// Pure fulfilment maths, split out so it can be unit-tested without a
/// `DocumentEngine`. `nonisolated` (pure value-level work) so the
/// `nonisolated` service can call it off the main actor under the module's
/// main-actor-by-default isolation.
nonisolated enum SalesOrderFulfilmentCalculator {

    /// Tolerance for the floating-point qty comparisons (a line is "fully"
    /// fulfilled when within this of its ordered qty).
    static let epsilon = 0.0000001

    /// Sum line qty per item across the given fulfilment documents (Sales
    /// Deliveries or Sales Invoices), counting only submitted (docStatus == 1)
    /// ones. Cancelled / draft documents don't count toward fulfilment.
    static func fulfilledByItem(_ docs: [Document]) -> [String: Double] {
        var byItem: [String: Double] = [:]
        for doc in docs where doc.docStatus == 1 {
            for row in doc.children["items"] ?? [] {
                guard let item = string(row.fields["item"]) else { continue }
                byItem[item, default: 0] += double(row.fields["qty"]) ?? 0
            }
        }
        return byItem
    }

    /// Total ordered qty across an order's lines.
    static func orderedQty(_ order: Document) -> Double {
        (order.children["items"] ?? []).reduce(0) { $0 + (double($1.fields["qty"]) ?? 0) }
    }

    static func total(_ byItem: [String: Double]) -> Double {
        byItem.values.reduce(0, +)
    }

    static func deliveryStatus(orderedQty: Double, deliveredQty: Double) -> String {
        progress(ordered: orderedQty, fulfilled: deliveredQty,
                 none: "To Deliver", partial: "Partially Delivered", full: "Fully Delivered")
    }

    /// Purchase-side receipt progress (shared maths, buy-side labels).
    static func receiptStatus(orderedQty: Double, receivedQty: Double) -> String {
        progress(ordered: orderedQty, fulfilled: receivedQty,
                 none: "To Receive", partial: "Partially Received", full: "Fully Received")
    }

    /// Billing progress — same labels for the sales and purchase order sides.
    static func billingStatus(orderedQty: Double, billedQty: Double) -> String {
        progress(ordered: orderedQty, fulfilled: billedQty,
                 none: "To Bill", partial: "Partially Billed", full: "Fully Billed")
    }

    /// Percentage fulfilled, capped at 100 for display (over-fulfilment shows as
    /// fully complete rather than > 100%).
    static func percent(orderedQty: Double, fulfilledQty: Double) -> Double {
        guard orderedQty > epsilon else { return 0 }
        return Swift.min(100, (fulfilledQty / orderedQty) * 100)
    }

    private static func progress(ordered: Double, fulfilled: Double, none: String, partial: String, full: String) -> String {
        if fulfilled <= epsilon { return none }
        if ordered > epsilon && fulfilled + epsilon >= ordered { return full }
        return partial
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
}

/// Keeps a Sales Order's delivery / billing progress in step with the Deliveries
/// and Invoices submitted against it. Wired like the other derivation services:
/// subscribes to `DocumentSubmittedEvent` / `DocumentCancelledEvent`, reacts to
/// `SalesDelivery` / `SalesInvoice`, and recomputes the linked order's
/// `delivery_status` / `billing_status` (and the matching qty / percent fields)
/// from ALL submitted fulfilment documents — so a cancel rolls the status back
/// just as cleanly as a submit advances it.
///
/// The order's fulfilment fields are `allowOnSubmit`, so the write lands on the
/// already-submitted order. The service writes only to `SalesOrder` (never to
/// the Delivery / Invoice that triggered it) and via `engine.save`, which fires
/// `DocumentSavedEvent` rather than a submit/cancel event, so there is no
/// re-entrancy.
public nonisolated final class SalesOrderFulfilmentService: @unchecked Sendable {

    private let engine: DocumentEngine
    private let emitter: EventEmitter
    private var tokens: [SubscriptionToken] = []

    public init(engine: DocumentEngine, emitter: EventEmitter) {
        self.engine = engine
        self.emitter = emitter
        wire()
    }

    deinit { for token in tokens { token.cancel() } }

    private func wire() {
        tokens.append(emitter.subscribe(DocumentSubmittedEvent.self) { [weak self] event in
            self?.handle(document: event.document)
        })
        tokens.append(emitter.subscribe(DocumentCancelledEvent.self) { [weak self] event in
            self?.handle(document: event.document)
        })
    }

    private func handle(document: Document) {
        guard document.docType == "SalesDelivery" || document.docType == "SalesInvoice" else { return }
        guard let orderId = nonEmptyString(document.fields["sales_order"]) else { return }
        do {
            try recompute(orderId: orderId)
        } catch {
            print("SalesOrderFulfilment: failed to recompute \(orderId): \(error)")
        }
    }

    /// Recompute both the delivery and billing progress for one order from every
    /// submitted Delivery / Invoice that links to it, and persist the changed
    /// fields. No-ops when nothing changed.
    private func recompute(orderId: String) throws {
        guard var order = try engine.fetch(docType: "SalesOrder", id: orderId) else { return }

        let deliveries = (try? engine.list(
            docType: "SalesDelivery",
            filters: ["sales_order": .string(orderId)],
            applyRowAccess: false
        )) ?? []
        let invoices = (try? engine.list(
            docType: "SalesInvoice",
            filters: ["sales_order": .string(orderId)],
            applyRowAccess: false
        )) ?? []

        let ordered = SalesOrderFulfilmentCalculator.orderedQty(order)
        let delivered = SalesOrderFulfilmentCalculator.total(
            SalesOrderFulfilmentCalculator.fulfilledByItem(deliveries))
        let billed = SalesOrderFulfilmentCalculator.total(
            SalesOrderFulfilmentCalculator.fulfilledByItem(invoices))

        var changed = false
        changed = setField(&order, "delivered_qty", .double(round2(delivered))) || changed
        changed = setField(&order, "per_delivered",
                           .double(round2(SalesOrderFulfilmentCalculator.percent(orderedQty: ordered, fulfilledQty: delivered)))) || changed
        changed = setField(&order, "delivery_status",
                           .string(SalesOrderFulfilmentCalculator.deliveryStatus(orderedQty: ordered, deliveredQty: delivered))) || changed
        changed = setField(&order, "billed_qty", .double(round2(billed))) || changed
        changed = setField(&order, "per_billed",
                           .double(round2(SalesOrderFulfilmentCalculator.percent(orderedQty: ordered, fulfilledQty: billed)))) || changed
        changed = setField(&order, "billing_status",
                           .string(SalesOrderFulfilmentCalculator.billingStatus(orderedQty: ordered, billedQty: billed))) || changed

        if changed { try engine.save(order) }
    }

    /// Set a field when its value actually differs; returns whether it changed.
    private func setField(_ doc: inout Document, _ key: String, _ value: FieldValue) -> Bool {
        if doc.fields[key] == value { return false }
        doc.fields[key] = value
        return true
    }

    private func round2(_ value: Double) -> Double { (value * 100).rounded() / 100 }

    private func nonEmptyString(_ value: FieldValue?) -> String? {
        guard case .string(let s) = value else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
