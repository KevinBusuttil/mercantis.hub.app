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
            WorkflowState(name: "Expired",   isDefault: false, allowEdit: false),
            WorkflowState(name: "Cancelled", isDefault: false, allowEdit: false),
        ],
        transitions: [
            WorkflowTransition(from: "Draft",     to: "Submitted", action: "Submit",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Submitted", to: "Ordered",   action: "Mark as Ordered",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Submitted", to: "Lost",      action: "Mark as Lost",
                               allowedRoles: [systemManagerRole]),
            // Past its valid-till date the quote auto-expires (or the owner can
            // mark it); a late acceptance can still convert it to an order.
            WorkflowTransition(from: "Submitted", to: "Expired",   action: "Mark as Expired",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Expired",   to: "Ordered",   action: "Mark as Ordered",
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

    public static let purchaseReceipt = WorkflowDefinition(
        id: "wf-purchase-receipt",
        name: "Purchase Receipt",
        docType: "PurchaseReceipt",
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

    // MARK: - Deliveries

    /// Sales Delivery status lifecycle. "Submit" confirms the delivery
    /// (Draft → Scheduled) and is the docStatus trigger that decrements
    /// stock; the remaining transitions track the physical journey. Cancel
    /// is reachable from every active state and reverses the stock movement.
    public static let salesDelivery = WorkflowDefinition(
        id: "wf-sales-delivery",
        name: "Sales Delivery",
        docType: "SalesDelivery",
        states: [
            WorkflowState(name: "Draft",            isDefault: true,  allowEdit: true),
            WorkflowState(name: "Scheduled",        isDefault: false, allowEdit: false),
            WorkflowState(name: "Loaded",           isDefault: false, allowEdit: false),
            WorkflowState(name: "Out for Delivery", isDefault: false, allowEdit: false),
            WorkflowState(name: "Delivered",        isDefault: false, allowEdit: false),
            WorkflowState(name: "Failed",           isDefault: false, allowEdit: false),
            WorkflowState(name: "Cancelled",        isDefault: false, allowEdit: false),
        ],
        transitions: [
            WorkflowTransition(from: "Draft",            to: "Scheduled",        action: "Submit",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Scheduled",        to: "Loaded",           action: "Mark Loaded",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Loaded",           to: "Out for Delivery", action: "Mark Out for Delivery",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Out for Delivery", to: "Delivered",        action: "Mark Delivered",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Out for Delivery", to: "Failed",           action: "Mark Failed",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Failed",           to: "Scheduled",        action: "Reschedule",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Scheduled",        to: "Cancelled",        action: "Cancel",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Loaded",           to: "Cancelled",        action: "Cancel",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Out for Delivery", to: "Cancelled",        action: "Cancel",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Delivered",        to: "Cancelled",        action: "Cancel",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Failed",           to: "Cancelled",        action: "Cancel",
                               allowedRoles: [systemManagerRole]),
        ]
    )

    // MARK: - POS

    public static let posInvoice = WorkflowDefinition(
        id: "wf-pos-invoice",
        name: "POS Sale",
        docType: "POSInvoice",
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

    // MARK: - Manufacturing

    public static let bom = WorkflowDefinition(
        id: "wf-bom",
        name: "BOM",
        docType: "BOM",
        states: [
            WorkflowState(name: "Draft",     isDefault: true,  allowEdit: true),
            WorkflowState(name: "Submitted", isDefault: false, allowEdit: false),
            WorkflowState(name: "Inactive",  isDefault: false, allowEdit: false),
            WorkflowState(name: "Cancelled", isDefault: false, allowEdit: false),
        ],
        transitions: [
            WorkflowTransition(from: "Draft",     to: "Submitted", action: "Submit",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Submitted", to: "Inactive",  action: "Deactivate",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Inactive",  to: "Submitted", action: "Reactivate",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Submitted", to: "Cancelled", action: "Cancel",
                               allowedRoles: [systemManagerRole]),
        ]
    )

    public static let workOrder = WorkflowDefinition(
        id: "wf-work-order",
        name: "Work Order",
        docType: "WorkOrder",
        states: [
            WorkflowState(name: "Draft",      isDefault: true,  allowEdit: true),
            WorkflowState(name: "Submitted",  isDefault: false, allowEdit: false),
            WorkflowState(name: "InProgress", isDefault: false, allowEdit: false),
            WorkflowState(name: "Completed",  isDefault: false, allowEdit: false),
            WorkflowState(name: "Stopped",    isDefault: false, allowEdit: false),
            WorkflowState(name: "Cancelled",  isDefault: false, allowEdit: false),
        ],
        transitions: [
            WorkflowTransition(from: "Draft",      to: "Submitted",  action: "Submit",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Submitted",  to: "InProgress", action: "Start",
                               allowedRoles: [systemManagerRole]),
            // Entering "Completed" is the trigger that
            // `ManufacturingDerivationService` watches to post the
            // "Manufacturing" Stock Entry that consumes raw materials
            // and produces the finished good.
            WorkflowTransition(from: "InProgress", to: "Completed",  action: "Complete",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "InProgress", to: "Stopped",    action: "Stop",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Stopped",    to: "InProgress", action: "Resume",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Submitted",  to: "Cancelled",  action: "Cancel",
                               allowedRoles: [systemManagerRole]),
        ]
    )

    public static let jobCard = WorkflowDefinition(
        id: "wf-job-card",
        name: "Job Card",
        docType: "JobCard",
        states: [
            WorkflowState(name: "Draft",      isDefault: true,  allowEdit: true),
            WorkflowState(name: "InProgress", isDefault: false, allowEdit: true),
            WorkflowState(name: "Submitted",  isDefault: false, allowEdit: false),
            WorkflowState(name: "Cancelled",  isDefault: false, allowEdit: false),
        ],
        transitions: [
            WorkflowTransition(from: "Draft",      to: "InProgress", action: "Start",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "InProgress", to: "Submitted",  action: "Submit",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Draft",      to: "Submitted",  action: "Submit (skip start)",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Submitted",  to: "Cancelled",  action: "Cancel",
                               allowedRoles: [systemManagerRole]),
        ]
    )

    public static let productionPlan = WorkflowDefinition(
        id: "wf-production-plan",
        name: "Production Plan",
        docType: "ProductionPlan",
        states: [
            WorkflowState(name: "Draft",     isDefault: true,  allowEdit: true),
            WorkflowState(name: "Submitted", isDefault: false, allowEdit: false),
            WorkflowState(name: "Cancelled", isDefault: false, allowEdit: false),
        ],
        transitions: [
            // Submit triggers `ManufacturingDerivationService` to
            // generate one Draft Work Order per row in
            // `items_to_manufacture` (deterministic ids → replay-safe).
            WorkflowTransition(from: "Draft",     to: "Submitted", action: "Submit",
                               allowedRoles: [systemManagerRole]),
            WorkflowTransition(from: "Submitted", to: "Cancelled", action: "Cancel",
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
        purchaseReceipt,
        salesDelivery,
        posInvoice,
        stockEntry,
        journalEntry,
        paymentEntry,
        bom,
        workOrder,
        jobCard,
        productionPlan,
    ]

    public static func workflow(forDocTypeId docTypeId: String) -> WorkflowDefinition? {
        allWorkflows.first { $0.docType == docTypeId }
    }
}
