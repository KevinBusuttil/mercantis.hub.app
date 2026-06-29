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

enum Selling {

    // MARK: - Child DocTypes

    /// One row inside Item.uoms — an alternative unit of measure plus its
    /// conversion factor relative to the item's `stock_uom`. (Wall 5)
    static let uomConversion = DocType(
        id: "UOMConversionDetail",
        name: "UOM Conversion",
        module: "Selling",
        appId: HubManifest.appID,
        isChildTable: true,
        fields: [
            FieldDefinition(key: "uom", label: "UOM",
                            type: .link, required: true, linkedDocType: "UOM"),
            FieldDefinition(key: "conversion_factor", label: "Conversion Factor",
                            type: .decimal, required: true, defaultValue: .double(1))
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: [],
        titleField: "uom"
    )

    /// One row inside Item.suppliers — per-supplier sourcing detail
    /// (alternative part number, lead time). (Wall 5)
    static let itemSupplier = DocType(
        id: "ItemSupplier",
        name: "Item Supplier",
        module: "Selling",
        appId: HubManifest.appID,
        isChildTable: true,
        fields: [
            FieldDefinition(key: "supplier", label: "Supplier",
                            type: .link, required: true, linkedDocType: "Supplier"),
            FieldDefinition(key: "supplier_part_no", label: "Supplier Part No",
                            type: .text, required: false),
            FieldDefinition(key: "lead_time_days", label: "Lead Time (days)",
                            type: .number, required: false)
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: [],
        titleField: "supplier"
    )

    /// One row inside a sales-side line-item table (Quotation, Sales Order,
    /// Sales Invoice). Wall 5 unlocks the structure; Wall 6 adds workflow
    /// gating on the parent. (Wall 5)
    static let salesItem = DocType(
        id: "SalesItem",
        name: "Sales Item",
        module: "Selling",
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
                            type: .currency, required: true,
                            helpText: "Price per unit before tax.",
                            defaultValue: .double(0)),
            FieldDefinition(key: "amount", label: "Amount",
                            type: .currency, required: false,
                            formulaExpression: "qty * rate"),
            FieldDefinition(key: "tax_code", label: "Tax Code",
                            type: .link, required: false,
                            helpText: "Optional. The VAT / sales-tax rate applied to this line.",
                            linkedDocType: "TaxCode"),
            FieldDefinition(key: "warehouse", label: "Source Warehouse",
                            type: .link, required: false,
                            helpText: "Where this item ships from. Defaults to your main store.",
                            linkedDocType: "Warehouse"),
            FieldDefinition(key: "delivery_date", label: "Delivery Date",
                            type: .date, required: false)
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: [],
        titleField: "item"
    )

    // MARK: - Parent DocTypes

    /// Item is the canonical sellable / stockable thing. Wall 4 unlocked
    /// the link fields; Wall 5 unlocks the UOM-conversion and supplier
    /// child tables.
    static let item = DocType(
        id: "Item",
        name: "Item",
        module: "Selling",
        appId: HubManifest.appID,
        isChildTable: false,
        fields: [
            FieldDefinition(key: "item_code", label: "Item Code",
                            type: .text, required: true,
                            helpText: "Your internal reference for this item. Must be unique.",
                            placeholder: "e.g. WIDGET-001",
                            isSearchable: true),
            FieldDefinition(key: "item_name", label: "Item Name",
                            type: .text, required: true,
                            placeholder: "e.g. Stainless Steel Widget",
                            isSearchable: true),
            FieldDefinition(key: "item_group", label: "Item Group",
                            type: .link, required: true, linkedDocType: "ItemGroup"),
            FieldDefinition(key: "brand", label: "Brand",
                            type: .link, required: false, linkedDocType: "Brand"),
            FieldDefinition(key: "stock_uom", label: "Default UOM",
                            type: .link, required: true, linkedDocType: "UOM"),
            FieldDefinition(key: "default_warehouse", label: "Default Warehouse",
                            type: .link, required: false, linkedDocType: "Warehouse"),
            FieldDefinition(key: "is_stock_item", label: "Track Stock",
                            type: .boolean, required: false,
                            helpText: "Turn off for services and other items you don't keep in inventory.",
                            defaultValue: .bool(true)),
            FieldDefinition(key: "valuation_method", label: "Valuation Method",
                            type: .select, required: false,
                            helpText: "How stock cost is worked out when you sell. Moving Average suits most businesses.",
                            defaultValue: .string("Moving Average"),
                            options: ["Moving Average", "FIFO"]),
            FieldDefinition(key: "is_sales_item", label: "Sales Item",
                            type: .boolean, required: false, defaultValue: .bool(true)),
            FieldDefinition(key: "is_purchase_item", label: "Purchase Item",
                            type: .boolean, required: false, defaultValue: .bool(true)),
            FieldDefinition(key: "standard_rate", label: "Standard Selling Rate",
                            type: .currency, required: false,
                            helpText: "Default selling price, used to pre-fill the rate on new sales lines."),
            FieldDefinition(key: "tax_code", label: "Default Tax Code",
                            type: .link, required: false,
                            helpText: "The VAT / sales-tax rate that applies to this item by default.",
                            linkedDocType: "TaxCode"),
            FieldDefinition(key: "uoms", label: "UOM Conversions",
                            type: .table, required: false, childDocType: "UOMConversionDetail"),
            FieldDefinition(key: "suppliers", label: "Suppliers",
                            type: .table, required: false, childDocType: "ItemSupplier"),
            FieldDefinition(key: "barcode", label: "Barcode",
                            type: .barcode, required: false, isSearchable: true),
            FieldDefinition(key: "image", label: "Item Image",
                            type: .image, required: false),
            FieldDefinition(key: "description", label: "Description",
                            type: .longText, required: false)
        ],
        permissions: [systemManagerPermission],
        autoname: "naming_series:ITEM-.####",
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["item_code", "item_name", "barcode"],
        titleField: "item_name",
        formLayout: FormLayout(sections: [
            FormLayoutSection(
                key: "identity",
                title: "Item",
                columns: 2,
                fieldKeys: ["item_code", "item_name", "item_group", "brand"]
            ),
            FormLayoutSection(
                key: "stock",
                title: "Stock",
                helpText: "How this item is measured and where it normally lives.",
                columns: 2,
                fieldKeys: ["stock_uom", "default_warehouse", "is_stock_item"]
            ),
            FormLayoutSection(
                key: "transactions",
                title: "Transactions",
                helpText: "Which kinds of transactions this item participates in.",
                columns: 2,
                fieldKeys: ["is_sales_item", "is_purchase_item", "standard_rate", "tax_code"]
            ),
            FormLayoutSection(
                key: "uoms",
                title: "UOMs",
                helpText: "Alternative units of measure and their conversion factors.",
                fieldKeys: ["uoms"]
            ),
            FormLayoutSection(
                key: "sourcing",
                title: "Sourcing",
                helpText: "Suppliers that stock this item.",
                fieldKeys: ["suppliers"]
            ),
            FormLayoutSection(
                key: "media",
                title: "Media",
                columns: 2,
                fieldKeys: ["barcode", "image", "description"]
            )
        ])
    )

    private static let salesParentLayout: [FormLayoutSection] = [
        FormLayoutSection(
            key: "header",
            title: "Header",
            columns: 2,
            fieldKeys: ["customer", "transaction_date", "currency", "price_list"]
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

    /// Submittable transactional DocTypes need the version-checked /
    /// immutable-after-submit policy.
    private static let submittableSyncPolicy = SyncPolicy(
        conflictResolution: .versionChecked,
        immutableAfterSubmit: true
    )

    private static func salesParentFields(
        includeDelivery: Bool,
        includeOutstanding: Bool = false
    ) -> [FieldDefinition] {
        var fields: [FieldDefinition] = [
            FieldDefinition(key: "customer", label: "Customer",
                            type: .link, required: true, linkedDocType: "Customer"),
            FieldDefinition(key: "transaction_date", label: "Date",
                            type: .date, required: true),
            FieldDefinition(key: "currency", label: "Currency",
                            type: .link, required: true, linkedDocType: "Currency"),
            FieldDefinition(key: "conversion_rate", label: "Exchange Rate to Base",
                            type: .decimal, required: false,
                            helpText: "Only matters when the currency differs from your base currency. Leave at 1 otherwise.",
                            defaultValue: .double(1)),
            FieldDefinition(key: "price_list", label: "Price List",
                            type: .link, required: false,
                            helpText: "Optional. Pick a price list to auto-fill item rates; leave blank to type rates in by hand.",
                            linkedDocType: "PriceList"),
        ]
        if includeDelivery {
            fields.append(FieldDefinition(key: "delivery_date", label: "Required Delivery Date",
                                          type: .date, required: false,
                                          allowOnSubmit: true))
        }
        fields.append(contentsOf: [
            FieldDefinition(key: "items", label: "Items",
                            type: .table, required: true, childDocType: "SalesItem"),
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
        ])
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

    /// Quotation — pre-sale offer to a Customer / Lead. Wall 6 makes it
    /// submittable with the `wf-quotation` workflow (Draft → Submitted →
    /// Ordered / Lost / Cancelled).
    static let quotation = DocType(
        id: "Quotation",
        name: "Quotation",
        module: "Selling",
        appId: HubManifest.appID,
        isChildTable: false,
        isSubmittable: true,
        fields: salesParentFields(includeDelivery: true),
        permissions: [systemManagerPermission],
        workflowId: "wf-quotation",
        autoname: "naming_series:SQTN-.YYYY.-.####",
        syncPolicy: submittableSyncPolicy,
        indexes: [],
        searchFields: ["customer"],
        titleField: "customer",
        formLayout: FormLayout(sections: salesParentLayout)
    )

    /// Fulfilment progress, written back by `SalesOrderFulfilmentService` as
    /// Deliveries and Invoices are submitted against the order. `allowOnSubmit`
    /// so the post-commit service can update them on the already-submitted
    /// order; read-only in the form (they're derived totals, never typed in).
    private static let salesOrderFulfilmentFields: [FieldDefinition] = [
        FieldDefinition(key: "delivery_status", label: "Delivery Status",
                        type: .select, required: false,
                        helpText: "How much of this order has been delivered. Updated automatically as Deliveries are submitted.",
                        defaultValue: .string("To Deliver"),
                        options: ["To Deliver", "Partially Delivered", "Fully Delivered"],
                        readOnlyExpression: "true", allowOnSubmit: true),
        FieldDefinition(key: "delivered_qty", label: "Delivered Qty",
                        type: .decimal, required: false,
                        readOnlyExpression: "true", allowOnSubmit: true),
        FieldDefinition(key: "per_delivered", label: "% Delivered",
                        type: .decimal, required: false,
                        readOnlyExpression: "true", allowOnSubmit: true),
        FieldDefinition(key: "billing_status", label: "Billing Status",
                        type: .select, required: false,
                        helpText: "How much of this order has been invoiced. Updated automatically as Sales Invoices are submitted.",
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

    /// Sales Order layout = the shared sales layout plus a Fulfilment section
    /// (delivery / billing progress), inserted before the Notes block.
    private static let salesOrderLayout: [FormLayoutSection] = [
        FormLayoutSection(
            key: "header",
            title: "Header",
            columns: 2,
            fieldKeys: ["customer", "transaction_date", "currency", "price_list"]
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
            helpText: "Delivery and billing progress, updated automatically as Deliveries and Invoices are submitted against this order.",
            columns: 2,
            fieldKeys: ["delivery_status", "per_delivered", "billing_status", "per_billed"]
        ),
        FormLayoutSection(
            key: "notes",
            title: "Notes",
            fieldKeys: ["notes"]
        )
    ]

    /// Sales Order — confirmed sale, awaiting delivery. Wall 6 makes it
    /// submittable with the `wf-sales-order` workflow.
    static let salesOrder = DocType(
        id: "SalesOrder",
        name: "Sales Order",
        module: "Selling",
        appId: HubManifest.appID,
        isChildTable: false,
        isSubmittable: true,
        fields: salesParentFields(includeDelivery: true) + [
            // Lineage back to the Quotation this order was converted from
            // (mirrors `sales_order` on Delivery / Invoice). Drives the
            // duplicate-conversion guard and the cancel cascade.
            FieldDefinition(key: "quotation", label: "Quotation",
                            type: .link, required: false, linkedDocType: "Quotation")
        ] + salesOrderFulfilmentFields,
        permissions: [systemManagerPermission],
        workflowId: "wf-sales-order",
        autoname: "naming_series:SO-.YYYY.-.####",
        syncPolicy: submittableSyncPolicy,
        indexes: [],
        searchFields: ["customer"],
        titleField: "customer",
        formLayout: FormLayout(sections: salesOrderLayout)
    )

    /// Sales Invoice — billable line items, accounts-receivable trigger.
    /// Wall 6 makes it submittable with the `wf-sales-invoice` workflow
    /// (Draft → Submitted → Paid / Overdue / Cancelled). Wall 7
    /// auto-derives GL entries from `debit_to` (Dr) and `income_account`
    /// (Cr) on submit.
    static let salesInvoice = DocType(
        id: "SalesInvoice",
        name: "Sales Invoice",
        module: "Selling",
        appId: HubManifest.appID,
        isChildTable: false,
        isSubmittable: true,
        fields: salesParentFields(includeDelivery: false, includeOutstanding: true) + [
            FieldDefinition(key: "tax_code", label: "Default Tax Code",
                            type: .link, required: false, linkedDocType: "TaxCode"),
            FieldDefinition(key: "net_total", label: "Net Total",
                            type: .currency, required: false),
            FieldDefinition(key: "taxes", label: "Taxes",
                            type: .table, required: false, childDocType: "TaxCharge"),
            FieldDefinition(key: "total_taxes", label: "Total Taxes",
                            type: .currency, required: false),
            FieldDefinition(key: "debit_to", label: "Debit To (Receivable)",
                            type: .link, required: true,
                            helpText: "The account the customer's unpaid balance is recorded against. Defaults to your Debtors account.",
                            linkedDocType: "Account"),
            FieldDefinition(key: "income_account", label: "Income Account",
                            type: .link, required: true,
                            helpText: "The revenue account this sale is credited to. Defaults to your Sales account.",
                            linkedDocType: "Account"),
            FieldDefinition(key: "cost_center", label: "Cost Center",
                            type: .link, required: false,
                            helpText: "Optional. Tags this sale to a department or branch for reporting.",
                            linkedDocType: "CostCenter"),
            FieldDefinition(key: "sales_order", label: "Sales Order",
                            type: .link, required: false, linkedDocType: "SalesOrder"),
            // Lineage back to the Delivery this invoice bills (deliver-then-
            // invoice). Drives the duplicate-conversion guard and the
            // Delivery → Invoice cancel cascade.
            FieldDefinition(key: "sales_delivery", label: "Sales Delivery",
                            type: .link, required: false, linkedDocType: "SalesDelivery"),
            FieldDefinition(key: "is_return", label: "Is Return (Credit Note)",
                            type: .boolean, required: false, defaultValue: .bool(false)),
            FieldDefinition(key: "return_against", label: "Return Against",
                            type: .link, required: false, linkedDocType: "SalesInvoice")
        ],
        permissions: [systemManagerPermission],
        workflowId: "wf-sales-invoice",
        autoname: "naming_series:SINV-.YYYY.-.####",
        syncPolicy: submittableSyncPolicy,
        indexes: [],
        searchFields: ["customer"],
        titleField: "customer",
        formLayout: FormLayout(sections: [
            FormLayoutSection(
                key: "header",
                title: "Header",
                columns: 2,
                fieldKeys: ["customer", "transaction_date", "currency", "price_list", "tax_code"]
            ),
            FormLayoutSection(
                key: "items",
                title: "Items",
                fieldKeys: ["items"]
            ),
            FormLayoutSection(
                key: "taxes",
                title: "Taxes",
                helpText: "Tax rows are calculated from item / customer tax codes on save.",
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
                fieldKeys: ["debit_to", "income_account", "cost_center"]
            ),
            FormLayoutSection(
                key: "notes",
                title: "Notes",
                fieldKeys: ["notes"]
            )
        ])
    )

    static let allDocTypes: [DocType] = [
        // Child DocTypes first
        uomConversion, itemSupplier, salesItem,
        // Parents
        item, quotation, salesOrder, salesInvoice
    ]
}
