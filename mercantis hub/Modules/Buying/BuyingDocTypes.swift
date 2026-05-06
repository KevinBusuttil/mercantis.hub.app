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

    /// Supplier is the canonical "we buy from" entity. Wall 4 unlocks the
    /// link fields (`supplier_group`, `default_currency`,
    /// `default_price_list`); supplier-side address / contact rows wait
    /// for Wall 5 (child tables).
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

    static let allDocTypes: [DocType] = [supplier]
}
