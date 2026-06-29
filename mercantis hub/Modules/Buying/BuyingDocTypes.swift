import MercantisCore

private let systemManagerPermission = PermissionRule(
    role: "System Manager",
    canRead: true,
    canWrite: true,
    canCreate: true,
    canDelete: true,
    canSubmit: false,
    canAmend: false
)

enum Buying {

    // MARK: - Child DocTypes

    /// One row inside a buy-side line-item table (Supplier Quotation,
    /// Purchase Order, Purchase Invoice). Wall 5 unlocks the structure;
    /// Wall 6 will add workflow gating on the parent.
    static let purchaseItem = DocType(
        id: "PurchaseItem",
        name: "Purchase Item",
        module: "Buying",
        appId: HubManifest.appID,
        isChildTable: true,
        fields: [
            FieldDefinition(key: "item", label: "Item",
                            type: .link, required: true, linkedDocType: "Item"),
            FieldDefinition(key: "description", label: "Description",
                            type: .text, required: false,
                            fetchFrom: "item.description"),
            FieldDefinition(key: "qty", label: "Quantity",
                            type: .decimal, required: true, defaultValue: .double(1)),
            FieldDefinition(key: "uom", label: "UOM",
                            type: .link, required: false, linkedDocType: "UOM"),
            FieldDefinition(key: "rate", label: "Rate",
                            type: .currency, required: true, defaultValue: .double(0)),
            FieldDefinition(key: "amount", label: "Amount",
                            type: .currency, required: false,
                            formulaExpression: "qty * rate"),
            FieldDefinition(key: "tax_code", label: "Tax Code",
                            type: .link, required: false, linkedDocType: "TaxCode"),
            FieldDefinition(key: "warehouse", label: "Target Warehouse",
                            type: .link, required: false, linkedDocType: "Warehouse"),
            FieldDefinition(key: "schedule_date", label: "Required By",
                            type: .date, required: false)
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: [],
        titleField: "item"
    )

    // MARK: - Parent DocTypes

    /// Supplier — Wall 4 unlocked the link fields (`supplier_group`,
    /// `default_currency`, `default_price_list`, `default_cost_center`).
    /// Per-supplier address / contact rows live as `links` rows on the
    /// shared Address / Contact DocTypes (Wall 5).
    static let supplier = DocType(
        id: "Supplier",
        name: "Supplier",
        module: "Buying",
        appId: HubManifest.appID,
        isChildTable: false,
        fields: [
            FieldDefinition(key: "supplier_name", label: "Supplier Name",
                            type: .text, required: true, isSearchable: true),
            FieldDefinition(key: "supplier_type", label: "Supplier Type",
                            type: .select, required: true,
                            options: ["Individual", "Company"]),
            FieldDefinition(key: "supplier_group", label: "Supplier Group",
                            type: .link, required: false, linkedDocType: "SupplierGroup"),
            FieldDefinition(key: "country", label: "Country", type: .text, required: false),
            FieldDefinition(key: "email_id", label: "Email",
                            type: .email, required: false, isSearchable: true),
            FieldDefinition(key: "mobile_no", label: "Mobile", type: .phone, required: false),
            FieldDefinition(key: "phone", label: "Phone", type: .phone, required: false),
            FieldDefinition(key: "tax_id", label: "Tax ID", type: .text, required: false),
            FieldDefinition(key: "tax_code", label: "Default Tax Code",
                            type: .link, required: false, linkedDocType: "TaxCode"),
            FieldDefinition(key: "default_currency", label: "Default Currency",
                            type: .link, required: false, linkedDocType: "Currency"),
            FieldDefinition(key: "default_price_list", label: "Default Buying Price List",
                            type: .link, required: false, linkedDocType: "PriceList"),
            FieldDefinition(key: "default_cost_center", label: "Default Cost Center",
                            type: .link, required: false, linkedDocType: "CostCenter"),
            FieldDefinition(key: "payment_terms", label: "Payment Terms",
                            type: .text, required: false),
            FieldDefinition(key: "notes", label: "Notes", type: .longText, required: false)
        ],
        permissions: [systemManagerPermission],
        autoname: "naming_series:SUPP-.YYYY.-.####",
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["supplier_name", "email_id"],
        titleField: "supplier_name",
        formLayout: FormLayout(sections: [
            FormLayoutSection(
                key: "identity",
                title: "Supplier",
                columns: 2,
                fieldKeys: ["supplier_name", "supplier_type", "supplier_group", "country"]
            ),
            FormLayoutSection(
                key: "reach",
                title: "Reach",
                columns: 2,
                fieldKeys: ["email_id", "mobile_no", "phone"]
            ),
            FormLayoutSection(
                key: "defaults",
                title: "Defaults",
                helpText: "Used when raising new purchase transactions for this supplier.",
                columns: 2,
                fieldKeys: ["default_currency", "default_price_list", "default_cost_center"]
            ),
            FormLayoutSection(
                key: "financial",
                title: "Financial",
                columns: 2,
                fieldKeys: ["tax_id", "tax_code", "payment_terms"]
            ),
            FormLayoutSection(
                key: "notes",
                title: "Notes",
                fieldKeys: ["notes"]
            )
        ])
    )

    private static let purchaseParentLayout: [FormLayoutSection] = [
        FormLayoutSection(
            key: "header",
            title: "Header",
            columns: 2,
            fieldKeys: ["supplier", "transaction_date", "currency", "price_list"]
        ),
        FormLayoutSection(
            key: "items",
            title: "Items",
            fieldKeys: ["items"]
        ),
        FormLayoutSection(
            key: "totals",
            title: "Totals",
            columns: 2,
            fieldKeys: ["total_qty", "grand_total"]
        ),
        FormLayoutSection(
            key: "notes",
            title: "Notes",
            fieldKeys: ["notes"]
        )
    ]

    private static let submittableSyncPolicy = SyncPolicy(
        conflictResolution: .versionChecked,
        immutableAfterSubmit: true
    )

    private static func purchaseParentFields(includeOutstanding: Bool = false) -> [FieldDefinition] {
        var fields: [FieldDefinition] = [
            FieldDefinition(key: "supplier", label: "Supplier",
                            type: .link, required: true, linkedDocType: "Supplier"),
            FieldDefinition(key: "transaction_date", label: "Date",
                            type: .date, required: true),
            FieldDefinition(key: "currency", label: "Currency",
                            type: .link, required: true, linkedDocType: "Currency"),
            FieldDefinition(key: "conversion_rate", label: "Exchange Rate to Base",
                            type: .decimal, required: false, defaultValue: .double(1)),
            FieldDefinition(key: "price_list", label: "Price List",
                            type: .link, required: false, linkedDocType: "PriceList"),
            FieldDefinition(key: "items", label: "Items",
                            type: .table, required: true, childDocType: "PurchaseItem"),
            // Derived on save by HubTaxCalculationPolicy — display only.
            FieldDefinition(key: "total_qty", label: "Total Qty",
                            type: .decimal, required: false,
                            readOnlyExpression: "true"),
            FieldDefinition(key: "grand_total", label: "Grand Total",
                            type: .currency, required: false,
                            readOnlyExpression: "true"),
            FieldDefinition(key: "notes", label: "Notes",
                            type: .longText, required: false,
                            allowOnSubmit: true)
        ]
        if includeOutstanding {
            fields.append(FieldDefinition(key: "due_date", label: "Due Date",
                                          type: .date, required: false,
                                          allowOnSubmit: true))
            fields.append(FieldDefinition(key: "outstanding_amount", label: "Outstanding",
                                          type: .currency, required: false,
                                          allowOnSubmit: true))
        }
        return fields
    }

    /// Supplier Quotation — pre-purchase RFQ response. Wall 6 makes it
    /// submittable with the `wf-supplier-quotation` workflow.
    static let supplierQuotation = DocType(
        id: "SupplierQuotation",
        name: "Supplier Quotation",
        module: "Buying",
        appId: HubManifest.appID,
        isChildTable: false,
        isSubmittable: true,
        fields: purchaseParentFields(),
        permissions: [systemManagerPermission],
        workflowId: "wf-supplier-quotation",
        autoname: "naming_series:SQTN-PURC-.YYYY.-.####",
        syncPolicy: submittableSyncPolicy,
        indexes: [],
        searchFields: ["supplier"],
        titleField: "supplier",
        formLayout: FormLayout(sections: purchaseParentLayout)
    )

    /// Fulfilment progress, written back by `PurchaseOrderFulfilmentService` as
    /// Receipts and Invoices are submitted against the order. `allowOnSubmit`
    /// so the post-commit service can update them on the already-submitted
    /// order; read-only in the form (they're derived totals, never typed in).
    private static let purchaseOrderFulfilmentFields: [FieldDefinition] = [
        FieldDefinition(key: "receipt_status", label: "Receipt Status",
                        type: .select, required: false,
                        helpText: "How much of this order has been received. Updated automatically as Purchase Receipts are submitted.",
                        defaultValue: .string("To Receive"),
                        options: ["To Receive", "Partially Received", "Fully Received"],
                        readOnlyExpression: "true", allowOnSubmit: true),
        FieldDefinition(key: "received_qty", label: "Received Qty",
                        type: .decimal, required: false,
                        readOnlyExpression: "true", allowOnSubmit: true),
        FieldDefinition(key: "per_received", label: "% Received",
                        type: .decimal, required: false,
                        readOnlyExpression: "true", allowOnSubmit: true),
        FieldDefinition(key: "billing_status", label: "Billing Status",
                        type: .select, required: false,
                        helpText: "How much of this order has been invoiced. Updated automatically as Purchase Invoices are submitted.",
                        defaultValue: .string("To Bill"),
                        options: ["To Bill", "Partially Billed", "Fully Billed"],
                        readOnlyExpression: "true", allowOnSubmit: true),
        FieldDefinition(key: "billed_qty", label: "Billed Qty",
                        type: .decimal, required: false,
                        readOnlyExpression: "true", allowOnSubmit: true),
        FieldDefinition(key: "per_billed", label: "% Billed",
                        type: .decimal, required: false,
                        readOnlyExpression: "true", allowOnSubmit: true),
    ]

    /// Purchase Order layout = the shared purchase layout plus a Fulfilment
    /// section (receipt / billing progress), inserted before the Notes block.
    private static let purchaseOrderLayout: [FormLayoutSection] = [
        FormLayoutSection(
            key: "header",
            title: "Header",
            columns: 2,
            fieldKeys: ["supplier", "transaction_date", "currency", "price_list"]
        ),
        FormLayoutSection(
            key: "items",
            title: "Items",
            fieldKeys: ["items"]
        ),
        FormLayoutSection(
            key: "totals",
            title: "Totals",
            columns: 2,
            fieldKeys: ["total_qty", "grand_total"]
        ),
        FormLayoutSection(
            key: "fulfilment",
            title: "Fulfilment",
            helpText: "Receipt and billing progress, updated automatically as Receipts and Invoices are submitted against this order.",
            columns: 2,
            fieldKeys: ["receipt_status", "per_received", "billing_status", "per_billed"]
        ),
        FormLayoutSection(
            key: "notes",
            title: "Notes",
            fieldKeys: ["notes"]
        )
    ]

    /// Purchase Order — confirmed purchase, awaiting receipt. Wall 6
    /// makes it submittable with the `wf-purchase-order` workflow.
    static let purchaseOrder = DocType(
        id: "PurchaseOrder",
        name: "Purchase Order",
        module: "Buying",
        appId: HubManifest.appID,
        isChildTable: false,
        isSubmittable: true,
        fields: purchaseParentFields() + purchaseOrderFulfilmentFields,
        permissions: [systemManagerPermission],
        workflowId: "wf-purchase-order",
        autoname: "naming_series:PO-.YYYY.-.####",
        syncPolicy: submittableSyncPolicy,
        indexes: [],
        searchFields: ["supplier"],
        titleField: "supplier",
        formLayout: FormLayout(sections: purchaseOrderLayout)
    )

    /// Purchase Invoice — billable line items, accounts-payable trigger.
    /// Wall 6 makes it submittable with the `wf-purchase-invoice` workflow.
    /// Wall 7 auto-derives GL entries from `credit_to` (Cr) and
    /// `expense_account` (Dr) on submit.
    static let purchaseInvoice = DocType(
        id: "PurchaseInvoice",
        name: "Purchase Invoice",
        module: "Buying",
        appId: HubManifest.appID,
        isChildTable: false,
        isSubmittable: true,
        fields: purchaseParentFields(includeOutstanding: true) + [
            FieldDefinition(key: "tax_code", label: "Default Tax Code",
                            type: .link, required: false, linkedDocType: "TaxCode"),
            FieldDefinition(key: "net_total", label: "Net Total",
                            type: .currency, required: false),
            FieldDefinition(key: "taxes", label: "Taxes",
                            type: .table, required: false, childDocType: "TaxCharge"),
            FieldDefinition(key: "total_taxes", label: "Total Taxes",
                            type: .currency, required: false),
            FieldDefinition(key: "credit_to", label: "Credit To (Payable)",
                            type: .link, required: true,
                            helpText: "The account the amount you owe the supplier is recorded against. Defaults to your Creditors account.",
                            linkedDocType: "Account"),
            FieldDefinition(key: "expense_account", label: "Expense Account",
                            type: .link, required: true,
                            helpText: "The account this purchase is charged to. Defaults to your COGS / expense account.",
                            linkedDocType: "Account"),
            FieldDefinition(key: "cost_center", label: "Cost Center",
                            type: .link, required: false,
                            helpText: "Optional. Tags this purchase to a department or branch for reporting.",
                            linkedDocType: "CostCenter"),
            // Lineage back to the Purchase Order this invoice bills (drives the
            // billing rollup, the duplicate-conversion guard, and the cancel
            // cascade) and the Receipt it bills (receive-then-bill).
            FieldDefinition(key: "purchase_order", label: "Purchase Order",
                            type: .link, required: false, linkedDocType: "PurchaseOrder"),
            FieldDefinition(key: "purchase_receipt", label: "Purchase Receipt",
                            type: .link, required: false, linkedDocType: "PurchaseReceipt"),
            FieldDefinition(key: "is_return", label: "Is Return (Debit Note)",
                            type: .boolean, required: false, defaultValue: .bool(false)),
            FieldDefinition(key: "return_against", label: "Return Against",
                            type: .link, required: false, linkedDocType: "PurchaseInvoice")
        ],
        permissions: [systemManagerPermission],
        workflowId: "wf-purchase-invoice",
        autoname: "naming_series:PINV-.YYYY.-.####",
        syncPolicy: submittableSyncPolicy,
        indexes: [],
        searchFields: ["supplier"],
        titleField: "supplier",
        formLayout: FormLayout(sections: [
            FormLayoutSection(
                key: "header",
                title: "Header",
                columns: 2,
                fieldKeys: ["supplier", "transaction_date", "currency", "price_list", "tax_code"]
            ),
            FormLayoutSection(
                key: "items",
                title: "Items",
                fieldKeys: ["items"]
            ),
            FormLayoutSection(
                key: "taxes",
                title: "Taxes",
                helpText: "Tax rows are calculated from item / supplier tax codes on save.",
                fieldKeys: ["taxes"]
            ),
            FormLayoutSection(
                key: "totals",
                title: "Totals",
                columns: 2,
                fieldKeys: ["total_qty", "net_total", "total_taxes", "grand_total"]
            ),
            FormLayoutSection(
                key: "billing",
                title: "Billing",
                columns: 2,
                fieldKeys: ["due_date", "outstanding_amount"]
            ),
            FormLayoutSection(
                key: "posting",
                title: "Posting",
                helpText: "Accounts used when GL entries are derived on submit.",
                columns: 2,
                fieldKeys: ["credit_to", "expense_account", "cost_center"]
            ),
            FormLayoutSection(
                key: "notes",
                title: "Notes",
                fieldKeys: ["notes"]
            )
        ])
    )

    // MARK: - Purchase Receipt (Phase 4 — fulfilment)

    /// One received line on a Purchase Receipt. `warehouse` is where the
    /// goods land; `rate` is the receipt cost used as the stock valuation.
    static let purchaseReceiptItem = DocType(
        id: "PurchaseReceiptItem",
        name: "Purchase Receipt Item",
        module: "Buying",
        appId: HubManifest.appID,
        isChildTable: true,
        fields: [
            FieldDefinition(key: "item", label: "Item",
                            type: .link, required: true, linkedDocType: "Item"),
            FieldDefinition(key: "description", label: "Description",
                            type: .text, required: false,
                            fetchFrom: "item.description"),
            FieldDefinition(key: "qty", label: "Received Qty",
                            type: .decimal, required: true, defaultValue: .double(1)),
            FieldDefinition(key: "uom", label: "UOM",
                            type: .link, required: false, linkedDocType: "UOM"),
            FieldDefinition(key: "rate", label: "Rate",
                            type: .currency, required: false, defaultValue: .double(0)),
            FieldDefinition(key: "amount", label: "Amount",
                            type: .currency, required: false,
                            formulaExpression: "qty * rate"),
            FieldDefinition(key: "warehouse", label: "Warehouse",
                            type: .link, required: false, linkedDocType: "Warehouse"),
            FieldDefinition(key: "purchase_order", label: "Purchase Order",
                            type: .link, required: false, linkedDocType: "PurchaseOrder")
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: [],
        titleField: "item"
    )

    /// Purchase Receipt — the physical goods-in document. Separate from the
    /// Purchase Invoice (financial). On submit it increments stock on each
    /// line warehouse via the Stock Ledger; cancel reverses it. Links back
    /// to the originating Purchase Order where practical.
    static let purchaseReceipt = DocType(
        id: "PurchaseReceipt",
        name: "Purchase Receipt",
        module: "Buying",
        appId: HubManifest.appID,
        isChildTable: false,
        isSubmittable: true,
        fields: [
            FieldDefinition(key: "supplier", label: "Supplier",
                            type: .link, required: true, linkedDocType: "Supplier"),
            FieldDefinition(key: "transaction_date", label: "Receipt Date",
                            type: .date, required: true),
            FieldDefinition(key: "purchase_order", label: "Purchase Order",
                            type: .link, required: false, linkedDocType: "PurchaseOrder"),
            FieldDefinition(key: "currency", label: "Currency",
                            type: .link, required: false, linkedDocType: "Currency"),
            FieldDefinition(key: "set_warehouse", label: "Default Warehouse",
                            type: .link, required: false, linkedDocType: "Warehouse"),
            FieldDefinition(key: "is_return", label: "Is Return (Goods Out)",
                            type: .boolean, required: false, defaultValue: .bool(false)),
            FieldDefinition(key: "return_against", label: "Return Against",
                            type: .link, required: false, linkedDocType: "PurchaseReceipt"),
            FieldDefinition(key: "items", label: "Items",
                            type: .table, required: true, childDocType: "PurchaseReceiptItem"),
            FieldDefinition(key: "total_qty", label: "Total Qty",
                            type: .decimal, required: false,
                            readOnlyExpression: "true"),
            FieldDefinition(key: "remarks", label: "Remarks",
                            type: .longText, required: false, allowOnSubmit: true)
        ],
        permissions: [systemManagerPermission],
        workflowId: "wf-purchase-receipt",
        autoname: "naming_series:PREC-.YYYY.-.####",
        syncPolicy: submittableSyncPolicy,
        indexes: [],
        searchFields: ["supplier"],
        titleField: "supplier",
        formLayout: FormLayout(sections: [
            FormLayoutSection(
                key: "header",
                title: "Header",
                columns: 2,
                fieldKeys: ["supplier", "transaction_date", "purchase_order", "currency", "set_warehouse"]
            ),
            FormLayoutSection(
                key: "items",
                title: "Received Items",
                helpText: "Submitting increases stock at each line's warehouse.",
                fieldKeys: ["items"]
            ),
            FormLayoutSection(
                key: "totals",
                title: "Totals",
                fieldKeys: ["total_qty"]
            ),
            FormLayoutSection(
                key: "notes",
                title: "Notes",
                fieldKeys: ["remarks"]
            )
        ])
    )

    static let allDocTypes: [DocType] = [
        // Child DocTypes first
        purchaseItem, purchaseReceiptItem,
        // Parents
        supplier, supplierQuotation, purchaseOrder, purchaseInvoice,
        purchaseReceipt
    ]
}
