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

    static let allDocTypes: [DocType] = [customerGroup, territory, itemGroup]
}
