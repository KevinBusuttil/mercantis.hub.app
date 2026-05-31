import MercantisCore

/// Hub-side registry of built-in list views per DocType.
///
/// Core owns the generic `RecordListViewDefinition` model and the rendering;
/// Hub supplies the ERP-specific "All / Draft / Unpaid / Overdue" tabs an
/// operator expects. Core never references these — `RootView` passes the
/// result of `views(for:)` into `RecordCollectionHostView(listViews:)`, so a
/// DocType with no entry here simply falls back to Core's synthesised status
/// chips.
///
/// Predicates use the same `ListFilter` model the engine consumes. Two status
/// conventions exist in Hub and both are honoured:
/// - `docStatus` (Int): 0 Draft / 1 Submitted / 2 Cancelled — the lifecycle.
/// - `status` (String): workflow state ("Paid", "Overdue", "Closed", …).
///
/// Chip *labels* are resolved through `HubWorkflowDisplayPolicy` so they show
/// the same business wording as the badges (e.g. a SalesInvoice's "Submitted"
/// lifecycle chip reads "Posted"), while the *predicates* keep matching the
/// raw persisted values — display aliases never touch the query.
///
/// Only fields that actually exist on the current Hub DocTypes are referenced.
enum HubListViews {

    /// Built-in views for `docTypeId`, or `[]` to let Core synthesise chips.
    static func views(for docTypeId: String) -> [RecordListViewDefinition] {
        switch docTypeId {
        case "SalesInvoice":   return salesInvoice
        case "SalesOrder":     return salesOrder
        case "Quotation":      return quotation
        case "PurchaseOrder":  return purchaseOrder
        case "PurchaseInvoice": return purchaseInvoice
        case "StockEntry":     return stockEntry
        case "Item":           return item
        case "Customer":       return customer
        case "Supplier":       return supplier
        case "PaymentEntry":   return paymentEntry
        case "JournalEntry":   return journalEntry
        default:               return []
        }
    }

    // MARK: - Helpers

    private static let policy = HubWorkflowDisplayPolicy.policy

    private static func lifecycleLabel(_ docType: String, _ docStatus: Int) -> String {
        policy.lifecycleDisplay(docTypeId: docType, docStatus: docStatus).label
    }

    private static func draft(for docType: String, _ image: String = "pencil") -> RecordListViewDefinition {
        RecordListViewDefinition(id: "draft", label: lifecycleLabel(docType, 0), systemImage: image,
                                 predicates: [ListFilter("docStatus", .eq(.int(0)))])
    }
    private static func submitted(for docType: String) -> RecordListViewDefinition {
        RecordListViewDefinition(id: "submitted", label: lifecycleLabel(docType, 1), systemImage: "checkmark.seal",
                                 predicates: [ListFilter("docStatus", .eq(.int(1)))])
    }
    private static func cancelled(for docType: String) -> RecordListViewDefinition {
        RecordListViewDefinition(id: "cancelled", label: lifecycleLabel(docType, 2), systemImage: "xmark.seal",
                                 predicates: [ListFilter("docStatus", .eq(.int(2)))])
    }
    /// `rawState` is the persisted workflow string used by the predicate; the
    /// visible label is the policy alias for `(docType, rawState)`.
    private static func status(_ id: String, _ rawState: String, _ image: String, for docType: String) -> RecordListViewDefinition {
        RecordListViewDefinition(id: id,
                                 label: policy.statusDisplay(docTypeId: docType, state: rawState).label,
                                 systemImage: image,
                                 predicates: [ListFilter("status", .eq(.string(rawState)))])
    }
    private static func purpose(_ value: String, _ image: String) -> RecordListViewDefinition {
        RecordListViewDefinition(id: "purpose:\(value)", label: value, systemImage: image,
                                 predicates: [ListFilter("purpose", .eq(.string(value)))])
    }

    // MARK: - Selling

    private static var salesInvoice: [RecordListViewDefinition] {
        let dt = "SalesInvoice"
        return [
            .all(),
            draft(for: dt),
            submitted(for: dt),
            status("paid", "Paid", "checkmark.circle", for: dt),
            status("overdue", "Overdue", "exclamationmark.circle", for: dt),
            // `outstanding_amount` exists on SalesInvoice; > 0 = still owed.
            RecordListViewDefinition(id: "outstanding", label: "Outstanding", systemImage: "creditcard",
                                     predicates: [ListFilter("outstanding_amount", .gt(.double(0)))]),
            cancelled(for: dt)
        ]
    }

