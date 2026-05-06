import Foundation
import MercantisCore

/// Hub workflow definitions wired into `AppManifest.workflows` and consumed
/// by Core's `WorkflowEngine` (ADR-004). One workflow per transactional
/// DocType. Every workflow includes the canonical `Draft → Submitted →
/// Cancelled` transitions that mirror Core's `docStatus` lifecycle (ADR-013);
/// most also model post-submit application states (Lost / Ordered / Paid).
///
/// Conventions:
/// - State names match the eventual `Document.status` strings.
/// - The "Submit" transition only flips `Document.status` to "Submitted";
///   the actual `docStatus` 0→1 transition runs through
///   `DocumentEngine.submit(_:)` separately. The Hub UI invokes both
///   when the user taps the Submit button.
/// - "Cancel" similarly mirrors `DocumentEngine.cancel(_:)` (docStatus 1→2).
/// - All transitions are gated to `System Manager` for now; tighter
///   role gating arrives with the role-import work in a later revision.
public enum HubWorkflows: Sendable {

    private static let systemManagerRole = "System Manager"

    // MARK: - Selling

    public static let quotation = WorkflowDefinition(
        id: "wf-quotation",
        name: "Quotation",
        docType: "Quotation",
        states: [
            WorkflowState(name: "Draft",     isDefault: true,  allowEdit: true),
            WorkflowState(name: "Submitted", isDefault: false, allowEdit: false),
            WorkflowState(name: "Ordered",   isDefault: false, allowEdit: false),
            WorkflowState(name: "Lost",      isDefault: false, allowEdit: false),
            WorkflowState(name: "Cancelled", isDefault: false, allowEdit: false),
        ],
        transitions: [
            WorkflowTransition(from: "Draft",     to: "Submitted", action: "Submit",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Submitted", to: "Ordered",   action: "Mark as Ordered",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Submitted", to: "Lost",      action: "Mark as Lost",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Submitted", to: "Cancelled", action: "Cancel",
                               allowedRoles: [systemManagerRole]),
        ]
    )

    public static let salesOrder = WorkflowDefinition(
        id: "wf-sales-order",
        name: "Sales Order",
        docType: "SalesOrder",
        states: [
            WorkflowState(name: "Draft",     isDefault: true,  allowEdit: true),
            WorkflowState(name: "Submitted", isDefault: false, allowEdit: false),
            WorkflowState(name: "Closed",    isDefault: false, allowEdit: false),
            WorkflowState(name: "Cancelled", isDefault: false, allowEdit: false),
        ],
        transitions: [
            WorkflowTransition(from: "Draft",     to: "Submitted", action: "Submit",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Submitted", to: "Closed",    action: "Close",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Submitted", to: "Cancelled", action: "Cancel",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Closed",    to: "Submitted", action: "Re-open",
                               allowedRoles: [systemManagerRole]),
        ]
    )

    public static let salesInvoice = WorkflowDefinition(
        id: "wf-sales-invoice",
        name: "Sales Invoice",
        docType: "SalesInvoice",
        states: [
            WorkflowState(name: "Draft",     isDefault: true,  allowEdit: true),
            WorkflowState(name: "Submitted", isDefault: false, allowEdit: false),
            WorkflowState(name: "Paid",      isDefault: false, allowEdit: false),
            WorkflowState(name: "Overdue",   isDefault: false, allowEdit: false),
            WorkflowState(name: "Cancelled", isDefault: false, allowEdit: false),
        ],
        transitions: [
            WorkflowTransition(from: "Draft",     to: "Submitted", action: "Submit",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Submitted", to: "Paid",      action: "Mark as Paid",
                               allowedRoles: [systemManagerRole],
                               conditionExpression: "outstanding_amount <= 0"),
            WorkflowTransition(from: "Submitted", to: "Overdue",   action: "Mark as Overdue",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Overdue",   to: "Paid",      action: "Mark as Paid",
                               allowedRoles: [systemManagerRole],
                               conditionExpression: "outstanding_amount <= 0"),
            WorkflowTransition(from: "Submitted", to: "Cancelled", action: "Cancel",
                               allowedRoles: [systemManagerRole]),
        ]
    )

    // MARK: - Buying

    public static let supplierQuotation = WorkflowDefinition(
        id: "wf-supplier-quotation",
        name: "Supplier Quotation",
        docType: "SupplierQuotation",
        states: [
            WorkflowState(name: "Draft",     isDefault: true,  allowEdit: true),
            WorkflowState(name: "Submitted", isDefault: false, allowEdit: false),
            WorkflowState(name: "Ordered",   isDefault: false, allowEdit: false),
            WorkflowState(name: "Cancelled", isDefault: false, allowEdit: false),
        ],
        transitions: [
            WorkflowTransition(from: "Draft",     to: "Submitted", action: "Submit",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Submitted", to: "Ordered",   action: "Mark as Ordered",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Submitted", to: "Cancelled", action: "Cancel",
                               allowedRoles: [systemManagerRole]),
        ]
    )

