import Foundation
import MercantisCore

/// Keeps a Purchase Order's receipt / billing progress in step with the
/// Receipts and Invoices submitted against it — the buy-side mirror of
/// `SalesOrderFulfilmentService`. Subscribes to `DocumentSubmittedEvent` /
/// `DocumentCancelledEvent`, reacts to `PurchaseReceipt` / `PurchaseInvoice`,
/// and recomputes the linked order's `receipt_status` / `billing_status` (and
/// the matching qty / percent fields) from ALL submitted fulfilment documents,
/// so a cancel rolls the status back just as cleanly as a submit advances it.
///
/// The order's fulfilment fields are `allowOnSubmit`, so the write lands on the
/// already-submitted order. The service writes only to `PurchaseOrder` and via
/// `engine.save` (which fires `DocumentSavedEvent`, not a submit/cancel event),
/// so there is no re-entrancy. Reuses `SalesOrderFulfilmentCalculator` for the
/// shared fulfilment arithmetic.
public nonisolated final class PurchaseOrderFulfilmentService: @unchecked Sendable {

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
        guard document.docType == "PurchaseReceipt" || document.docType == "PurchaseInvoice" else { return }
        guard let orderId = nonEmptyString(document.fields["purchase_order"]) else { return }
        do {
            try recompute(orderId: orderId)
        } catch {
            print("PurchaseOrderFulfilment: failed to recompute \(orderId): \(error)")
        }
    }

    /// Recompute both the receipt and billing progress for one order from every
    /// submitted Receipt / Invoice that links to it, and persist the changed
    /// fields. No-ops when nothing changed.
    private func recompute(orderId: String) throws {
        guard var order = try engine.fetch(docType: "PurchaseOrder", id: orderId) else { return }

        let receipts = (try? engine.list(
            docType: "PurchaseReceipt",
            filters: ["purchase_order": .string(orderId)],
            applyRowAccess: false
        )) ?? []
        let invoices = (try? engine.list(
            docType: "PurchaseInvoice",
            filters: ["purchase_order": .string(orderId)],
            applyRowAccess: false
        )) ?? []

        let ordered = SalesOrderFulfilmentCalculator.orderedQty(order)
        let received = SalesOrderFulfilmentCalculator.total(
            SalesOrderFulfilmentCalculator.fulfilledByItem(receipts))
        let billed = SalesOrderFulfilmentCalculator.total(
            SalesOrderFulfilmentCalculator.fulfilledByItem(invoices))

        var changed = false
        changed = setField(&order, "received_qty", .double(round2(received))) || changed
        changed = setField(&order, "per_received",
                           .double(round2(SalesOrderFulfilmentCalculator.percent(orderedQty: ordered, fulfilledQty: received)))) || changed
        changed = setField(&order, "receipt_status",
                           .string(SalesOrderFulfilmentCalculator.receiptStatus(orderedQty: ordered, receivedQty: received))) || changed
        changed = setField(&order, "billed_qty", .double(round2(billed))) || changed
        changed = setField(&order, "per_billed",
                           .double(round2(SalesOrderFulfilmentCalculator.percent(orderedQty: ordered, fulfilledQty: billed)))) || changed
        changed = setField(&order, "billing_status",
                           .string(SalesOrderFulfilmentCalculator.billingStatus(orderedQty: ordered, billedQty: billed))) || changed

        if changed { try engine.save(order) }
    }

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
