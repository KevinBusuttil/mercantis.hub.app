import Foundation
import MercantisCore

/// Hub-specific business wording for Core's lifecycle (`docStatus`) and
/// workflow (`Document.status`) states.
///
/// This is the single place that translates the internal AX-style spine into
/// the friendly, document-specific language a small business expects:
///
/// - Invoice:      Draft → Posted → Cancelled       (action: "Post Invoice")
/// - Sales Order:  Draft → Confirmed → Closed        (action: "Confirm Order")
/// - Quotation:    Draft → Sent → Accepted / Lost    (action: "Send Quote")
/// - Stock Entry:  Draft → Posted → Reversed         (action: "Post Stock Movement")
/// - BOM:          Draft → Active → Inactive         (action: "Activate BOM")
/// - Work Order:   Draft → Released → … → Completed   (action: "Release Work Order")
///
/// IMPORTANT: nothing here renames a persisted workflow state or `docStatus`
/// value — these are *display aliases only*. The internal `Submitted` state and
/// the GL / CustTrans / VendTrans / StockLedgerEntry / Settlement / TaxTrans
/// derivation are completely untouched. No data migration is required.
enum HubWorkflowDisplayPolicy {

    /// The composed policy injected into Core's UI components and consumed by
    /// `HubDocumentEditor` for action / badge wording.
    static let policy = DocumentDisplayPolicy(mappings: mappings)

    // MARK: - Reusable confirmation copy

    private static let postLedgerConfirmation =
        "Posting this document locks most fields and automatically creates the matching accounting and audit entries."
    private static let cancelLedgerConfirmation =
        "Cancelling this posted document creates reversal entries. The original document and its audit trail are retained."
    private static let postStockConfirmation =
        "Posting this stock movement updates stock history and creates stock ledger entries."
    private static let reverseStockConfirmation =
        "Reversing this stock movement creates compensating stock ledger entries. The audit trail is retained."
    private static let completeWorkOrderConfirmation =
        "Completing this work order posts a manufacturing stock movement: raw materials are consumed and the finished item is received, creating stock ledger entries."

    // MARK: - Mapping table

