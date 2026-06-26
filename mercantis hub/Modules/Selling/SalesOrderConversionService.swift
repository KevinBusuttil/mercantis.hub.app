import Foundation
import MercantisCore

/// Keeps sales-document conversions consistent with their source's lifecycle.
///
/// When a Quotation or Sales Order is cancelled, its still-DRAFT converted
/// documents (a Quotation's Sales Orders; a Sales Order's Deliveries /
/// Invoices, created via "Convert to …") are discarded — they reference a
/// now-void source and were never posted. Submitted downstream documents
/// already block the source's cancellation in Core (`findLinkedSubmittedDocuments`
/// via the back-link), so by the time this runs only drafts remain.
///
/// Wired like the other derivation services: subscribes to
/// `DocumentCancelledEvent` and reacts to `Quotation` / `SalesOrder`, writing
/// under a system context.
public nonisolated final class SalesOrderConversionService: @unchecked Sendable {

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
        // Each source links to its drafts via a back-link field on the target:
        // a Quotation's draft Sales Orders (via `quotation`), and a Sales
        // Order's draft Deliveries / Invoices (via `sales_order`).
        let cascade: [(target: String, linkField: String)]
        switch document.docType {
        case "Quotation":
            cascade = [("SalesOrder", "quotation")]
        case "SalesOrder":
            cascade = [("SalesDelivery", "sales_order"), ("SalesInvoice", "sales_order")]
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
                    print("SalesOrderConversion: failed to discard draft \(targetType) \(draft.id): \(error)")
                }
            }
        }
    }
}
