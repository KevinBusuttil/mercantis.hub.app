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

enum Selling {

    /// Item is the canonical sellable / stockable thing. Wall 4 unlocks
    /// the link fields (`item_group`, `brand`, `stock_uom`,
    /// `default_warehouse`); UOM-conversion rows, supplier rows, and
    /// item-price rows wait for Wall 5 (child tables).
    static let item = DocType(
        id: "Item",
        name: "Item",
        module: "Selling",
        appId: HubManifest.appID,
        isChildTable: false,
        fields: [
            FieldDefinition(key: "item_code", label: "Item Code",
                            type: .text, required: true, isSearchable: true),
            FieldDefinition(key: "item_name", label: "Item Name",
                            type: .text, required: true, isSearchable: true),
            FieldDefinition(key: "item_group", label: "Item Group",
                            type: .link, required: true, linkedDocType: "ItemGroup"),
            FieldDefinition(key: "brand", label: "Brand",
                            type: .link, required: false, linkedDocType: "Brand"),
            FieldDefinition(key: "stock_uom", label: "Default UOM",
                            type: .link, required: true, linkedDocType: "UOM"),
            FieldDefinition(key: "default_warehouse", label: "Default Warehouse",
                            type: .link, required: false, linkedDocType: "Warehouse"),
            FieldDefinition(key: "is_stock_item", label: "Track Stock",
                            type: .boolean, required: false, defaultValue: .bool(true)),
            FieldDefinition(key: "is_sales_item", label: "Sales Item",
                            type: .boolean, required: false, defaultValue: .bool(true)),
            FieldDefinition(key: "is_purchase_item", label: "Purchase Item",
                            type: .boolean, required: false, defaultValue: .bool(true)),
            FieldDefinition(key: "standard_rate", label: "Standard Selling Rate",
                            type: .currency, required: false),
            FieldDefinition(key: "barcode", label: "Barcode",
                            type: .barcode, required: false, isSearchable: true),
            FieldDefinition(key: "image", label: "Item Image",
                            type: .image, required: false),
            FieldDefinition(key: "description", label: "Description",
                            type: .longText, required: false)
        ],
        permissions: [systemManagerPermission],
        autoname: "naming_series:ITEM-.####",
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["item_code", "item_name", "barcode"],
        titleField: "item_name",
        formLayout: FormLayout(sections: [
            FormLayoutSection(
                key: "identity",
                title: "Item",
                fieldKeys: ["item_code", "item_name", "item_group", "brand"]
            ),
            FormLayoutSection(
                key: "stock",
                title: "Stock",
                helpText: "How this item is measured and where it normally lives.",
                fieldKeys: ["stock_uom", "default_warehouse", "is_stock_item"]
            ),
            FormLayoutSection(
                key: "transactions",
                title: "Transactions",
                helpText: "Which kinds of transactions this item participates in.",
                fieldKeys: ["is_sales_item", "is_purchase_item", "standard_rate"]
            ),
            FormLayoutSection(
                key: "media",
                title: "Media",
                fieldKeys: ["barcode", "image", "description"]
            )
        ])
    )

    static let allDocTypes: [DocType] = [item]
}
