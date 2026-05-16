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

enum Stock {

    // MARK: - Child DocTypes

    /// One row inside a Stock Entry — the per-line item movement
    /// (source warehouse → target warehouse, quantity, valuation rate).
    /// Wall 5 unlocks the structure; Wall 6 will gate submit on the
    /// parent Stock Entry; Wall 7 will derive Stock Ledger rows.
    static let stockEntryDetail = DocType(
        id: "StockEntryDetail",
        name: "Stock Entry Detail",
        module: "Stock",
        appId: HubManifest.appID,
        isChildTable: true,
        fields: [
            FieldDefinition(key: "item", label: "Item",
                            type: .link, required: true, linkedDocType: "Item"),
            FieldDefinition(key: "uom", label: "UOM",
                            type: .link, required: false, linkedDocType: "UOM"),
            FieldDefinition(key: "qty", label: "Quantity",
                            type: .decimal, required: true, defaultValue: .double(0)),
            FieldDefinition(key: "source_warehouse", label: "Source Warehouse",
                            type: .link, required: false, linkedDocType: "Warehouse"),
            FieldDefinition(key: "target_warehouse", label: "Target Warehouse",
                            type: .link, required: false, linkedDocType: "Warehouse"),
            FieldDefinition(key: "valuation_rate", label: "Valuation Rate",
                            type: .currency, required: false),
            FieldDefinition(key: "amount", label: "Amount",
                            type: .currency, required: false,
                            formulaExpression: "qty * valuation_rate")
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: [],
        titleField: "item"
    )

    // MARK: - Parent DocTypes

    /// Stock Entry — generic stock movement. `purpose` chooses receipt /
    /// issue / transfer / repack semantics. Wall 6 makes it submittable
    /// with the `wf-stock-entry` workflow. Submit-time stock-ledger
    /// derivation waits on Wall 7.
    static let stockEntry = DocType(
        id: "StockEntry",
        name: "Stock Entry",
        module: "Stock",
        appId: HubManifest.appID,
        isChildTable: false,
        isSubmittable: true,
        fields: [
            FieldDefinition(key: "purpose", label: "Purpose",
                            type: .select, required: true,
                            options: ["Material Receipt", "Material Issue",
                                      "Material Transfer", "Repack",
                                      "Manufacturing", "Send to Subcontractor"]),
            FieldDefinition(key: "posting_date", label: "Posting Date",
                            type: .date, required: true),
            FieldDefinition(key: "posting_time", label: "Posting Time",
                            type: .datetime, required: false),
            FieldDefinition(key: "default_source_warehouse", label: "Default Source Warehouse",
                            type: .link, required: false, linkedDocType: "Warehouse"),
            FieldDefinition(key: "default_target_warehouse", label: "Default Target Warehouse",
                            type: .link, required: false, linkedDocType: "Warehouse"),
            FieldDefinition(key: "items", label: "Items",
                            type: .table, required: true, childDocType: "StockEntryDetail"),
            FieldDefinition(key: "total_value", label: "Total Value",
                            type: .currency, required: false),
            FieldDefinition(key: "remarks", label: "Remarks",
                            type: .longText, required: false,
                            allowOnSubmit: true)
        ],
        permissions: [systemManagerPermission],
        workflowId: "wf-stock-entry",
        autoname: "naming_series:STE-.YYYY.-.####",
        syncPolicy: SyncPolicy(conflictResolution: .versionChecked, immutableAfterSubmit: true),
        indexes: [],
        searchFields: ["purpose"],
        titleField: "purpose",
        formLayout: FormLayout(sections: [
            FormLayoutSection(
                key: "header",
                title: "Header",
                fieldKeys: ["purpose", "posting_date", "posting_time"]
            ),
            FormLayoutSection(
                key: "defaults",
                title: "Default Warehouses",
                helpText: "Pre-fills source / target on each new line.",
                fieldKeys: ["default_source_warehouse", "default_target_warehouse"]
            ),
            FormLayoutSection(
                key: "items",
                title: "Items",
                fieldKeys: ["items"]
            ),
            FormLayoutSection(
                key: "totals",
                title: "Totals",
                fieldKeys: ["total_value"]
            ),
            FormLayoutSection(
                key: "remarks",
                title: "Remarks",
                fieldKeys: ["remarks"]
            )
        ])
    )

    static let allDocTypes: [DocType] = [
        stockEntryDetail,
        stockEntry,
        stockLedgerEntry
    ]

    // MARK: - Derived ledger (Wall 7)

    /// Stock Ledger Entry — append-only inventory movement record derived
    /// from Stock Entry submit. Each Stock Entry row produces one SLE per
    /// side (one for source warehouse, one for target warehouse) with a
    /// signed `qty_change`. On Stock Entry cancel, reversal rows with
    /// negated `qty_change` are written; original rows stay in place so
    /// the trail is auditable.
    ///
    /// IDs are deterministic: `SLE-<stockEntryId>-<rowIndex>-<side>` (with
    /// `-reversal` suffix for cancellations) so re-firing the derivation
    /// upserts in place instead of duplicating.
    static let stockLedgerEntry = DocType(
        id: "StockLedgerEntry",
        name: "Stock Ledger Entry",
        module: "Stock",
        appId: HubManifest.appID,
        isChildTable: false,
        fields: [
            FieldDefinition(key: "item", label: "Item",
                            type: .link, required: true, linkedDocType: "Item"),
            FieldDefinition(key: "warehouse", label: "Warehouse",
                            type: .link, required: true, linkedDocType: "Warehouse"),
            FieldDefinition(key: "posting_date", label: "Posting Date",
                            type: .date, required: true),
            FieldDefinition(key: "posting_time", label: "Posting Time",
                            type: .datetime, required: false),
            FieldDefinition(key: "voucher_type", label: "Voucher Type",
                            type: .text, required: true),
            FieldDefinition(key: "voucher_no", label: "Voucher No",
                            type: .text, required: true, isSearchable: true),
            FieldDefinition(key: "qty_change", label: "Qty Change",
                            type: .decimal, required: true,
                            defaultValue: .double(0)),
            FieldDefinition(key: "valuation_rate", label: "Valuation Rate",
                            type: .currency, required: false),
            FieldDefinition(key: "amount", label: "Amount",
                            type: .currency, required: false,
                            formulaExpression: "qty_change * valuation_rate"),
            FieldDefinition(key: "is_reversal", label: "Reversal",
                            type: .boolean, required: false, defaultValue: .bool(false))
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [
            IndexDefinition(fieldKey: "voucher_no", unique: false),
            IndexDefinition(fieldKey: "item", unique: false),
            IndexDefinition(fieldKey: "warehouse", unique: false)
        ],
        searchFields: ["voucher_no", "item"],
        titleField: "voucher_no"
    )
}
