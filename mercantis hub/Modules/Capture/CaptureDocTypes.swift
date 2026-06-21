import MercantisCore

/// Document Capture (ADR-049). A lightweight intake record for a photographed
/// or uploaded receipt/bill, plus the internal merchant→supplier learning rule.
///
/// The receipt image rides as a synced attachment (ADR-048) bound to the
/// capture via the `document_file` field key — not a payload field — so the
/// "Captured Document" DocType holds only the *extracted* metadata a reviewer
/// confirms before a draft voucher is created.
///
/// Deliberately simple for self-employed users: neither DocType is
/// submittable, there is no workflow and no regex rules. A plain `status`
/// select drives the review queue; routing to a draft Purchase Invoice happens
/// from the review screen, never automatically.
///
/// Swift parity notes vs the Flutter `CaptureModule`:
///   • Flutter `FieldType.data`     → Swift `.text`
///   • Flutter `FieldType.integer`  → Swift `.number`
///   • Flutter `FieldType.smallText`→ Swift `.longText`
///   • Flutter `FieldType.percent`  → Swift `.percent`
///   • Flutter `options: "A\nB\nC"` newline strings → Swift `options: [String]`.
private let captureSystemManagerPermission = PermissionRule(
    role: "System Manager",
    canRead: true,
    canWrite: true,
    canCreate: true,
    canDelete: true,
    canSubmit: false,
    canAmend: false
)

enum Capture {

    // MARK: - Constants (mirror Flutter CaptureModule)

    static let moduleName = "Document Capture"

    /// Status values for a capture's lifecycle. Plain strings on the `status`
    /// field — no submittable workflow.
    static let statusReceived     = "Received"
    static let statusReady        = "Ready"
    static let statusNeedsReview  = "Needs Review"
    static let statusDraftCreated = "Draft Created"
    static let statusDuplicate    = "Duplicate"

    static let statusOptions: [String] = [
        statusReceived, statusReady, statusNeedsReview, statusDraftCreated, statusDuplicate
    ]

    /// Field key under which the receipt image is attached (via AttachmentManager).
    static let documentFileFieldKey = "document_file"

    /// "Anyone" means the capture shows in every operator's review queue; other
    /// values scope it to operators whose role matches (see `visibleToRole`).
    static let roleAnyone = "Anyone"
    static let roleOptions: [String] = [roleAnyone, "Bookkeeping", "Management", "Field"]

    /// Lifecycle values that still want a human's eyes in the review queue.
    static let openStatuses: Set<String> = [statusReceived, statusReady, statusNeedsReview]

    /// Normalised merchant key used to remember a merchant→supplier mapping.
    /// Lower-cased, with digits and punctuation stripped and whitespace
    /// collapsed — so "BP Service Station #4471" and "BP SERVICE STATION" share
    /// a memory even when a store/receipt number is appended to the name.
    static func merchantKey(_ merchant: String) -> String {
        let lowered = merchant.lowercased()
        // Replace anything that isn't a-z or space with a space.
        let cleaned = String(lowered.map { ch -> Character in
            (ch == " " || (ch >= "a" && ch <= "z")) ? ch : " "
        })
        // Collapse runs of whitespace into single spaces, then trim.
        let collapsed = cleaned.split(whereSeparator: { $0 == " " }).joined(separator: " ")
        return collapsed.trimmingCharacters(in: .whitespaces)
    }

    /// View-only role scoping (ADR-049): every company member receives every
    /// capture (sync is not partitioned), but a capture tagged for a specific
    /// role only surfaces in that role's review queue. "Anyone"/empty shows to
    /// all; a System Manager sees everything.
    static func visibleToRole(_ intendedRole: String?, userRoles: Set<String>) -> Bool {
        guard let intendedRole, !intendedRole.isEmpty, intendedRole != roleAnyone else {
            return true
        }
        if userRoles.contains("System Manager") { return true }
        let wanted = intendedRole.lowercased()
        return userRoles.contains { $0.lowercased() == wanted }
    }

    // MARK: - DocTypes

