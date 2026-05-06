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

enum Accounting {

    // MARK: - Tree master

    /// Account is the Chart-of-Accounts node. Tree DocType (Wall 8 already
    /// shipped by Core); root nodes carry `is_group = true` and child
    /// leaf accounts hold the balances.
    static let account = DocType(
        id: "Account",
        name: "Account",
        module: "Accounting",
        appId: HubManifest.appID,
        isChildTable: false,
        isTree: true,
        treeRootName: "Chart of Accounts",
        fields: [
            FieldDefinition(key: "account_name", label: "Account Name",
                            type: .text, required: true, isSearchable: true),
            FieldDefinition(key: "parent_account", label: "Parent Account",
                            type: .link, required: false, linkedDocType: "Account"),
            FieldDefinition(key: "is_group", label: "Is Group",
                            type: .boolean, required: false, defaultValue: .bool(false)),
            FieldDefinition(key: "account_type", label: "Account Type",
                            type: .select, required: false,
                            options: ["", "Bank", "Cash", "Stock", "Receivable",
                                      "Payable", "Tax", "Income", "Expense",
                                      "Equity", "Fixed Asset", "Stock Adjustment"]),
            FieldDefinition(key: "root_type", label: "Root Type",
                            type: .select, required: false,
                            options: ["", "Asset", "Liability", "Equity",
                                      "Income", "Expense"]),
            FieldDefinition(key: "currency", label: "Currency",
                            type: .link, required: false, linkedDocType: "Currency"),
            FieldDefinition(key: "disabled", label: "Disabled",
                            type: .boolean, required: false, defaultValue: .bool(false))
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["account_name"],
        titleField: "account_name"
    )

    // MARK: - Child DocTypes

    /// One row inside a Journal Entry — the per-account debit / credit
    /// posting. Wall 5 unlocks the structure; Wall 6 will gate submit on
    /// the parent; Wall 7 will derive GL Entry rows from submit.
    static let journalEntryAccount = DocType(
        id: "JournalEntryAccount",
        name: "Journal Entry Account",
        module: "Accounting",
        appId: HubManifest.appID,
        isChildTable: true,
        fields: [
            FieldDefinition(key: "account", label: "Account",
                            type: .link, required: true, linkedDocType: "Account"),
            FieldDefinition(key: "party_type", label: "Party Type",
                            type: .select, required: false,
                            options: ["", "Customer", "Supplier", "Employee"]),
            FieldDefinition(key: "party", label: "Party",
                            type: .text, required: false),
            FieldDefinition(key: "debit", label: "Debit",
                            type: .currency, required: false, defaultValue: .double(0)),
            FieldDefinition(key: "credit", label: "Credit",
                            type: .currency, required: false, defaultValue: .double(0)),
            FieldDefinition(key: "cost_center", label: "Cost Center",
                            type: .link, required: false, linkedDocType: "CostCenter"),
            FieldDefinition(key: "reference_doctype", label: "Reference DocType",
                            type: .select, required: false,
                            options: ["", "SalesInvoice", "PurchaseInvoice",
                                      "PaymentEntry", "JournalEntry"]),
            FieldDefinition(key: "reference_name", label: "Reference Name",
                            type: .text, required: false)
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: [],
        titleField: "account"
    )

    /// One row inside a Payment Entry — the per-invoice allocation.
    /// Wall 5 ships the structure; Wall 6 / Wall 7 layer on submit + GL.
    static let paymentEntryReference = DocType(
        id: "PaymentEntryReference",
        name: "Payment Entry Reference",
        module: "Accounting",
        appId: HubManifest.appID,
        isChildTable: true,
        fields: [
            FieldDefinition(key: "reference_doctype", label: "Reference DocType",
                            type: .select, required: true,
                            options: ["SalesInvoice", "PurchaseInvoice", "JournalEntry"]),
            FieldDefinition(key: "reference_name", label: "Reference Name",
                            type: .text, required: true),
            FieldDefinition(key: "total_amount", label: "Total Amount",
                            type: .currency, required: false),
            FieldDefinition(key: "outstanding_amount", label: "Outstanding",
                            type: .currency, required: false),
            FieldDefinition(key: "allocated_amount", label: "Allocated Amount",
                            type: .currency, required: true, defaultValue: .double(0))
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: [],
        titleField: "reference_name"
    )

    // MARK: - Parent DocTypes

    /// Journal Entry — manual debit/credit posting set. Wall 6 makes it
    /// submittable with the `wf-journal-entry` workflow and adds a
    /// total-debit-equals-total-credit submit-time validation rule.
    /// GL-entry derivation waits on Wall 7.
    static let journalEntry = DocType(
        id: "JournalEntry",
        name: "Journal Entry",
        module: "Accounting",
        appId: HubManifest.appID,
        isChildTable: false,
        isSubmittable: true,
        fields: [
            FieldDefinition(key: "voucher_type", label: "Voucher Type",
                            type: .select, required: true,
                            options: ["Journal Entry", "Bank Entry", "Cash Entry",
                                      "Credit Card Entry", "Debit Note", "Credit Note",
                                      "Contra Entry", "Excise Entry"]),
            FieldDefinition(key: "posting_date", label: "Posting Date",
                            type: .date, required: true),
            FieldDefinition(key: "company_currency", label: "Company Currency",
                            type: .link, required: false, linkedDocType: "Currency"),
            FieldDefinition(key: "accounts", label: "Accounts",
                            type: .table, required: true, childDocType: "JournalEntryAccount"),
            FieldDefinition(
                key: "total_debit", label: "Total Debit",
                type: .currency, required: false,
                validationRules: [
                    ValidationRule(
                        ruleType: "expression",
                        expression: "total_debit == total_credit",
                        message: "Total debit must equal total credit before submitting."
                    )
                ]
            ),
            FieldDefinition(key: "total_credit", label: "Total Credit",
                            type: .currency, required: false),
            FieldDefinition(key: "user_remark", label: "User Remark",
                            type: .longText, required: false,
                            allowOnSubmit: true)
        ],
        permissions: [systemManagerPermission],
        workflowId: "wf-journal-entry",
        autoname: "naming_series:JE-.YYYY.-.####",
        syncPolicy: SyncPolicy(conflictResolution: .versionChecked, immutableAfterSubmit: true),
        indexes: [],
        searchFields: ["voucher_type"],
        titleField: "voucher_type",
        formLayout: FormLayout(sections: [
            FormLayoutSection(
                key: "header",
                title: "Header",
                fieldKeys: ["voucher_type", "posting_date", "company_currency"]
            ),
            FormLayoutSection(
                key: "accounts",
                title: "Account Postings",
                helpText: "Total debit must equal total credit on submit (Wall 6 enforces).",
                fieldKeys: ["accounts"]
            ),
            FormLayoutSection(
                key: "totals",
                title: "Totals",
                fieldKeys: ["total_debit", "total_credit"]
            ),
            FormLayoutSection(
                key: "remarks",
                title: "Remarks",
                fieldKeys: ["user_remark"]
            )
        ])
    )

    /// Payment Entry — receipt or payment voucher. Allocates one cash /
    /// bank movement to one or more invoices via the `references` child
    /// table. Wall 6 makes it submittable with the `wf-payment-entry`
    /// workflow. GL derivation waits on Wall 7.
    static let paymentEntry = DocType(
        id: "PaymentEntry",
        name: "Payment Entry",
        module: "Accounting",
        appId: HubManifest.appID,
        isChildTable: false,
        isSubmittable: true,
        fields: [
            FieldDefinition(key: "payment_type", label: "Payment Type",
                            type: .select, required: true,
                            options: ["Receive", "Pay", "Internal Transfer"]),
            FieldDefinition(key: "posting_date", label: "Posting Date",
                            type: .date, required: true),
            FieldDefinition(key: "party_type", label: "Party Type",
                            type: .select, required: false,
                            options: ["", "Customer", "Supplier", "Employee"]),
            FieldDefinition(key: "party", label: "Party",
                            type: .text, required: false),
            FieldDefinition(key: "paid_from", label: "Paid From",
                            type: .link, required: true, linkedDocType: "Account"),
            FieldDefinition(key: "paid_to", label: "Paid To",
                            type: .link, required: true, linkedDocType: "Account"),
            FieldDefinition(key: "paid_amount", label: "Paid Amount",
                            type: .currency, required: true, defaultValue: .double(0)),
            FieldDefinition(key: "received_amount", label: "Received Amount",
                            type: .currency, required: false),
            FieldDefinition(key: "references", label: "Allocations",
                            type: .table, required: false,
                            childDocType: "PaymentEntryReference",
                            allowOnSubmit: true),
            FieldDefinition(key: "remarks", label: "Remarks",
                            type: .longText, required: false,
                            allowOnSubmit: true)
        ],
        permissions: [systemManagerPermission],
        workflowId: "wf-payment-entry",
        autoname: "naming_series:PE-.YYYY.-.####",
        syncPolicy: SyncPolicy(conflictResolution: .versionChecked, immutableAfterSubmit: true),
        indexes: [],
        searchFields: ["party"],
        titleField: "party",
        formLayout: FormLayout(sections: [
            FormLayoutSection(
                key: "header",
                title: "Header",
                fieldKeys: ["payment_type", "posting_date"]
            ),
            FormLayoutSection(
                key: "party",
                title: "Party",
                fieldKeys: ["party_type", "party"]
            ),
            FormLayoutSection(
                key: "accounts",
                title: "Accounts",
                fieldKeys: ["paid_from", "paid_to", "paid_amount", "received_amount"]
            ),
            FormLayoutSection(
                key: "references",
                title: "Allocations",
                helpText: "Match this payment to one or more outstanding invoices.",
                fieldKeys: ["references"]
            ),
            FormLayoutSection(
                key: "remarks",
                title: "Remarks",
                fieldKeys: ["remarks"]
            )
        ])
    )

    static let allDocTypes: [DocType] = [
        // Master
        account,
        // Child DocTypes
        journalEntryAccount, paymentEntryReference,
        // Parents
        journalEntry, paymentEntry
    ]
}