    public static let purchaseOrder = WorkflowDefinition(
        id: "wf-purchase-order",
        name: "Purchase Order",
        docType: "PurchaseOrder",
        states: [
            WorkflowState(name: "Draft",     isDefault: true,  allowEdit: true),
            WorkflowState(name: "Submitted", isDefault: false, allowEdit: false),
            WorkflowState(name: "Closed",    isDefault: false, allowEdit: false),
            WorkflowState(name: "Cancelled", isDefault: false, allowEdit: false),
        ],
        transitions: [
            WorkflowTransition(from: "Draft",     to: "Submitted", action: "Submit",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Submitted", to: "Closed",    action: "Close",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Submitted", to: "Cancelled", action: "Cancel",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Closed",    to: "Submitted", action: "Re-open",
                               allowedRoles: [systemManagerRole]),
        ]
    )

    public static let purchaseInvoice = WorkflowDefinition(
        id: "wf-purchase-invoice",
        name: "Purchase Invoice",
        docType: "PurchaseInvoice",
        states: [
            WorkflowState(name: "Draft",     isDefault: true,  allowEdit: true),
            WorkflowState(name: "Submitted", isDefault: false, allowEdit: false),
            WorkflowState(name: "Paid",      isDefault: false, allowEdit: false),
            WorkflowState(name: "Overdue",   isDefault: false, allowEdit: false),
            WorkflowState(name: "Cancelled", isDefault: false, allowEdit: false),
        ],
        transitions: [
            WorkflowTransition(from: "Draft",     to: "Submitted", action: "Submit",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Submitted", to: "Paid",      action: "Mark as Paid",
                               allowedRoles: [systemManagerRole],
                               conditionExpression: "outstanding_amount <= 0"),
            WorkflowTransition(from: "Submitted", to: "Overdue",   action: "Mark as Overdue",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Overdue",   to: "Paid",      action: "Mark as Paid",
                               allowedRoles: [systemManagerRole],
                               conditionExpression: "outstanding_amount <= 0"),
            WorkflowTransition(from: "Submitted", to: "Cancelled", action: "Cancel",
                               allowedRoles: [systemManagerRole]),
        ]
    )

    // MARK: - Stock + Accounting (canonical Draft / Submitted / Cancelled only)

    public static let stockEntry = WorkflowDefinition(
        id: "wf-stock-entry",
        name: "Stock Entry",
        docType: "StockEntry",
        states: [
            WorkflowState(name: "Draft",     isDefault: true,  allowEdit: true),
            WorkflowState(name: "Submitted", isDefault: false, allowEdit: false),
            WorkflowState(name: "Cancelled", isDefault: false, allowEdit: false),
        ],
        transitions: [
            WorkflowTransition(from: "Draft",     to: "Submitted", action: "Submit",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Submitted", to: "Cancelled", action: "Cancel",
                               allowedRoles: [systemManagerRole]),
        ]
    )

    public static let journalEntry = WorkflowDefinition(
        id: "wf-journal-entry",
        name: "Journal Entry",
        docType: "JournalEntry",
        states: [
            WorkflowState(name: "Draft",     isDefault: true,  allowEdit: true),
            WorkflowState(name: "Submitted", isDefault: false, allowEdit: false),
            WorkflowState(name: "Cancelled", isDefault: false, allowEdit: false),
        ],
        transitions: [
            WorkflowTransition(from: "Draft",     to: "Submitted", action: "Submit",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Submitted", to: "Cancelled", action: "Cancel",
                               allowedRoles: [systemManagerRole]),
        ]
    )

    public static let paymentEntry = WorkflowDefinition(
        id: "wf-payment-entry",
        name: "Payment Entry",
        docType: "PaymentEntry",
        states: [
            WorkflowState(name: "Draft",      isDefault: true,  allowEdit: true),
            WorkflowState(name: "Submitted",  isDefault: false, allowEdit: false),
            WorkflowState(name: "Reconciled", isDefault: false, allowEdit: false),
            WorkflowState(name: "Cancelled",  isDefault: false, allowEdit: false),
        ],
        transitions: [
            WorkflowTransition(from: "Draft",     to: "Submitted",  action: "Submit",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Submitted", to: "Reconciled", action: "Reconcile",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Submitted", to: "Cancelled",  action: "Cancel",
                               allowedRoles: [systemManagerRole]),
        ]
    )

    // MARK: - Registration

    public static let allWorkflows: [WorkflowDefinition] = [
        quotation,
        salesOrder,
        salesInvoice,
        supplierQuotation,
        purchaseOrder,
        purchaseInvoice,
        stockEntry,
        journalEntry,
        paymentEntry,
    ]

    public static func workflow(forDocTypeId docTypeId: String) -> WorkflowDefinition? {
        allWorkflows.first { $0.docType == docTypeId }
    }
}
