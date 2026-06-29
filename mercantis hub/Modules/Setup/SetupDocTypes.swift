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

enum Setup {

    static let company = DocType(
        id: "Company",
        name: "Company",
        module: "Setup",
        appId: HubManifest.appID,
        isChildTable: false,
        fields: [
            FieldDefinition(key: "business_name", label: "Business Name",
                            type: .text, required: true, isSearchable: true),
            FieldDefinition(key: "vat_tax_number", label: "VAT / Tax Number",
                            type: .text, required: false),
            FieldDefinition(key: "registration_number", label: "Registration Number",
                            type: .text, required: false),
            FieldDefinition(key: "country", label: "Country",
                            type: .select, required: false,
                            helpText: "The country your business is set up in. Chosen during setup; drives your chart of accounts and tax codes.",
                            options: [""] + HubJurisdictionLibrary.all.map(\.name)),
            FieldDefinition(key: "tax_regime", label: "Tax Regime",
                            type: .select, required: false,
                            helpText: "VAT, Sales Tax, or GST/HST — set from your country.",
                            options: [""] + HubJurisdictionLibrary.taxRegimeLabels),
            FieldDefinition(key: "tax_registered", label: "Tax Registered",
                            type: .boolean, required: false,
                            helpText: "Whether the business is registered to charge VAT / GST / sales tax.",
                            defaultValue: .bool(false)),
            FieldDefinition(key: "accounting_basis", label: "Accounting Basis",
                            type: .select, required: false,
                            helpText: "Accrual records income/cost when invoiced; Cash records them when money moves.",
                            defaultValue: .string("Accrual"),
                            options: ["Accrual", "Cash"]),
            FieldDefinition(key: "business_type", label: "Business Type",
                            type: .select, required: false,
                            helpText: "What kind of business this is, chosen during setup. Tailors your workspace and the default income account new invoices use.",
                            options: [""] + HubPreset.allCases.map(\.title)),
            FieldDefinition(key: "address", label: "Address",
                            type: .longText, required: false),
            FieldDefinition(key: "email", label: "Email",
                            type: .email, required: false, isSearchable: true),
            FieldDefinition(key: "phone", label: "Phone",
                            type: .phone, required: false),
            FieldDefinition(key: "logo", label: "Logo",
                            type: .image, required: false),
            FieldDefinition(key: "default_currency", label: "Default Currency",
                            type: .link, required: false, linkedDocType: "Currency"),
            FieldDefinition(key: "default_warehouse", label: "Default Warehouse",
                            type: .link, required: false, linkedDocType: "Warehouse"),
            FieldDefinition(key: "allow_negative_stock", label: "Allow Negative Stock",
                            type: .boolean, required: false, defaultValue: .bool(false)),
            FieldDefinition(key: "allow_over_delivery", label: "Allow Over-Delivery",
                            type: .boolean, required: false,
                            helpText: "When off, a Sales Delivery can't ship more of an item than its Sales Order ordered.",
                            defaultValue: .bool(false)),
            FieldDefinition(key: "allow_over_receipt", label: "Allow Over-Receipt",
                            type: .boolean, required: false,
                            helpText: "When off, a Purchase Receipt can't receive more of an item than its Purchase Order ordered.",
                            defaultValue: .bool(false)),
            FieldDefinition(key: "default_receivable_account", label: "Default Receivable Account",
                            type: .link, required: false, linkedDocType: "Account"),
            FieldDefinition(key: "default_payable_account", label: "Default Payable Account",
                            type: .link, required: false, linkedDocType: "Account"),
            FieldDefinition(key: "default_income_account", label: "Default Income Account",
                            type: .link, required: false, linkedDocType: "Account"),
            FieldDefinition(key: "default_expense_account", label: "Default Expense Account",
                            type: .link, required: false, linkedDocType: "Account"),
            FieldDefinition(key: "default_cash_bank_account", label: "Default Cash / Bank Account",
                            type: .link, required: false, linkedDocType: "Account"),
            FieldDefinition(key: "default_stock_account", label: "Default Stock Account",
                            type: .link, required: false, linkedDocType: "Account"),
            FieldDefinition(key: "default_grni_account", label: "Default GRNI Account",
                            type: .link, required: false, linkedDocType: "Account"),
            FieldDefinition(key: "default_vat_account", label: "Default VAT Account",
                            type: .link, required: false, linkedDocType: "Account"),
            FieldDefinition(key: "default_tax_code", label: "Default Tax Code",
                            type: .link, required: false,
                            helpText: "The tax automatically applied to new invoices. Set from your country during setup.",
                            linkedDocType: "TaxCode"),
            FieldDefinition(key: "books_lock_date", label: "Books Locked Through",
                            type: .date, required: false,
                            helpText: "Postings dated on or before this date are blocked. Set automatically when you file a tax return or finalise a period, so filed figures can't change by accident.")
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["business_name", "registration_number", "vat_tax_number", "email"],
        titleField: "business_name",
        formLayout: FormLayout(sections: [
            FormLayoutSection(
                key: "identity",
                title: "Business Identity",
                helpText: "Set up your legal identity and primary contact details.",
                columns: 2,
                fieldKeys: ["business_name", "registration_number", "vat_tax_number"]
            ),
            FormLayoutSection(
                key: "jurisdiction",
                title: "Tax & Jurisdiction",
                helpText: "Chosen during setup. These drive your chart of accounts, tax codes, and the tax applied to new invoices.",
                columns: 2,
                fieldKeys: ["country", "tax_regime", "tax_registered", "accounting_basis", "business_type"]
            ),
            FormLayoutSection(
                key: "contact",
                title: "Contact",
                columns: 2,
                fieldKeys: ["email", "phone", "logo"]
            ),
            FormLayoutSection(
                key: "address",
                title: "Address",
                fieldKeys: ["address"]
            ),
            FormLayoutSection(
                key: "defaults",
                title: "Defaults",
                helpText: "Used as defaults for future sales, buying, stock, and accounting setup.",
                columns: 2,
                fieldKeys: ["default_currency", "default_warehouse", "allow_negative_stock", "allow_over_delivery", "books_lock_date"]
            ),
            FormLayoutSection(
                key: "accounts",
                title: "Default Accounts",
                columns: 2,
                fieldKeys: ["default_receivable_account", "default_payable_account",
                            "default_income_account", "default_expense_account",
                            "default_cash_bank_account", "default_stock_account",
                            "default_grni_account", "default_vat_account",
                            "default_tax_code"]
            )
        ])
    )

    // MARK: - Tree masters

    static let customerGroup = DocType(
        id: "CustomerGroup",
        name: "Customer Group",
        module: "Setup",
        appId: HubManifest.appID,
        isChildTable: false,
        isTree: true,
        treeRootName: "All Customer Groups",
        fields: [
            FieldDefinition(key: "customer_group_name", label: "Customer Group Name",
                            type: .text, required: true, isSearchable: true),
            FieldDefinition(key: "parent_customer_group", label: "Parent Customer Group",
                            type: .link, required: false, linkedDocType: "CustomerGroup")
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["customer_group_name"],
        titleField: "customer_group_name"
    )

    static let territory = DocType(
        id: "Territory",
        name: "Territory",
        module: "Setup",
        appId: HubManifest.appID,
        isChildTable: false,
        isTree: true,
        treeRootName: "All Territories",
        fields: [
            FieldDefinition(key: "territory_name", label: "Territory Name",
                            type: .text, required: true, isSearchable: true),
            FieldDefinition(key: "parent_territory", label: "Parent Territory",
                            type: .link, required: false, linkedDocType: "Territory")
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["territory_name"],
        titleField: "territory_name"
    )

    static let itemGroup = DocType(
        id: "ItemGroup",
        name: "Item Group",
        module: "Setup",
        appId: HubManifest.appID,
        isChildTable: false,
        isTree: true,
        treeRootName: "All Item Groups",
        fields: [
            FieldDefinition(key: "item_group_name", label: "Item Group Name",
                            type: .text, required: true, isSearchable: true),
            FieldDefinition(key: "parent_item_group", label: "Parent Item Group",
                            type: .link, required: false, linkedDocType: "ItemGroup")
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["item_group_name"],
        titleField: "item_group_name"
    )

    static let supplierGroup = DocType(
        id: "SupplierGroup",
        name: "Supplier Group",
        module: "Setup",
        appId: HubManifest.appID,
        isChildTable: false,
        isTree: true,
        treeRootName: "All Supplier Groups",
        fields: [
            FieldDefinition(key: "supplier_group_name", label: "Supplier Group Name",
                            type: .text, required: true, isSearchable: true),
            FieldDefinition(key: "parent_supplier_group", label: "Parent Supplier Group",
                            type: .link, required: false, linkedDocType: "SupplierGroup")
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["supplier_group_name"],
        titleField: "supplier_group_name"
    )

    static let warehouse = DocType(
        id: "Warehouse",
        name: "Warehouse",
        module: "Setup",
        appId: HubManifest.appID,
        isChildTable: false,
        isTree: true,
        treeRootName: "All Warehouses",
        fields: [
            FieldDefinition(key: "warehouse_name", label: "Warehouse Name",
                            type: .text, required: true, isSearchable: true),
            FieldDefinition(key: "parent_warehouse", label: "Parent Warehouse",
                            type: .link, required: false, linkedDocType: "Warehouse"),
            FieldDefinition(key: "is_group", label: "Is Group", type: .boolean, required: false),
            FieldDefinition(key: "address_line1", label: "Address Line", type: .text, required: false),
            FieldDefinition(key: "city", label: "City", type: .text, required: false)
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["warehouse_name", "city"],
        titleField: "warehouse_name"
    )

    static let costCenter = DocType(
        id: "CostCenter",
        name: "Cost Center",
        module: "Setup",
        appId: HubManifest.appID,
        isChildTable: false,
        isTree: true,
        treeRootName: "All Cost Centers",
        fields: [
            FieldDefinition(key: "cost_center_name", label: "Cost Center Name",
                            type: .text, required: true, isSearchable: true),
            FieldDefinition(key: "parent_cost_center", label: "Parent Cost Center",
                            type: .link, required: false, linkedDocType: "CostCenter"),
            FieldDefinition(key: "is_group", label: "Is Group", type: .boolean, required: false)
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["cost_center_name"],
        titleField: "cost_center_name"
    )

    // MARK: - Flat masters

    /// Stocked currencies. ID format follows ISO 4217 ("EUR", "USD", "MTL").
    static let currency = DocType(
        id: "Currency",
        name: "Currency",
        module: "Setup",
        appId: HubManifest.appID,
        isChildTable: false,
        fields: [
            FieldDefinition(key: "currency_name", label: "Currency Name",
                            type: .text, required: true, isSearchable: true),
            FieldDefinition(key: "iso_code", label: "ISO 4217 Code",
                            type: .text, required: true, isSearchable: true),
            FieldDefinition(key: "symbol", label: "Symbol", type: .text, required: false),
            FieldDefinition(key: "smallest_unit", label: "Smallest Unit",
                            type: .decimal, required: false, defaultValue: .double(0.01)),
            FieldDefinition(key: "enabled", label: "Enabled",
                            type: .boolean, required: false, defaultValue: .bool(true))
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["currency_name", "iso_code"],
        titleField: "currency_name"
    )

    /// Unit of measure (UOM). Used by Item and stock-movement DocTypes.
    static let uom = DocType(
        id: "UOM",
        name: "UOM",
        module: "Setup",
        appId: HubManifest.appID,
        isChildTable: false,
        fields: [
            FieldDefinition(key: "uom_name", label: "UOM Name",
                            type: .text, required: true, isSearchable: true),
            FieldDefinition(key: "must_be_whole_number", label: "Must Be Whole Number",
                            type: .boolean, required: false, defaultValue: .bool(false)),
            FieldDefinition(key: "enabled", label: "Enabled",
                            type: .boolean, required: false, defaultValue: .bool(true))
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["uom_name"],
        titleField: "uom_name"
    )

    /// Brand for Items.
    static let brand = DocType(
        id: "Brand",
        name: "Brand",
        module: "Setup",
        appId: HubManifest.appID,
        isChildTable: false,
        fields: [
            FieldDefinition(key: "brand_name", label: "Brand Name",
                            type: .text, required: true, isSearchable: true),
            FieldDefinition(key: "description", label: "Description",
                            type: .longText, required: false)
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["brand_name"],
        titleField: "brand_name"
    )

    // MARK: - Fiscal Year

    /// Fiscal Year defines an accounting period for reporting and period-close.
    /// A micro/small business typically has one active fiscal year at a time.
    static let fiscalYear = DocType(
        id: "FiscalYear",
        name: "Fiscal Year",
        module: "Setup",
        appId: HubManifest.appID,
        isChildTable: false,
        fields: [
            FieldDefinition(key: "year_name", label: "Year Name",
                            type: .text, required: true, isSearchable: true),
            FieldDefinition(key: "year_start_date", label: "Start Date",
                            type: .date, required: true),
            FieldDefinition(key: "year_end_date", label: "End Date",
                            type: .date, required: true),
            FieldDefinition(key: "is_active", label: "Active",
                            type: .boolean, required: false, defaultValue: .bool(true)),
            FieldDefinition(key: "is_closed", label: "Closed",
                            type: .boolean, required: false, defaultValue: .bool(false)),
            FieldDefinition(key: "closed_date", label: "Closed On",
                            type: .date, required: false,
                            helpText: "When the year was closed off."),
            FieldDefinition(key: "closing_entry", label: "Closing Entry",
                            type: .link, required: false,
                            helpText: "The year-end Journal Entry that rolled profit into Retained Earnings.",
                            linkedDocType: "JournalEntry"),
            FieldDefinition(key: "retained_earnings_account", label: "Retained Earnings Account",
                            type: .link, required: false,
                            helpText: "Where this year's net profit or loss is carried forward.",
                            linkedDocType: "Account")
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["year_name"],
        titleField: "year_name",
        formLayout: FormLayout(sections: [
            FormLayoutSection(
                key: "period",
                title: "Accounting Period",
                helpText: "Define the start and end dates for this fiscal year. Keep one open year marked active.",
                columns: 2,
                fieldKeys: ["year_name", "year_start_date", "year_end_date", "is_active", "is_closed",
                            "closed_date", "closing_entry", "retained_earnings_account"]
            )
        ])
    )

    // MARK: - Numbering Settings

    /// Numbering Series stores business-facing numbering preferences for
    /// invoices, bills, deliveries, POS receipts, and payments.
    /// Current live document naming still stays in Mercantis Core via each
    /// DocType's static `autoname` pattern, so this record is storage-only
    /// until Hub/Core grows a safe runtime override bridge.
    static let numberingSeries = DocType(
        id: "NumberingSeries",
        name: "Numbering Series",
        module: "Setup",
        appId: HubManifest.appID,
        isChildTable: false,
        fields: [
            FieldDefinition(key: "sales_invoice_prefix", label: "Sales Invoice Prefix",
                            type: .text, required: false, defaultValue: .string("SINV-.YYYY.-.####")),
            FieldDefinition(key: "purchase_invoice_prefix", label: "Purchase Invoice / Bill Prefix",
                            type: .text, required: false, defaultValue: .string("PINV-.YYYY.-.####")),
            FieldDefinition(key: "delivery_prefix", label: "Delivery Prefix",
                            type: .text, required: false, defaultValue: .string("DEL-.YYYY.-.####")),
            FieldDefinition(key: "pos_receipt_prefix", label: "POS Receipt Prefix",
                            type: .text, required: false, defaultValue: .string("POS-.YYYY.-.####")),
            FieldDefinition(key: "payment_prefix", label: "Payment Prefix",
                            type: .text, required: false, defaultValue: .string("PE-.YYYY.-.####"))
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: [],
        titleField: "sales_invoice_prefix",
        formLayout: FormLayout(sections: [
            FormLayoutSection(
                key: "series",
                title: "Document Numbering",
                helpText: "Store the preferred naming pattern for each document type. Current live IDs still follow the built-in Core autoname patterns. Use .YYYY. for year and .#### for sequence.",
                columns: 2,
                fieldKeys: ["sales_invoice_prefix", "purchase_invoice_prefix",
                            "delivery_prefix", "pos_receipt_prefix", "payment_prefix"]
            )
        ])
    )

    /// Price list. Per-customer-group / per-currency pricing reference.
    /// Item-level price rows live in the `items` child table (Wall 5).
    static let priceList = DocType(
        id: "PriceList",
        name: "Price List",
        module: "Setup",
        appId: HubManifest.appID,
        isChildTable: false,
        fields: [
            FieldDefinition(key: "price_list_name", label: "Price List Name",
                            type: .text, required: true, isSearchable: true),
            FieldDefinition(key: "currency", label: "Currency",
                            type: .link, required: true, linkedDocType: "Currency"),
            FieldDefinition(key: "buying", label: "Used for Buying",
                            type: .boolean, required: false, defaultValue: .bool(false)),
            FieldDefinition(key: "selling", label: "Used for Selling",
                            type: .boolean, required: false, defaultValue: .bool(true)),
            FieldDefinition(key: "enabled", label: "Enabled",
                            type: .boolean, required: false, defaultValue: .bool(true)),
            FieldDefinition(key: "items", label: "Item Rates",
                            type: .table, required: false, childDocType: "ItemPrice")
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["price_list_name"],
        titleField: "price_list_name"
    )

    /// One row inside a PriceList.items child table — the per-item rate
    /// for the parent price list. (Wall 5)
    static let itemPrice = DocType(
        id: "ItemPrice",
        name: "Item Price",
        module: "Setup",
        appId: HubManifest.appID,
        isChildTable: true,
        fields: [
            FieldDefinition(key: "item", label: "Item",
                            type: .link, required: true, linkedDocType: "Item"),
            FieldDefinition(key: "uom", label: "UOM",
                            type: .link, required: false, linkedDocType: "UOM"),
            FieldDefinition(key: "rate", label: "Rate",
                            type: .currency, required: true),
            FieldDefinition(key: "min_qty", label: "Min Qty",
                            type: .decimal, required: false, defaultValue: .double(0)),
            FieldDefinition(key: "valid_from", label: "Valid From",
                            type: .date, required: false),
            FieldDefinition(key: "valid_upto", label: "Valid Upto",
                            type: .date, required: false)
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: [],
        titleField: "item"
    )

    static let allDocTypes: [DocType] = [
        company,
        fiscalYear,
        numberingSeries,
        // Tree masters
        customerGroup,
        territory,
        itemGroup,
        supplierGroup,
        warehouse,
        costCenter,
        // Flat masters
        currency,
        uom,
        brand,
        priceList,
        // Child DocTypes
        itemPrice
    ]
}
