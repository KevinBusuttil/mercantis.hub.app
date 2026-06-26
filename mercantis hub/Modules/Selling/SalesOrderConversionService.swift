import Foundation
import MercantisCore

/// Keeps Sales Order conversions consistent with the order's lifecycle.
///
/// When a Sales Order is cancelled, its still-DRAFT converted documents (Sales
/// Deliveries / Invoices created from it via "Convert to …") are discarded —
/// they reference a now-void order and were never posted. Submitted deliveries
/// / invoices already block the order's cancellation in Core
/// (`findLinkedSubmittedDocuments` via the `sales_order` link), so by the time
/// this runs only drafts remain.
///
/// Wired like the other derivation services: subscribes to
/// `DocumentCancelledEvent` and reacts only to `SalesOrder`, writing under a
/// system context.
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
        guard document.docType == "SalesOrder" else { return }
        for targetType in ["SalesDelivery", "SalesInvoice"] {
            let linked = (try? engine.list(
                docType: targetType,
                filters: ["sales_order": .string(document.id)],
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
