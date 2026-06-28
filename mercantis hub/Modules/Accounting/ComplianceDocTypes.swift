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

/// Phase 3 (Accounting Autopilot) — the compliance record DocTypes.
///
/// A `TaxFiling` is the saved snapshot of a tax return the owner has reviewed and
/// filed: the period, the headline boxes, and who filed it when. Saving it gives
/// three things for free — a list surface (the owner's "filed returns" history),
/// the audit-log trail every Document gets, and a natural place to anchor the
/// books-lock that protects the filed period. The child `TaxFilingBox` keeps the
/// per-band breakdown so the figures are a durable record, not a recomputation.
enum Compliance {

    /// A filed (or draft) tax return for a period.
    static let taxFiling = DocType(
        id: "TaxFiling",
        name: "Tax Filing",
        module: "Accounting",
        appId: HubManifest.appID,
        isChildTable: false,
        fields: [
            FieldDefinition(key: "period_label", label: "Period",
                            type: .text, required: true, isSearchable: true),
            FieldDefinition(key: "tax_noun", label: "Tax",
                            type: .text, required: false,
                            helpText: "VAT, Sales Tax, or GST/HST — from your jurisdiction.",
                            defaultValue: .string("VAT")),
            FieldDefinition(key: "period_start", label: "Period Start",
                            type: .date, required: false),
            FieldDefinition(key: "period_end", label: "Period End",
                            type: .date, required: false),
            FieldDefinition(key: "output_tax", label: "Tax Collected (Sales)",
                            type: .currency, required: false, defaultValue: .double(0)),
            FieldDefinition(key: "input_tax", label: "Tax Paid (Purchases)",
                            type: .currency, required: false, defaultValue: .double(0)),
            FieldDefinition(key: "net_payable", label: "Net Payable",
                            type: .currency, required: false, defaultValue: .double(0)),
            FieldDefinition(key: "output_base", label: "Taxable Sales",
                            type: .currency, required: false, defaultValue: .double(0)),
            FieldDefinition(key: "input_base", label: "Taxable Purchases",
                            type: .currency, required: false, defaultValue: .double(0)),
            FieldDefinition(key: "status", label: "Status",
                            type: .select, required: false,
                            defaultValue: .string("Draft"),
                            options: ["Draft", "Filed"]),
            FieldDefinition(key: "filed_on", label: "Filed On",
                            type: .date, required: false),
            FieldDefinition(key: "filed_by", label: "Filed By",
                            type: .text, required: false),
            FieldDefinition(key: "boxes", label: "Breakdown",
                            type: .table, required: false, childDocType: "TaxFilingBox"),
            FieldDefinition(key: "notes", label: "Notes",
                            type: .longText, required: false)
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["period_label", "tax_noun"],
        titleField: "period_label",
        formLayout: FormLayout(sections: [
            FormLayoutSection(
                key: "summary", title: "Tax Filing",
                helpText: "A return you've reviewed and filed for a period. The figures are a snapshot at the time you filed.",
                columns: 2,
                fieldKeys: ["period_label", "tax_noun", "period_start", "period_end",
                            "output_tax", "input_tax", "net_payable",
                            "output_base", "input_base", "status", "filed_on", "filed_by"]
            )
        ])
    )

    /// One band (tax code / rate) inside a filing's breakdown.
    static let taxFilingBox = DocType(
        id: "TaxFilingBox",
        name: "Tax Filing Box",
        module: "Accounting",
        appId: HubManifest.appID,
        isChildTable: true,
        fields: [
            FieldDefinition(key: "label", label: "Band",
                            type: .text, required: false),
            FieldDefinition(key: "rate", label: "Rate",
                            type: .currency, required: false, defaultValue: .double(0)),
            FieldDefinition(key: "output_tax", label: "Tax Collected",
                            type: .currency, required: false, defaultValue: .double(0)),
            FieldDefinition(key: "input_tax", label: "Tax Paid",
                            type: .currency, required: false, defaultValue: .double(0))
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: [],
        titleField: "label"
    )

    static let allDocTypes: [DocType] = [taxFiling, taxFilingBox]
}
