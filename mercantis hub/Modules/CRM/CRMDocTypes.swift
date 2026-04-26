import MercantisCore

enum CRM {

    static let customer = DocType(
        id: "Customer",
        name: "Customer",
        module: "CRM",
        appId: HubManifest.appID,
        isChildTable: false,
        fields: [
            FieldDefinition(
                key: "customer_name",
                label: "Customer Name",
                type: .text,
                required: true,
                isSearchable: true
            ),
            FieldDefinition(
                key: "email",
                label: "Email",
                type: .email,
                required: false,
                isSearchable: true
            ),
            FieldDefinition(
                key: "phone",
                label: "Phone",
                type: .phone,
                required: false
            )
        ],
        permissions: [
            PermissionRule(
                role: "System Manager",
                canRead: true,
                canWrite: true,
                canCreate: true,
                canDelete: true,
                canSubmit: false,
                canAmend: false
            )
        ],
        autoname: "naming_series:CUST-.YYYY.-.####",
        syncPolicy: SyncPolicy(
            conflictResolution: .lastWriteWins,
            immutableAfterSubmit: false
        ),
        indexes: [],
        searchFields: ["customer_name", "email"],
        titleField: "customer_name"
    )

    static let allDocTypes: [DocType] = [customer]
}
