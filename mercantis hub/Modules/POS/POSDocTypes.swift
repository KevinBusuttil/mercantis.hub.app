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

/// Phase 6 — POS v1. Real point-of-sale documents that post sales, tax,
/// payment, and stock in a single submit.
///
/// POS reuses the shared spine rather than inventing parallel logic:
/// - lines use the existing `SalesItem` child (so `HubTaxCalculationPolicy`
///   and the stock derivation work unchanged),
/// - taxes use the shared `TaxCharge` rows and `HubTaxEngine`,
/// - `LedgerDerivationService.derivePOSInvoice` posts the cash sale (Dr
///   cash / Cr income / Cr output VAT), the TaxTrans rows, and the stock
///   issue, all on submit.
enum POS {

    // MARK: - Master: POS Profile

    /// Configuration for one till / register: where stock is drawn from,
    /// which price list and posting accounts to use.
    static let posProfile = DocType(
        id: "POSProfile",
        name: "POS Profile",
        module: "POS",
        appId: HubManifest.appID,
        isChildTable: false,
        fields: [
            FieldDefinition(key: "profile_name", label: "Profile Name",
                            type: .text, required: true, isSearchable: true),
            FieldDefinition(key: "warehouse", label: "Warehouse",
                            type: .link, required: false, linkedDocType: "Warehouse"),
            FieldDefinition(key: "price_list", label: "Price List",
                            type: .link, required: false, linkedDocType: "PriceList"),
            FieldDefinition(key: "customer", label: "Default Customer",
                            type: .link, required: false, linkedDocType: "Customer"),
            FieldDefinition(key: "currency", label: "Currency",
                            type: .link, required: false, linkedDocType: "Currency"),
            FieldDefinition(key: "cash_account", label: "Cash / Bank Account",
                            type: .link, required: false, linkedDocType: "Account"),
            FieldDefinition(key: "income_account", label: "Income Account",
                            type: .link, required: false, linkedDocType: "Account"),
            FieldDefinition(key: "tax_code", label: "Default Tax Code",
                            type: .link, required: false, linkedDocType: "TaxCode"),
            FieldDefinition(key: "enabled", label: "Enabled",
                            type: .boolean, required: false, defaultValue: .bool(true))
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["profile_name"],
        titleField: "profile_name",
        formLayout: FormLayout(sections: [
            FormLayoutSection(
                key: "identity", title: "Profile", columns: 2,
                fieldKeys: ["profile_name", "currency", "enabled"]
            ),
            FormLayoutSection(
                key: "operations", title: "Operations",
                helpText: "Where the till draws stock and prices from.",
                columns: 2,
                fieldKeys: ["warehouse", "price_list", "customer", "tax_code"]
            ),
            FormLayoutSection(
                key: "posting", title: "Posting",
                helpText: "Accounts used when a POS sale is posted.",
                columns: 2,
                fieldKeys: ["cash_account", "income_account"]
            )
        ])
    )

    // MARK: - Master: POS Session

    /// A till shift. Sales reference the open session; closing it stamps the
    /// totals. No ledger derivation — it's an operational grouping record.
    static let posSession = DocType(
        id: "POSSession",
        name: "POS Session",
        module: "POS",
        appId: HubManifest.appID,
        isChildTable: false,
        fields: [
            FieldDefinition(key: "pos_profile", label: "POS Profile",
                            type: .link, required: true, linkedDocType: "POSProfile"),
            FieldDefinition(key: "status", label: "Status",
                            type: .select, required: false, defaultValue: .string("Open"),
                            options: ["Open", "Closed"]),
            FieldDefinition(key: "opening_date", label: "Opened",
                            type: .datetime, required: false),
            FieldDefinition(key: "closing_date", label: "Closed",
                            type: .datetime, required: false),
            FieldDefinition(key: "opening_amount", label: "Opening Float",
                            type: .currency, required: false, defaultValue: .double(0)),
            FieldDefinition(key: "closing_amount", label: "Closing Cash",
                            type: .currency, required: false),
            FieldDefinition(key: "total_sales", label: "Total Sales",
                            type: .currency, required: false, defaultValue: .double(0)),
            FieldDefinition(key: "total_qty", label: "Items Sold",
                            type: .decimal, required: false, defaultValue: .double(0))
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [
            IndexDefinition(fieldKey: "pos_profile", unique: false),
            IndexDefinition(fieldKey: "status", unique: false)
        ],
        searchFields: ["pos_profile"],
        titleField: "pos_profile"
    )

    // MARK: - Child: Payment Tender

    /// One tender line on a POS sale (cash / card / manual). Shared by the
    /// POS Invoice `tenders` table.
    static let paymentTender = DocType(
        id: "PaymentTender",
        name: "Payment Tender",
        module: "POS",
        appId: HubManifest.appID,
        isChildTable: true,
        fields: [
            FieldDefinition(key: "tender_type", label: "Tender",
                            type: .select, required: true, defaultValue: .string("Cash"),
                            options: ["Cash", "Card", "Other"]),
            FieldDefinition(key: "amount", label: "Amount",
                            type: .currency, required: true, defaultValue: .double(0)),
            FieldDefinition(key: "reference", label: "Reference",
                            type: .text, required: false)
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: [],
        titleField: "tender_type"
    )

    // MARK: - Parent: POS Invoice (the posted sale)

    static let posInvoice = DocType(
        id: "POSInvoice",
        name: "POS Sale",
        module: "POS",
        appId: HubManifest.appID,
        isChildTable: false,
        isSubmittable: true,
        fields: [
            FieldDefinition(key: "pos_profile", label: "POS Profile",
                            type: .link, required: false, linkedDocType: "POSProfile"),
            FieldDefinition(key: "pos_session", label: "POS Session",
                            type: .link, required: false, linkedDocType: "POSSession"),
            FieldDefinition(key: "customer", label: "Customer",
                            type: .link, required: false, linkedDocType: "Customer"),
            FieldDefinition(key: "transaction_date", label: "Date",
                            type: .date, required: true),
            FieldDefinition(key: "currency", label: "Currency",
                            type: .link, required: false, linkedDocType: "Currency"),
            FieldDefinition(key: "warehouse", label: "Warehouse",
                            type: .link, required: false, linkedDocType: "Warehouse"),
            FieldDefinition(key: "tax_code", label: "Default Tax Code",
                            type: .link, required: false, linkedDocType: "TaxCode"),
            FieldDefinition(key: "items", label: "Items",
                            type: .table, required: true, childDocType: "SalesItem"),
            FieldDefinition(key: "net_total", label: "Net Total",
                            type: .currency, required: false),
            FieldDefinition(key: "taxes", label: "Taxes",
                            type: .table, required: false, childDocType: "TaxCharge"),
            FieldDefinition(key: "total_taxes", label: "Total Taxes",
                            type: .currency, required: false),
            FieldDefinition(key: "total_qty", label: "Total Qty",
                            type: .decimal, required: false),
            FieldDefinition(key: "grand_total", label: "Grand Total",
                            type: .currency, required: false),
            FieldDefinition(key: "tenders", label: "Payments",
                            type: .table, required: false, childDocType: "PaymentTender"),
            FieldDefinition(key: "paid_amount", label: "Paid Amount",
                            type: .currency, required: false, defaultValue: .double(0)),
            FieldDefinition(key: "change_amount", label: "Change",
                            type: .currency, required: false, defaultValue: .double(0)),
            FieldDefinition(key: "cash_account", label: "Cash / Bank Account",
                            type: .link, required: false, linkedDocType: "Account"),
            FieldDefinition(key: "income_account", label: "Income Account",
                            type: .link, required: false, linkedDocType: "Account"),
            FieldDefinition(key: "remarks", label: "Remarks",
                            type: .longText, required: false, allowOnSubmit: true)
        ],
        permissions: [systemManagerPermission],
        workflowId: "wf-pos-invoice",
        autoname: "naming_series:POS-.YYYY.-.####",
        syncPolicy: SyncPolicy(conflictResolution: .versionChecked, immutableAfterSubmit: true),
        indexes: [
            IndexDefinition(fieldKey: "pos_session", unique: false),
            IndexDefinition(fieldKey: "transaction_date", unique: false)
        ],
        searchFields: ["customer"],
        titleField: "customer",
        formLayout: FormLayout(sections: [
            FormLayoutSection(key: "header", title: "Header", columns: 2,
                              fieldKeys: ["pos_profile", "pos_session", "customer",
                                          "transaction_date", "currency", "warehouse"]),
            FormLayoutSection(key: "items", title: "Items", fieldKeys: ["items"]),
            FormLayoutSection(key: "taxes", title: "Taxes", fieldKeys: ["taxes"]),
            FormLayoutSection(key: "totals", title: "Totals", columns: 2,
                              fieldKeys: ["total_qty", "net_total", "total_taxes", "grand_total"]),
            FormLayoutSection(key: "payment", title: "Payment", columns: 2,
                              fieldKeys: ["tenders", "paid_amount", "change_amount"]),
            FormLayoutSection(key: "posting", title: "Posting", columns: 2,
                              fieldKeys: ["cash_account", "income_account"])
        ])
    )

    static let allDocTypes: [DocType] = [
        paymentTender,
        posProfile,
        posSession,
        posInvoice
    ]
}