    private static var salesOrder: [RecordListViewDefinition] {
        let dt = "SalesOrder"
        return [.all(), draft(for: dt), submitted(for: dt), status("closed", "Closed", "lock", for: dt), cancelled(for: dt)]
    }

    private static var quotation: [RecordListViewDefinition] {
        let dt = "Quotation"
        return [
            .all(), draft(for: dt), submitted(for: dt),
            status("ordered", "Ordered", "cart", for: dt),
            status("lost", "Lost", "xmark.bin", for: dt),
            cancelled(for: dt)
        ]
    }

    // MARK: - Buying

    private static var purchaseOrder: [RecordListViewDefinition] {
        let dt = "PurchaseOrder"
        return [.all(), draft(for: dt), submitted(for: dt), status("closed", "Closed", "lock", for: dt), cancelled(for: dt)]
    }

    private static var purchaseInvoice: [RecordListViewDefinition] {
        let dt = "PurchaseInvoice"
        return [
            .all(), draft(for: dt), submitted(for: dt),
            status("paid", "Paid", "checkmark.circle", for: dt),
            status("overdue", "Overdue", "exclamationmark.circle", for: dt),
            RecordListViewDefinition(id: "outstanding", label: "Outstanding", systemImage: "creditcard",
                                     predicates: [ListFilter("outstanding_amount", .gt(.double(0)))]),
            cancelled(for: dt)
        ]
    }

    // MARK: - Stock

    private static var stockEntry: [RecordListViewDefinition] {
        let dt = "StockEntry"
        return [
            .all(),
            purpose("Material Receipt", "tray.and.arrow.down"),
            purpose("Material Issue", "tray.and.arrow.up"),
            purpose("Material Transfer", "arrow.left.arrow.right"),
            submitted(for: dt),
            cancelled(for: dt)
        ]
    }

    // MARK: - Masters

    private static var item: [RecordListViewDefinition] {
        // Item has no is_active/disabled field; it carries is_stock_item /
        // is_sales_item booleans, so surface those instead of inventing flags.
        [
            .all(),
            RecordListViewDefinition(id: "stock", label: "Stock Items", systemImage: "shippingbox",
                                     predicates: [ListFilter("is_stock_item", .eq(.bool(true)))]),
            RecordListViewDefinition(id: "sales", label: "Sales Items", systemImage: "cart",
                                     predicates: [ListFilter("is_sales_item", .eq(.bool(true)))])
        ]
    }

    private static var customer: [RecordListViewDefinition] {
        // Customer has no is_active field. Territory / customer_group exist but
        // need a value to filter on, so they're offered via the field-filter
        // menu rather than as fixed chips. Default sort by name for usability.
        [
            RecordListViewDefinition(id: "all", label: "All", systemImage: "tray.full",
                                     sort: [ListSort(fieldKey: "customer_name", direction: .ascending)])
        ]
    }

    private static var supplier: [RecordListViewDefinition] {
        [
            RecordListViewDefinition(id: "all", label: "All", systemImage: "tray.full",
                                     sort: [ListSort(fieldKey: "supplier_name", direction: .ascending)])
        ]
    }

    // MARK: - Accounting

    private static var paymentEntry: [RecordListViewDefinition] {
        let dt = "PaymentEntry"
        return [
            .all(),
            RecordListViewDefinition(id: "receive", label: "Receive", systemImage: "arrow.down.circle",
                                     predicates: [ListFilter("payment_type", .eq(.string("Receive")))]),
            RecordListViewDefinition(id: "pay", label: "Pay", systemImage: "arrow.up.circle",
                                     predicates: [ListFilter("payment_type", .eq(.string("Pay")))]),
            submitted(for: dt)
        ]
    }

    private static var journalEntry: [RecordListViewDefinition] {
        let dt = "JournalEntry"
        return [.all(), draft(for: dt), submitted(for: dt), cancelled(for: dt)]
    }
}