    /// A lightweight intake record for a photographed/uploaded receipt or bill.
    static let capturedDocument = DocType(
        id: "Captured Document",
        name: "Captured Document",
        module: moduleName,
        appId: HubManifest.appID,
        isChildTable: false,
        isSubmittable: false,
        fields: [
            FieldDefinition(key: "status", label: "Status", type: .select,
                            required: false,
                            defaultValue: .string(statusReceived),
                            options: statusOptions),
            FieldDefinition(key: "source_type", label: "Source", type: .select,
                            required: false,
                            defaultValue: .string("Camera"),
                            options: ["Camera", "Upload"]),
            // — Extracted / confirmed metadata —
            FieldDefinition(key: "merchant_name", label: "Merchant", type: .text,
                            required: false, isSearchable: true),
            FieldDefinition(key: "supplier", label: "Supplier", type: .link,
                            required: false, linkedDocType: "Supplier"),
            FieldDefinition(key: "document_date", label: "Document Date", type: .date,
                            required: false),
            FieldDefinition(key: "invoice_no", label: "Invoice / Receipt No", type: .text,
                            required: false),
            FieldDefinition(key: "net_total", label: "Net Total", type: .currency,
                            required: false),
            FieldDefinition(key: "vat_total", label: "VAT Total", type: .currency,
                            required: false),
            FieldDefinition(key: "grand_total", label: "Grand Total", type: .currency,
                            required: false),
            FieldDefinition(key: "currency", label: "Currency", type: .link,
                            required: false, linkedDocType: "Currency"),
            // — Review routing —
            FieldDefinition(key: "intended_role", label: "For", type: .select,
                            required: false,
                            defaultValue: .string(roleAnyone),
                            options: roleOptions),
            FieldDefinition(key: "extraction_confidence", label: "Extraction Confidence",
                            type: .percent, required: false,
                            readOnlyExpression: "true"),
            FieldDefinition(key: "voucher_type", label: "Created Voucher Type", type: .text,
                            required: false, readOnlyExpression: "true"),
            FieldDefinition(key: "linked_voucher", label: "Created Voucher", type: .text,
                            required: false, readOnlyExpression: "true"),
            FieldDefinition(key: "notes", label: "Notes", type: .longText, required: false)
        ],
        permissions: [captureSystemManagerPermission],
        autoname: "naming_series:CAP-.YYYY.-.####",
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["merchant_name", "invoice_no"],
        titleField: "merchant_name",
        formLayout: FormLayout(sections: [
            FormLayoutSection(
                key: "intake",
                title: "Capture",
                columns: 2,
                fieldKeys: ["status", "source_type", "intended_role", "extraction_confidence"]
            ),
            FormLayoutSection(
                key: "extracted",
                title: "Extracted",
                helpText: "Read on-device (or by the optional AI). Confirm before creating a draft.",
                columns: 2,
                fieldKeys: ["merchant_name", "supplier", "document_date", "invoice_no",
                            "net_total", "vat_total", "grand_total", "currency"]
            ),
            FormLayoutSection(
                key: "voucher",
                title: "Created Voucher",
                columns: 2,
                fieldKeys: ["voucher_type", "linked_voucher"]
            ),
            FormLayoutSection(
                key: "notes",
                title: "Notes",
                fieldKeys: ["notes"]
            )
        ])
    )

    /// Internal learning rule (ADR-049): a remembered merchant→supplier
    /// mapping, keyed by `merchantKey`. Written silently when a draft is created
    /// and read back to prefill future captures. Not user-facing — no regex, no
    /// setup.
    static let captureRule = DocType(
        id: "Capture Rule",
        name: "Capture Rule",
        module: moduleName,
        appId: HubManifest.appID,
        isChildTable: false,
        isSubmittable: false,
        fields: [
            FieldDefinition(key: "merchant_name", label: "Merchant", type: .text,
                            required: false, isSearchable: true),
            FieldDefinition(key: "supplier", label: "Supplier", type: .link,
                            required: false, linkedDocType: "Supplier"),
            FieldDefinition(key: "times_seen", label: "Times Seen", type: .number,
                            required: false)
        ],
        permissions: [captureSystemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["merchant_name"],
        titleField: "merchant_name"
    )

    static let allDocTypes: [DocType] = [capturedDocument, captureRule]
}
