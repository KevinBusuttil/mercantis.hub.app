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

enum Setup {

    // MARK: - Tree masters

    static let customerGroup = DocType(
        id: "CustomerGroup",
        name: "Customer Group",
        module: "Setup",
        appId: HubManifest.appID,
        isChildTable: false,
        isTree: true,
        treeRootName: "All Customer Groups",
        fields: [
            FieldDefinition(key: "customer_group_name", label: "Customer Group Name",
                            type: .text, required: true, isSearchable: true),
            FieldDefinition(key: "parent_customer_group", label: "Parent Customer Group",
                            type: .link, required: false, linkedDocType: "CustomerGroup")
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["customer_group_name"],
        titleField: "customer_group_name"
    )

    static let territory = DocType(
        id: "Territory",
        name: "Territory",
        module: "Setup",
        appId: HubManifest.appID,
        isChildTable: false,
        isTree: true,
        treeRootName: "All Territories",
        fields: [
            FieldDefinition(key: "territory_name", label: "Territory Name",
                            type: .text, required: true, isSearchable: true),
            FieldDefinition(key: "parent_territory", label: "Parent Territory",
                            type: .link, required: false, linkedDocType: "Territory")
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["territory_name"],
        titleField: "territory_name"
    )

    static let itemGroup = DocType(
        id: "ItemGroup",
        name: "Item Group",
        module: "Setup",
        appId: HubManifest.appID,
        isChildTable: false,
        isTree: true,
        treeRootName: "All Item Groups",
        fields: [
            FieldDefinition(key: "item_group_name", label: "Item Group Name",
                            type: .text, required: true, isSearchable: true),
            FieldDefinition(key: "parent_item_group", label: "Parent Item Group",
                            type: .link, required: false, linkedDocType: "ItemGroup")
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["item_group_name"],
        titleField: "item_group_name"
    )

    static let supplierGroup = DocType(
        id: "SupplierGroup",
        name: "Supplier Group",
        module: "Setup",
        appId: HubManifest.appID,
        isChildTable: false,
        isTree: true,
        treeRootName: "All Supplier Groups",
        fields: [
            FieldDefinition(key: "supplier_group_name", label: "Supplier Group Name",
                            type: .text, required: true, isSearchable: true),
            FieldDefinition(key: "parent_supplier_group", label: "Parent Supplier Group",
                            type: .link, required: false, linkedDocType: "SupplierGroup")
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["supplier_group_name"],
        titleField: "supplier_group_name"
    )

    static let warehouse = DocType(
        id: "Warehouse",
        name: "Warehouse",
        module: "Setup",
        appId: HubManifest.appID,
        isChildTable: false,
        isTree: true,
        treeRootName: "All Warehouses",
        fields: [
            FieldDefinition(key: "warehouse_name", label: "Warehouse Name",
                            type: .text, required: true, isSearchable: true),
            FieldDefinition(key: "parent_warehouse", label: "Parent Warehouse",
                            type: .link, required: false, linkedDocType: "Warehouse"),
            FieldDefinition(key: "is_group", label: "Is Group", type: .boolean, required: false),
            FieldDefinition(key: "address_line1", label: "Address Line", type: .text, required: false),
            FieldDefinition(key: "city", label: "City", type: .text, required: false)
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["warehouse_name", "city"],
        titleField: "warehouse_name"
    )

    static let costCenter = DocType(
        id: "CostCenter",
        name: "Cost Center",
        module: "Setup",
        appId: HubManifest.appID,
        isChildTable: false,
        isTree: true,
        treeRootName: "All Cost Centers",
        fields: [
            FieldDefinition(key: "cost_center_name", label: "Cost Center Name",
                            type: .text, required: true, isSearchable: true),
            FieldDefinition(key: "parent_cost_center", label: "Parent Cost Center",
                            type: .link, required: false, linkedDocType: "CostCenter"),
            FieldDefinition(key: "is_group", label: "Is Group", type: .boolean, required: false)
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["cost_center_name"],
        titleField: "cost_center_name"
    )

    // MARK: - Flat masters

    /// Stocked currencies. ID format follows ISO 4217 ("EUR", "USD", "MTL").
    static let currency = DocType(
        id: "Currency",
        name: "Currency",
        module: "Setup",
        appId: HubManifest.appID,
        isChildTable: false,
        fields: [
            FieldDefinition(key: "currency_name", label: "Currency Name",
                            type: .text, required: true, isSearchable: true),
            FieldDefinition(key: "iso_code", label: "ISO 4217 Code",
                            type: .text, required: true, isSearchable: true),
            FieldDefinition(key: "symbol", label: "Symbol", type: .text, required: false),
            FieldDefinition(key: "smallest_unit", label: "Smallest Unit",
                            type: .decimal, required: false, defaultValue: .double(0.01)),
            FieldDefinition(key: "enabled", label: "Enabled",
                            type: .boolean, required: false, defaultValue: .bool(true))
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["currency_name", "iso_code"],
        titleField: "currency_name"
    )

    /// Unit of measure (UOM). Used by Item and stock-movement DocTypes.
    static let uom = DocType(
        id: "UOM",
        name: "UOM",
        module: "Setup",
        appId: HubManifest.appID,
        isChildTable: false,
        fields: [
            FieldDefinition(key: "uom_name", label: "UOM Name",
                            type: .text, required: true, isSearchable: true),
            FieldDefinition(key: "must_be_whole_number", label: "Must Be Whole Number",
                            type: .boolean, required: false, defaultValue: .bool(false)),
            FieldDefinition(key: "enabled", label: "Enabled",
                            type: .boolean, required: false, defaultValue: .bool(true))
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["uom_name"],
        titleField: "uom_name"
    )

    /// Brand for Items.
    static let brand = DocType(
        id: "Brand",
        name: "Brand",
        module: "Setup",
        appId: HubManifest.appID,
        isChildTable: false,
        fields: [
            FieldDefinition(key: "brand_name", label: "Brand Name",
                            type: .text, required: true, isSearchable: true),
            FieldDefinition(key: "description", label: "Description",
                            type: .longText, required: false)
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["brand_name"],
        titleField: "brand_name"
    )

    /// Price list. Per-customer-group / per-currency pricing reference.
    /// Item-level price rows live in the `items` child table (Wall 5).
    static let priceList = DocType(
        id: "PriceList",
        name: "Price List",
        module: "Setup",
        appId: HubManifest.appID,
        isChildTable: false,
        fields: [
            FieldDefinition(key: "price_list_name", label: "Price List Name",
                            type: .text, required: true, isSearchable: true),
            FieldDefinition(key: "currency", label: "Currency",
                            type: .link, required: true, linkedDocType: "Currency"),
            FieldDefinition(key: "buying", label: "Used for Buying",
                            type: .boolean, required: false, defaultValue: .bool(false)),
            FieldDefinition(key: "selling", label: "Used for Selling",
                            type: .boolean, required: false, defaultValue: .bool(true)),
            FieldDefinition(key: "enabled", label: "Enabled",
                            type: .boolean, required: false, defaultValue: .bool(true)),
            FieldDefinition(key: "items", label: "Item Rates",
                            type: .table, required: false, childDocType: "ItemPrice")
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["price_list_name"],
        titleField: "price_list_name"
    )

    /// One row inside a PriceList.items child table — the per-item rate
    /// for the parent price list. (Wall 5)
    static let itemPrice = DocType(
        id: "ItemPrice",
        name: "Item Price",
        module: "Setup",
        appId: HubManifest.appID,
        isChildTable: true,
        fields: [
            FieldDefinition(key: "item", label: "Item",
                            type: .link, required: true, linkedDocType: "Item"),
            FieldDefinition(key: "uom", label: "UOM",
                            type: .link, required: false, linkedDocType: "UOM"),
            FieldDefinition(key: "rate", label: "Rate",
                            type: .currency, required: true),
            FieldDefinition(key: "min_qty", label: "Min Qty",
                            type: .decimal, required: false, defaultValue: .double(0)),
            FieldDefinition(key: "valid_from", label: "Valid From",
                            type: .date, required: false),
            FieldDefinition(key: "valid_upto", label: "Valid Upto",
                            type: .date, required: false)
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: [],
        titleField: "item"
    )

    static let allDocTypes: [DocType] = [
        // Tree masters
        customerGroup,
        territory,
        itemGroup,
        supplierGroup,
        warehouse,
        costCenter,
        // Flat masters
        currency,
        uom,
        brand,
        priceList,
        // Child DocTypes
        itemPrice
    ]
}
