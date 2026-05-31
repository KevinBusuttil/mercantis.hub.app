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

    private static func draft(_ image: String = "pencil") -> RecordListViewDefinition {
        RecordListViewDefinition(id: "draft", label: "Draft", systemImage: image,
                                 predicates: [ListFilter("docStatus", .eq(.int(0)))])
    }
    private static func submitted() -> RecordListViewDefinition {
        RecordListViewDefinition(id: "submitted", label: "Submitted", systemImage: "checkmark.seal",
                                 predicates: [ListFilter("docStatus", .eq(.int(1)))])
    }
    private static func cancelled() -> RecordListViewDefinition {
        RecordListViewDefinition(id: "cancelled", label: "Cancelled", systemImage: "xmark.seal",
                                 predicates: [ListFilter("docStatus", .eq(.int(2)))])
    }
    private static func status(_ id: String, _ label: String, _ image: String) -> RecordListViewDefinition {
        RecordListViewDefinition(id: id, label: label, systemImage: image,
                                 predicates: [ListFilter("status", .eq(.string(label)))])
    }
    private static func purpose(_ value: String, _ image: String) -> RecordListViewDefinition {
        RecordListViewDefinition(id: "purpose:\(value)", label: value, systemImage: image,
                                 predicates: [ListFilter("purpose", .eq(.string(value)))])
    }

    // MARK: - Selling

    private static var salesInvoice: [RecordListViewDefinition] {
        [
            .all(),
            draft(),
            submitted(),
            status("paid", "Paid", "checkmark.circle"),
            status("overdue", "Overdue", "exclamationmark.circle"),
            // `outstanding_amount` exists on SalesInvoice; > 0 = still owed.
            RecordListViewDefinition(id: "outstanding", label: "Outstanding", systemImage: "creditcard",
                                     predicates: [ListFilter("outstanding_amount", .gt(.double(0)))]),
            cancelled()
        ]
    }

    private static var salesOrder: [RecordListViewDefinition] {
        [.all(), draft(), submitted(), status("closed", "Closed", "lock"), cancelled()]
    }

    private static var quotation: [RecordListViewDefinition] {
        [
            .all(), draft(), submitted(),
            status("ordered", "Ordered", "cart"),
            status("lost", "Lost", "xmark.bin"),
            cancelled()
        ]
    }

    // MARK: - Buying

    private static var purchaseOrder: [RecordListViewDefinition] {
        [.all(), draft(), submitted(), status("closed", "Closed", "lock"), cancelled()]
    }

    private static var purchaseInvoice: [RecordListViewDefinition] {
        [
            .all(), draft(), submitted(),
            status("paid", "Paid", "checkmark.circle"),
            status("overdue", "Overdue", "exclamationmark.circle"),
            RecordListViewDefinition(id: "outstanding", label: "Outstanding", systemImage: "creditcard",
                                     predicates: [ListFilter("outstanding_amount", .gt(.double(0)))]),
            cancelled()
        ]
    }

    // MARK: - Stock

    private static var stockEntry: [RecordListViewDefinition] {
        [
            .all(),
            purpose("Material Receipt", "tray.and.arrow.down"),
            purpose("Material Issue", "tray.and.arrow.up"),
            purpose("Material Transfer", "arrow.left.arrow.right"),
            submitted(),
            cancelled()
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
        [
            .all(),
            RecordListViewDefinition(id: "receive", label: "Receive", systemImage: "arrow.down.circle",
                                     predicates: [ListFilter("payment_type", .eq(.string("Receive")))]),
            RecordListViewDefinition(id: "pay", label: "Pay", systemImage: "arrow.up.circle",
                                     predicates: [ListFilter("payment_type", .eq(.string("Pay")))]),
            submitted()
        ]
    }

    private static var journalEntry: [RecordListViewDefinition] {
        [.all(), draft(), submitted(), cancelled()]
    }
}
