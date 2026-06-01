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

/// Phase 2 — VAT / Tax Foundation master data.
///
/// Two masters plus one shared child table:
/// - `TaxCategory` — optional grouping (e.g. "Goods", "Services", "Domestic").
/// - `TaxCode` — the VAT code itself: Standard / Reduced / Zero / Exempt,
///   each carrying a rate and a posting account.
/// - `TaxCharge` — one computed tax row inside an invoice's `taxes` table.
///
/// All three are Hub-owned business DocTypes built on Core's generic
/// metadata primitives, consistent with the rest of the Hub manifest.
enum Tax {

    // MARK: - Tax Category

    /// Optional grouping for tax codes. Micro businesses can ignore it;
    /// it exists so codes can be organised (Goods vs Services, Domestic vs
    /// EU) without overloading the code name.
    static let taxCategory = DocType(
        id: "TaxCategory",
        name: "Tax Category",
        module: "Tax",
        appId: HubManifest.appID,
        isChildTable: false,
        fields: [
            FieldDefinition(key: "tax_category_name", label: "Tax Category Name",
                            type: .text, required: true, isSearchable: true),
            FieldDefinition(key: "description", label: "Description",
                            type: .longText, required: false),
            FieldDefinition(key: "enabled", label: "Enabled",
                            type: .boolean, required: false, defaultValue: .bool(true))
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["tax_category_name"],
        titleField: "tax_category_name"
    )

    // MARK: - Tax Code (VAT Code)

    /// The VAT / tax code. The acceptance criterion "User can create VAT
    /// codes: Standard, Reduced, Zero, Exempt" is satisfied by creating one
    /// `TaxCode` record per code with the appropriate `rate`:
    /// Standard (e.g. 18), Reduced (e.g. 7), Zero (0), Exempt (0).
    ///
    /// `tax_account` is the GL account the tax posts to (output VAT for
    /// sales, input VAT for purchases). When empty, derivation falls back
    /// to the Business Profile `default_vat_account`.
    static let taxCode = DocType(
        id: "TaxCode",
        name: "Tax Code",
        module: "Tax",
        appId: HubManifest.appID,
        isChildTable: false,
        fields: [
            FieldDefinition(key: "tax_code_name", label: "Tax Code Name",
                            type: .text, required: true, isSearchable: true),
            FieldDefinition(key: "tax_type", label: "Tax Type",
                            type: .select, required: true,
                            defaultValue: .string("VAT"),
                            options: ["VAT", "SalesTax"]),
            FieldDefinition(key: "rate", label: "Rate (%)",
                            type: .decimal, required: true, defaultValue: .double(0)),
            FieldDefinition(key: "tax_category", label: "Tax Category",
                            type: .link, required: false, linkedDocType: "TaxCategory"),
            FieldDefinition(key: "tax_account", label: "Tax Account",
                            type: .link, required: false, linkedDocType: "Account"),
            FieldDefinition(key: "is_default", label: "Default",
                            type: .boolean, required: false, defaultValue: .bool(false)),
            FieldDefinition(key: "enabled", label: "Enabled",
                            type: .boolean, required: false, defaultValue: .bool(true))
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["tax_code_name"],
        titleField: "tax_code_name",
        formLayout: FormLayout(sections: [
            FormLayoutSection(
                key: "identity",
                title: "Tax Code",
                helpText: "Create one code per VAT band: Standard, Reduced, Zero, Exempt.",
                columns: 2,
                fieldKeys: ["tax_code_name", "tax_type", "rate", "tax_category"]
            ),
            FormLayoutSection(
                key: "posting",
                title: "Posting",
                helpText: "Account the tax posts to. Leave blank to use the Business Profile default VAT account.",
                columns: 2,
                fieldKeys: ["tax_account", "is_default", "enabled"]
            )
        ])
    )

    // MARK: - Tax Charge (invoice tax row)

    /// One computed tax row inside a Sales Invoice / Purchase Invoice
    /// `taxes` child table. Populated by `HubTaxCalculationPolicy`, then
    /// turned into `TaxTrans` ledger rows on submit. Shared between sales
    /// and purchase (and later POS) so there is a single tax row shape.
    static let taxCharge = DocType(
        id: "TaxCharge",
        name: "Tax Charge",
        module: "Tax",
        appId: HubManifest.appID,
        isChildTable: true,
        fields: [
            FieldDefinition(key: "tax_code", label: "Tax Code",
                            type: .link, required: true, linkedDocType: "TaxCode"),
            FieldDefinition(key: "tax_type", label: "Tax Type",
                            type: .text, required: false),
            FieldDefinition(key: "description", label: "Description",
                            type: .text, required: false),
            FieldDefinition(key: "rate", label: "Rate (%)",
                            type: .decimal, required: false, defaultValue: .double(0)),
            FieldDefinition(key: "tax_account", label: "Tax Account",
                            type: .link, required: false, linkedDocType: "Account"),
            FieldDefinition(key: "taxable_amount", label: "Taxable Amount",
                            type: .currency, required: false, defaultValue: .double(0)),
            FieldDefinition(key: "tax_amount", label: "Tax Amount",
                            type: .currency, required: false, defaultValue: .double(0))
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: [],
        titleField: "tax_code"
    )

    static let allDocTypes: [DocType] = [
        taxCategory,
        taxCode,
        taxCharge
    ]
}
