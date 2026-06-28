import Foundation
import MercantisCore

/// Phase 2 — the shared "save → post → mark submitted" sequence used by the
/// guided accounting flows (Opening Balances, Bank Reconciliation categorise),
/// factored out of `GuidedPaymentFlowView.saveSubmit` so every flow posts a
/// document the exact same way: persist the draft, run Core's atomic submit
/// (which fires GL / subledger derivation inside the transaction), then advance
/// the workflow to Submitted.
enum HubPostingFlow {

    @discardableResult
    static func saveSubmit(
        _ draft: Document,
        docType: String,
        engine: DocumentEngine,
        workflowEngine: WorkflowEngine,
        posting: PostingCoordinator?,
        evaluator: ExpressionEvaluator = ExpressionEvaluator()
    ) throws -> String {
        var doc = try engine.save(draft)
        if let refreshed = try engine.fetch(docType: docType, id: doc.id) { doc = refreshed }

        // Atomic posting inside the submit transaction (no half-posted state).
        if let posting, let closure = posting.submitClosure(for: doc) {
            try engine.submit(&doc, inTransaction: closure)
        } else {
            try engine.submit(&doc)
        }
        if let refreshed = try engine.fetch(docType: docType, id: doc.id) { doc = refreshed }

        // Advance the workflow status to Submitted, mirroring the document editor.
        if let workflow = HubWorkflows.workflow(forDocTypeId: docType),
           let transition = (try? workflowEngine.availableTransitions(
                workflow: workflow,
                currentState: "Draft",
                userRoles: ["System Manager"],
                document: doc,
                expressionEvaluator: evaluator
           ))?.first(where: { $0.action == "Submit" }) {
            _ = try workflowEngine.transition(
                document: &doc,
                workflow: workflow,
                action: transition.action,
                userRoles: ["System Manager"],
                expressionEvaluator: evaluator,
                userId: HubIdentity.userId()
            )
            _ = try engine.save(doc)
        }
        return doc.id
    }
}
