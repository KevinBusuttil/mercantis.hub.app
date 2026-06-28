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

/// Phase 2 (Accounting Autopilot) — Banking master + operational DocTypes.
///
/// A non-accountant owner expects the bank to be central. A `BankAccount` is the
/// owner-facing wrapper over a chart-of-accounts cash/bank node (it carries the
/// IBAN / last-4 / processor metadata the GL account doesn't). `BankStatementLine`
/// stages imported bank transactions for reconciliation, and `BankReconciliation`
/// records a reconciled period.
enum Banking {

    /// A real bank / cash / card / payment-processor account, wrapping a GL
    /// cash-or-bank Account with the metadata reconciliation needs.
    static let bankAccount = DocType(
        id: "BankAccount",
        name: "Bank Account",
        module: "Accounting",
        appId: HubManifest.appID,
        isChildTable: false,
        fields: [
            FieldDefinition(key: "account_name", label: "Account Name",
                            type: .text, required: true, isSearchable: true),
            FieldDefinition(key: "account_kind", label: "Type",
                            type: .select, required: false,
                            helpText: "Bank, cash, card, or a payment processor (Stripe / PayPal).",
                            defaultValue: .string("Bank"),
                            options: ["Bank", "Cash", "Card", "Stripe", "PayPal", "Other"]),
            FieldDefinition(key: "gl_account", label: "Ledger Account",
                            type: .link, required: true,
                            helpText: "The chart-of-accounts account this bank account posts to.",
                            linkedDocType: "Account"),
            FieldDefinition(key: "account_number", label: "Account Number / IBAN",
                            type: .text, required: false, isSearchable: true),
            FieldDefinition(key: "currency", label: "Currency",
                            type: .link, required: false, linkedDocType: "Currency"),
            FieldDefinition(key: "opening_balance", label: "Opening Balance",
                            type: .currency, required: false, defaultValue: .double(0)),
            FieldDefinition(key: "disabled", label: "Disabled",
                            type: .boolean, required: false, defaultValue: .bool(false))
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["account_name", "account_number"],
        titleField: "account_name",
        formLayout: FormLayout(sections: [
            FormLayoutSection(
                key: "identity", title: "Bank Account",
                helpText: "Set up each bank, cash, card, or payment-processor account so you can reconcile it.",
                columns: 2,
                fieldKeys: ["account_name", "account_kind", "gl_account", "account_number", "currency", "opening_balance"]
            )
        ])
    )

    /// One imported bank-statement transaction, staged for matching. `amount`
    /// is signed: positive = money in, negative = money out.
    static let bankStatementLine = DocType(
        id: "BankStatementLine",
        name: "Bank Statement Line",
        module: "Accounting",
        appId: HubManifest.appID,
        isChildTable: false,
        fields: [
            FieldDefinition(key: "bank_account", label: "Bank Account",
                            type: .link, required: true, linkedDocType: "BankAccount"),
            FieldDefinition(key: "line_date", label: "Date",
                            type: .date, required: false),
            FieldDefinition(key: "description", label: "Description",
                            type: .text, required: false, isSearchable: true),
            FieldDefinition(key: "reference", label: "Reference",
                            type: .text, required: false),
            FieldDefinition(key: "amount", label: "Amount",
                            type: .currency, required: false, defaultValue: .double(0)),
            FieldDefinition(key: "running_balance", label: "Balance",
                            type: .currency, required: false),
            FieldDefinition(key: "status", label: "Status",
                            type: .select, required: false,
                            defaultValue: .string("Unmatched"),
                            options: ["Unmatched", "Matched", "Reconciled", "Ignored"]),
            FieldDefinition(key: "matched_doctype", label: "Matched DocType",
                            type: .text, required: false),
            FieldDefinition(key: "matched_name", label: "Matched Record",
                            type: .text, required: false),
            FieldDefinition(key: "category_account", label: "Category Account",
                            type: .link, required: false, linkedDocType: "Account"),
            FieldDefinition(key: "journal_entry", label: "Journal Entry",
                            type: .text, required: false)
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["description", "reference"],
        titleField: "description"
    )

    /// A reconciled statement period for a bank account.
    static let bankReconciliation = DocType(
        id: "BankReconciliation",
        name: "Bank Reconciliation",
        module: "Accounting",
        appId: HubManifest.appID,
        isChildTable: false,
        fields: [
            FieldDefinition(key: "bank_account", label: "Bank Account",
                            type: .link, required: true, linkedDocType: "BankAccount"),
            FieldDefinition(key: "statement_date", label: "Statement Date",
                            type: .date, required: false),
            FieldDefinition(key: "opening_balance", label: "Opening Balance",
                            type: .currency, required: false, defaultValue: .double(0)),
            FieldDefinition(key: "closing_balance", label: "Statement Closing Balance",
                            type: .currency, required: false, defaultValue: .double(0)),
            FieldDefinition(key: "reconciled_balance", label: "Reconciled Balance",
                            type: .currency, required: false, defaultValue: .double(0)),
            FieldDefinition(key: "status", label: "Status",
                            type: .select, required: false,
                            defaultValue: .string("Open"),
                            options: ["Open", "Reconciled"]),
            FieldDefinition(key: "notes", label: "Notes",
                            type: .longText, required: false)
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: [],
        titleField: "bank_account"
    )

    static let allDocTypes: [DocType] = [bankAccount, bankStatementLine, bankReconciliation]
}
