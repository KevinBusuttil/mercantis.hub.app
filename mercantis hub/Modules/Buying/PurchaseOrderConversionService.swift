import Foundation
import MercantisCore

/// Buy-side mirror of `SalesOrderConversionService`: discards still-DRAFT
/// converted documents when their source is cancelled.
///
/// When a Purchase Order is cancelled, its draft Receipts / Invoices (created
/// via "Convert to …", linked back via `purchase_order`) are discarded — they
/// reference a now-void source and were never posted. A cancelled Purchase
/// Receipt likewise discards any draft Invoice built from it (via
/// `purchase_receipt`). Submitted downstream documents already block the
/// source's cancellation in Core, so by the time this runs only drafts remain.
public nonisolated final class PurchaseOrderConversionService: @unchecked Sendable {

    private let engine: DocumentEngine
    private let emitter: EventEmitter
    private let systemContext = ExecutionContext.system(operatorId: "system", deviceId: "system")
    private var tokens: [SubscriptionToken] = []

    public init(engine: DocumentEngine, emitter: EventEmitter) {
        self.engine = engine
        self.emitter = emitter
        wire()
    }

    deinit { for token in tokens { token.cancel() } }

    private func wire() {
        let token = emitter.subscribe(DocumentCancelledEvent.self) { [weak self] event in
            self?.handleCancel(document: event.document)
        }
        tokens.append(token)
    }

    private func handleCancel(document: Document) {
        let cascade: [(target: String, linkField: String)]
        switch document.docType {
        case "PurchaseOrder":
            cascade = [("PurchaseReceipt", "purchase_order"), ("PurchaseInvoice", "purchase_order")]
        case "PurchaseReceipt":
            cascade = [("PurchaseInvoice", "purchase_receipt")]
        default:
            return
        }

        for (targetType, linkField) in cascade {
            let linked = (try? engine.list(
                docType: targetType,
                filters: [linkField: .string(document.id)],
                applyRowAccess: false
            )) ?? []
            for draft in linked where draft.docStatus == 0 {
                do {
                    try engine.delete(docType: targetType, id: draft.id, context: systemContext)
                } catch {
                    print("PurchaseOrderConversion: failed to discard draft \(targetType) \(draft.id): \(error)")
                }
            }
        }
    }
}