    private static let mappings: [String: DocTypeDisplayMapping] = [

        // MARK: Sales

        "Quotation": DocTypeDisplayMapping(
            statuses: [
                "Draft":     .init(label: "Draft",     tone: .muted),
                "Submitted": .init(label: "Sent",      tone: .info,
                                   help: "The quote has been sent to the customer."),
                "Ordered":   .init(label: "Accepted",  tone: .success,
                                   help: "The customer accepted the quote."),
                "Lost":      .init(label: "Lost",      tone: .danger),
                "Cancelled": .init(label: "Cancelled", tone: .danger),
            ],
            actions: [
                "Submit":          .init(label: "Send Quote"),
                "Mark as Ordered": .init(label: "Mark as Accepted"),
                "Mark as Lost":    .init(label: "Mark as Lost"),
                "Cancel":          .init(label: "Cancel Quote"),
            ]
        ),

        "SalesOrder": DocTypeDisplayMapping(
            statuses: [
                "Draft":     .init(label: "Draft",     tone: .muted),
                "Submitted": .init(label: "Confirmed", tone: .brand,
                                   help: "The order is confirmed and ready to fulfil."),
                "Closed":    .init(label: "Closed",    tone: .muted),
                "Cancelled": .init(label: "Cancelled", tone: .danger),
            ],
            actions: [
                "Submit":  .init(label: "Confirm Order"),
                "Close":   .init(label: "Close Order"),
                "Re-open": .init(label: "Re-open Order"),
                "Cancel":  .init(label: "Cancel Order"),
                "Amend":   .init(label: "Create Revised Order"),
            ]
        ),

        "SalesInvoice": DocTypeDisplayMapping(
            statuses: [
                "Draft":     .init(label: "Draft",     tone: .muted),
                "Submitted": .init(label: "Posted",    tone: .brand,
                                   help: "The invoice is issued and posted to the customer ledger."),
                "Paid":      .init(label: "Paid",      tone: .success),
                "Overdue":   .init(label: "Overdue",   tone: .warning),
                "Cancelled": .init(label: "Cancelled", tone: .danger),
            ],
            actions: [
                "Submit":          .init(label: "Post Invoice", confirmation: postLedgerConfirmation),
                "Cancel":          .init(label: "Cancel Invoice", confirmation: cancelLedgerConfirmation),
                "Amend":           .init(label: "Create Corrected Invoice"),
                "Mark as Paid":    .init(label: "Mark as Paid"),
                "Mark as Overdue": .init(label: "Mark as Overdue"),
            ]
        ),

        // MARK: Buying

        "SupplierQuotation": DocTypeDisplayMapping(
            statuses: [
                "Draft":     .init(label: "Draft",     tone: .muted),
                "Submitted": .init(label: "Received",  tone: .brand,
                                   help: "The supplier's quote has been recorded."),
                "Ordered":   .init(label: "Ordered",   tone: .success),
                "Cancelled": .init(label: "Cancelled", tone: .danger),
            ],
            actions: [
                "Submit":          .init(label: "Record Supplier Quote"),
                "Mark as Ordered": .init(label: "Mark as Ordered"),
                "Cancel":          .init(label: "Cancel"),
            ]
        ),

        "PurchaseOrder": DocTypeDisplayMapping(
            statuses: [
                "Draft":     .init(label: "Draft",     tone: .muted),
                "Submitted": .init(label: "Confirmed", tone: .brand,
                                   help: "The order is confirmed and sent to the supplier."),
                "Closed":    .init(label: "Closed",    tone: .muted),
                "Cancelled": .init(label: "Cancelled", tone: .danger),
            ],
            actions: [
                "Submit":  .init(label: "Confirm Order"),
                "Close":   .init(label: "Close Order"),
                "Re-open": .init(label: "Re-open Order"),
                "Cancel":  .init(label: "Cancel Order"),
                "Amend":   .init(label: "Create Revised Order"),
            ]
        ),

        "PurchaseInvoice": DocTypeDisplayMapping(
            statuses: [
                "Draft":     .init(label: "Draft",     tone: .muted),
                "Submitted": .init(label: "Posted",    tone: .brand,
                                   help: "The bill is posted to the supplier ledger."),
                "Paid":      .init(label: "Paid",      tone: .success),
                "Overdue":   .init(label: "Overdue",   tone: .warning),
                "Cancelled": .init(label: "Cancelled", tone: .danger),
            ],
            actions: [
                "Submit":          .init(label: "Post Bill", confirmation: postLedgerConfirmation),
                "Cancel":          .init(label: "Cancel Bill", confirmation: cancelLedgerConfirmation),
                "Amend":           .init(label: "Create Corrected Bill"),
                "Mark as Paid":    .init(label: "Mark as Paid"),
                "Mark as Overdue": .init(label: "Mark as Overdue"),
            ]
        ),

        // MARK: Stock

        "StockEntry": DocTypeDisplayMapping(
            statuses: [
                "Draft":     .init(label: "Draft",    tone: .muted),
                "Submitted": .init(label: "Posted",   tone: .brand,
                                   help: "The movement is posted and stock history is updated."),
                "Cancelled": .init(label: "Reversed", tone: .danger,
                                   help: "The movement has been reversed with compensating entries."),
            ],
            actions: [
                "Submit": .init(label: "Post Stock Movement", confirmation: postStockConfirmation),
                "Cancel": .init(label: "Reverse Stock Movement", confirmation: reverseStockConfirmation),
                "Amend":  .init(label: "Create Correction"),
            ]
        ),

        // MARK: Accounting

        "JournalEntry": DocTypeDisplayMapping(
            statuses: [
                "Draft":     .init(label: "Draft",    tone: .muted),
                "Submitted": .init(label: "Posted",   tone: .brand,
                                   help: "The journal is posted to the general ledger."),
                "Cancelled": .init(label: "Reversed", tone: .danger),
            ],
            actions: [
                "Submit": .init(label: "Post Journal", confirmation: postLedgerConfirmation),
                "Cancel": .init(label: "Reverse Journal", confirmation: cancelLedgerConfirmation),
                "Amend":  .init(label: "Create Reversal / Correction"),
            ]
        ),

        "PaymentEntry": DocTypeDisplayMapping(
            statuses: [
                "Draft":      .init(label: "Draft",      tone: .muted),
                "Submitted":  .init(label: "Posted",     tone: .brand,
                                    help: "The payment is posted to the ledger."),
                "Reconciled": .init(label: "Reconciled", tone: .success,
                                    help: "The payment has been matched against a bank line."),
                "Cancelled":  .init(label: "Cancelled",  tone: .danger),
            ],
            actions: [
                "Submit":    .init(label: "Post Payment", confirmation: postLedgerConfirmation),
                "Reconcile": .init(label: "Mark Reconciled"),
                "Cancel":    .init(label: "Cancel Payment", confirmation: cancelLedgerConfirmation),
            ]
        ),

        // MARK: Manufacturing

        "BOM": DocTypeDisplayMapping(
            statuses: [
                "Draft":     .init(label: "Draft",     tone: .muted),
                "Submitted": .init(label: "Active",    tone: .success,
                                   help: "This BOM is active and usable in production."),
                "Inactive":  .init(label: "Inactive",  tone: .muted),
                "Cancelled": .init(label: "Cancelled", tone: .danger),
            ],
            actions: [
                "Submit":     .init(label: "Activate BOM"),
                "Deactivate": .init(label: "Deactivate"),
                "Reactivate": .init(label: "Reactivate"),
                "Cancel":     .init(label: "Cancel"),
            ]
        ),

        "WorkOrder": DocTypeDisplayMapping(
            statuses: [
                "Draft":      .init(label: "Draft",       tone: .muted),
                "Submitted":  .init(label: "Released",    tone: .brand,
                                    help: "The work order is released to the shop floor."),
                "InProgress": .init(label: "In Progress", tone: .info),
                "Completed":  .init(label: "Completed",   tone: .success),
                "Stopped":    .init(label: "Stopped",     tone: .warning),
                "Cancelled":  .init(label: "Cancelled",   tone: .danger),
            ],
            actions: [
                "Submit":   .init(label: "Release Work Order"),
                "Start":    .init(label: "Start"),
                "Complete": .init(label: "Complete", confirmation: completeWorkOrderConfirmation),
                "Stop":     .init(label: "Stop"),
                "Resume":   .init(label: "Resume"),
                "Cancel":   .init(label: "Cancel"),
            ]
        ),

        "JobCard": DocTypeDisplayMapping(
            statuses: [
                "Draft":      .init(label: "Draft",       tone: .muted),
                "InProgress": .init(label: "In Progress", tone: .info),
                "Submitted":  .init(label: "Completed",   tone: .success,
                                    help: "The job is complete."),
                "Cancelled":  .init(label: "Cancelled",   tone: .danger),
            ],
            actions: [
                "Start":             .init(label: "Start Job"),
                "Submit":            .init(label: "Complete Job"),
                "Submit (skip start)": .init(label: "Complete Job"),
                "Cancel":            .init(label: "Cancel"),
            ]
        ),

        "ProductionPlan": DocTypeDisplayMapping(
            statuses: [
                "Draft":     .init(label: "Draft",     tone: .muted),
                "Submitted": .init(label: "Planned",   tone: .info,
                                   help: "The plan is released; work orders have been generated."),
                "Cancelled": .init(label: "Cancelled", tone: .danger),
            ],
            actions: [
                "Submit": .init(label: "Release Plan"),
                "Cancel": .init(label: "Cancel"),
            ]
        ),
    ]
}
