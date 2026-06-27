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

/// User-defined print formats, stored as documents so they sync across devices
/// via the normal document sync. The full `MercantisCore.PrintFormat` config is
/// JSON-encoded into `payload`; the other fields mirror it for listing and the
/// default lookup. Built-in formats live in code (`HubPrintFormats`); these are
/// the customisable ones an operator creates in the Print Formats manager.
enum PrintingDocs {

    static let printFormat = DocType(
        id: "PrintFormat",
        name: "Print Format",
        module: "Printing",
        appId: HubManifest.appID,
        isChildTable: false,
        fields: [
            FieldDefinition(key: "format_name", label: "Name",
                            type: .text, required: true, isSearchable: true),
            FieldDefinition(key: "target_doctype", label: "Document Type",
                            type: .text, required: true),
            FieldDefinition(key: "is_default", label: "Default",
                            type: .boolean, required: false, defaultValue: .bool(false)),
            FieldDefinition(key: "based_on", label: "Based On",
                            type: .text, required: false),
            // JSON-encoded MercantisCore.PrintFormat (the renderable definition).
            FieldDefinition(key: "payload", label: "Definition",
                            type: .longText, required: false)
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [
            IndexDefinition(fieldKey: "target_doctype", unique: false)
        ],
        searchFields: ["format_name"],
        titleField: "format_name"
    )

    static let allDocTypes: [DocType] = [printFormat]
}
