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
                            type: .text, required: false),
            FieldDefinition(key: "qty", label: "Quantity",
                            type: .decimal, required: true, defaultValue: .double(1)),
            FieldDefinition(key: "uom", label: "UOM",
                            type: .link, required: false, linkedDocType: "UOM"),
            FieldDefinition(key: "rate", label: "Rate",
                            type: .currency, required: true, defaultValue: .double(0)),
            FieldDefinition(key: "amount", label: "Amount",
                            type: .currency, required: false,
                            formulaExpression: "qty * rate"),
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
                fieldKeys: ["supplier_name", "supplier_type", "supplier_group", "country"]
            ),
            FormLayoutSection(
                key: "reach",
                title: "Reach",
                fieldKeys: ["email_id", "mobile_no", "phone"]
            ),
            FormLayoutSection(
                key: "defaults",
                title: "Defaults",
                helpText: "Used when raising new purchase transactions for this supplier.",
                fieldKeys: ["default_currency", "default_price_list", "default_cost_center"]
            ),
            FormLayoutSection(
                key: "financial",
                title: "Financial",
                fieldKeys: ["tax_id", "payment_terms"]
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
            fieldKeys: ["total_qty", "grand_total"]
        ),
        FormLayoutSection(
            key: "notes",
            title: "Notes",
            fieldKeys: ["notes"]
        )
    ]

    private static let purchaseParentFields: [FieldDefinition] = [
        FieldDefinition(key: "supplier", label: "Supplier",
                        type: .link, required: true, linkedDocType: "Supplier"),
        FieldDefinition(key: "transaction_date", label: "Date",
                        type: .date, required: true),
        FieldDefinition(key: "currency", label: "Currency",
                        type: .link, required: true, linkedDocType: "Currency"),
        FieldDefinition(key: "price_list", label: "Price List",
                        type: .link, required: false, linkedDocType: "PriceList"),
        FieldDefinition(key: "items", label: "Items",
                        type: .table, required: true, childDocType: "PurchaseItem"),
        FieldDefinition(key: "total_qty", label: "Total Qty",
                        type: .decimal, required: false),
        FieldDefinition(key: "grand_total", label: "Grand Total",
                        type: .currency, required: false),
        FieldDefinition(key: "notes", label: "Notes",
                        type: .longText, required: false)
    ]

    /// Supplier Quotation — pre-purchase RFQ response.
    static let supplierQuotation = DocType(
        id: "SupplierQuotation",
        name: "Supplier Quotation",
        module: "Buying",
        appId: HubManifest.appID,
        isChildTable: false,
        fields: purchaseParentFields,
        permissions: [systemManagerPermission],
        autoname: "naming_series:SQTN-PURC-.YYYY.-.####",
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["supplier"],
        titleField: "supplier",
        formLayout: FormLayout(sections: purchaseParentLayout)
    )

    /// Purchase Order — confirmed purchase, awaiting receipt.
    static let purchaseOrder = DocType(
        id: "PurchaseOrder",
        name: "Purchase Order",
        module: "Buying",
        appId: HubManifest.appID,
        isChildTable: false,
        fields: purchaseParentFields,
        permissions: [systemManagerPermission],
        autoname: "naming_series:PO-.YYYY.-.####",
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["supplier"],
        titleField: "supplier",
        formLayout: FormLayout(sections: purchaseParentLayout)
    )

    /// Purchase Invoice — billable line items, accounts-payable trigger.
    /// GL-entry derivation waits on Wall 7.
    static let purchaseInvoice = DocType(
        id: "PurchaseInvoice",
        name: "Purchase Invoice",
        module: "Buying",
        appId: HubManifest.appID,
        isChildTable: false,
        fields: purchaseParentFields + [
            FieldDefinition(key: "due_date", label: "Due Date",
                            type: .date, required: false),
            FieldDefinition(key: "outstanding_amount", label: "Outstanding",
                            type: .currency, required: false)
        ],
        permissions: [systemManagerPermission],
        autoname: "naming_series:PINV-.YYYY.-.####",
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["supplier"],
        titleField: "supplier",
        formLayout: FormLayout(sections: purchaseParentLayout + [
            FormLayoutSection(
                key: "billing",
                title: "Billing",
                fieldKeys: ["due_date", "outstanding_amount"]
            )
        ])
    )

    static let allDocTypes: [DocType] = [
        // Child DocTypes first
        purchaseItem,
        // Parents
        supplier, supplierQuotation, purchaseOrder, purchaseInvoice
    ]
}
