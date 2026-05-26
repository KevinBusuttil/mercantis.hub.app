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

private let submittableSyncPolicy = SyncPolicy(
    conflictResolution: .versionChecked,
    immutableAfterSubmit: true
)

private let masterSyncPolicy = SyncPolicy(
    conflictResolution: .lastWriteWins,
    immutableAfterSubmit: false
)

/// Manufacturing module — declarative DocType + FormLayout definitions.
///
/// Shape mirrors `Selling` / `Buying`: a child-table primer, then masters
/// (`Workstation`, `Operation`) that are referenced from transactional
/// documents, then the transactional parents (`BOM`, `WorkOrder`,
/// `JobCard`, `ProductionPlan`).
///
/// Runtime derivations (BOM cost rollup, Work Order → Stock Entry on
/// completion, Production Plan → Work Order auto-creation) live in
/// `ManufacturingDerivationService`. Workflow state machines live in
/// `HubWorkflows`. Navigation lives in `ManufacturingNavigation`.
enum Manufacturing {

    // MARK: - Child DocTypes

    /// One row inside `BOM.items` — a raw-material component plus its
    /// per-unit quantity and rate. `amount` is computed by formula
    /// (`qty * rate`); scrap percent is captured for informational use
    /// by future planning logic but does not currently feed the rollup.
    static let bomItem = DocType(
        id: "BOMItem",
        name: "BOM Item",
        module: "Manufacturing",
        appId: HubManifest.appID,
        isChildTable: true,
        fields: [
            FieldDefinition(key: "item", label: "Item",
                            type: .link, required: true, linkedDocType: "Item"),
            FieldDefinition(key: "description", label: "Description",
                            type: .text, required: false),
            FieldDefinition(key: "qty", label: "Quantity",
                            type: .decimal, required: true, defaultValue: .double(1)),
            FieldDefinition(key: "uom", label: "UOM",
                            type: .link, required: false, linkedDocType: "UOM"),
            FieldDefinition(key: "scrap_pct", label: "Scrap %",
                            type: .decimal, required: false, defaultValue: .double(0)),
            FieldDefinition(key: "rate", label: "Rate",
                            type: .currency, required: false, defaultValue: .double(0)),
            FieldDefinition(key: "amount", label: "Amount",
                            type: .currency, required: false,
                            formulaExpression: "qty * rate")
        ],
        permissions: [systemManagerPermission],
        syncPolicy: masterSyncPolicy,
        indexes: [],
        searchFields: [],
        titleField: "item"
    )

    /// One row inside `BOM.operations` — a routing step plus the time it
    /// takes and the workstation that performs it. `cost` is computed by
    /// formula (`(time_minutes / 60) * hour_rate`).
    static let bomOperation = DocType(
        id: "BOMOperation",
        name: "BOM Operation",
        module: "Manufacturing",
        appId: HubManifest.appID,
        isChildTable: true,
        fields: [
            FieldDefinition(key: "operation", label: "Operation",
                            type: .link, required: true, linkedDocType: "Operation"),
            FieldDefinition(key: "workstation", label: "Workstation",
                            type: .link, required: false, linkedDocType: "Workstation"),
            FieldDefinition(key: "time_minutes", label: "Time (min)",
                            type: .decimal, required: true, defaultValue: .double(0)),
            FieldDefinition(key: "hour_rate", label: "Hour Rate",
                            type: .currency, required: false, defaultValue: .double(0)),
            FieldDefinition(key: "cost", label: "Cost",
                            type: .currency, required: false,
                            formulaExpression: "(time_minutes / 60) * hour_rate")
        ],
        permissions: [systemManagerPermission],
        syncPolicy: masterSyncPolicy,
        indexes: [],
        searchFields: [],
        titleField: "operation"
    )

    /// One row inside `WorkOrder.required_items` — a raw-material
    /// requirement derived from the BOM at WO creation time. Transferred
    /// and consumed quantities are tracked separately so partial issues
    /// don't bury the underlying requirement.
    static let workOrderItem = DocType(
        id: "WorkOrderItem",
        name: "Work Order Item",
        module: "Manufacturing",
        appId: HubManifest.appID,
        isChildTable: true,
        fields: [
            FieldDefinition(key: "item", label: "Item",
                            type: .link, required: true, linkedDocType: "Item"),
            FieldDefinition(key: "required_qty", label: "Required Qty",
                            type: .decimal, required: true, defaultValue: .double(0)),
            FieldDefinition(key: "transferred_qty", label: "Transferred Qty",
                            type: .decimal, required: false, defaultValue: .double(0),
                            allowOnSubmit: true),
            FieldDefinition(key: "consumed_qty", label: "Consumed Qty",
                            type: .decimal, required: false, defaultValue: .double(0),
                            allowOnSubmit: true)
        ],
        permissions: [systemManagerPermission],
        syncPolicy: masterSyncPolicy,
        indexes: [],
        searchFields: [],
        titleField: "item"
    )

    /// One row inside `ProductionPlan.items_to_manufacture` — an item to
    /// produce, optionally pinned to a Sales Order whose demand it
    /// fulfils. When the parent plan submits, `ManufacturingDerivationService`
    /// creates one Draft `WorkOrder` per row.
    static let productionPlanItem = DocType(
        id: "ProductionPlanItem",
        name: "Production Plan Item",
        module: "Manufacturing",
        appId: HubManifest.appID,
        isChildTable: true,
        fields: [
            FieldDefinition(key: "item", label: "Item",
                            type: .link, required: true, linkedDocType: "Item"),
            FieldDefinition(key: "planned_qty", label: "Planned Qty",
                            type: .decimal, required: true, defaultValue: .double(1)),
            FieldDefinition(key: "bom", label: "BOM",
                            type: .link, required: false, linkedDocType: "BOM"),
            FieldDefinition(key: "against_sales_order", label: "Against Sales Order",
                            type: .link, required: false, linkedDocType: "SalesOrder")
        ],
        permissions: [systemManagerPermission],
        syncPolicy: masterSyncPolicy,
        indexes: [],
        searchFields: [],
        titleField: "item"
    )

    // MARK: - Masters

    /// A machine or station on the shop floor. Reusable across BOMs and
    /// Job Cards; `hour_rate` participates in BOM operation costing.
    static let workstation = DocType(
        id: "Workstation",
        name: "Workstation",
        module: "Manufacturing",
        appId: HubManifest.appID,
        isChildTable: false,
        fields: [
            FieldDefinition(key: "workstation_name", label: "Workstation Name",
                            type: .text, required: true, isSearchable: true),
            FieldDefinition(key: "hour_rate", label: "Hour Rate",
                            type: .currency, required: false, defaultValue: .double(0)),
            FieldDefinition(key: "location", label: "Location",
                            type: .text, required: false),
            FieldDefinition(key: "is_active", label: "Active",
                            type: .boolean, required: false, defaultValue: .bool(true)),
            FieldDefinition(key: "notes", label: "Notes",
                            type: .longText, required: false)
        ],
        permissions: [systemManagerPermission],
        autoname: "naming_series:WS-.####",
        syncPolicy: masterSyncPolicy,
        indexes: [],
        searchFields: ["workstation_name", "location"],
        titleField: "workstation_name",
        formLayout: FormLayout(sections: [
            FormLayoutSection(
                key: "identity", title: "Workstation", columns: 2,
                fieldKeys: ["workstation_name", "location", "hour_rate", "is_active"]
            ),
            FormLayoutSection(
                key: "notes", title: "Notes",
                fieldKeys: ["notes"]
            )
        ])
    )

    /// A reusable manufacturing step (e.g. Laser Cut, Weld, Powder Coat)
    /// with default routing metadata that BOMs and Job Cards can inherit.
    static let operation = DocType(
        id: "Operation",
        name: "Operation",
        module: "Manufacturing",
        appId: HubManifest.appID,
        isChildTable: false,
        fields: [
            FieldDefinition(key: "operation_name", label: "Operation Name",
                            type: .text, required: true, isSearchable: true),
            FieldDefinition(key: "description", label: "Description",
                            type: .longText, required: false),
            FieldDefinition(key: "default_workstation", label: "Default Workstation",
                            type: .link, required: false, linkedDocType: "Workstation"),
            FieldDefinition(key: "default_time_minutes", label: "Default Time (min)",
                            type: .decimal, required: false, defaultValue: .double(0))
        ],
        permissions: [systemManagerPermission],
        autoname: "naming_series:OP-.####",
        syncPolicy: masterSyncPolicy,
        indexes: [],
        searchFields: ["operation_name"],
        titleField: "operation_name",
        formLayout: FormLayout(sections: [
            FormLayoutSection(
                key: "identity", title: "Operation", columns: 2,
                fieldKeys: ["operation_name", "default_workstation",
                            "default_time_minutes"]
            ),
            FormLayoutSection(
                key: "details", title: "Details",
                fieldKeys: ["description"]
            )
        ])
    )

    // MARK: - BOM

    /// Bill of Materials — the recipe for producing N units of a finished
    /// `Item`. Submittable; once submitted the rollup costs and child
    /// rows are immutable per `submittableSyncPolicy`. `ManufacturingDerivation`
    /// recomputes `raw_material_cost` / `operating_cost` / `total_cost`
    /// on every save while the BOM is still in Draft.
    static let bom = DocType(
        id: "BOM",
        name: "BOM",
        module: "Manufacturing",
        appId: HubManifest.appID,
        isChildTable: false,
        isSubmittable: true,
        fields: [
            FieldDefinition(key: "item", label: "Item",
                            type: .link, required: true, linkedDocType: "Item"),
            FieldDefinition(key: "qty", label: "Quantity",
                            type: .decimal, required: true, defaultValue: .double(1)),
            FieldDefinition(key: "uom", label: "UOM",
                            type: .link, required: false, linkedDocType: "UOM"),
            FieldDefinition(key: "is_default", label: "Default for Item",
                            type: .boolean, required: false, defaultValue: .bool(false)),
            FieldDefinition(key: "is_active", label: "Active",
                            type: .boolean, required: false, defaultValue: .bool(true)),
            FieldDefinition(key: "items", label: "Items",
                            type: .table, required: true, childDocType: "BOMItem"),
            FieldDefinition(key: "operations", label: "Operations",
                            type: .table, required: false, childDocType: "BOMOperation"),
            FieldDefinition(key: "raw_material_cost", label: "Raw-Material Cost",
                            type: .currency, required: false),
            FieldDefinition(key: "operating_cost", label: "Operating Cost",
                            type: .currency, required: false),
            FieldDefinition(key: "total_cost", label: "Total Cost",
                            type: .currency, required: false),
            FieldDefinition(key: "notes", label: "Notes",
                            type: .longText, required: false, allowOnSubmit: true)
        ],
        permissions: [systemManagerPermission],
        workflowId: "wf-bom",
        autoname: "naming_series:BOM-.YYYY.-.####",
        syncPolicy: submittableSyncPolicy,
        indexes: [],
        searchFields: ["item"],
        titleField: "item",
        formLayout: FormLayout(sections: [
            FormLayoutSection(
                key: "header", title: "Header", columns: 2,
                fieldKeys: ["item", "qty", "uom", "is_default", "is_active"]
            ),
            FormLayoutSection(
                key: "items", title: "Items",
                helpText: "Raw materials consumed per `qty` units of the finished item.",
                fieldKeys: ["items"]
            ),
            FormLayoutSection(
                key: "operations", title: "Operations",
                helpText: "Routing steps required to produce the finished item.",
                fieldKeys: ["operations"]
            ),
            FormLayoutSection(
                key: "costing", title: "Costing",
                helpText: "Rolled up automatically from items + operations on save.",
                columns: 2,
                fieldKeys: ["raw_material_cost", "operating_cost", "total_cost"]
            ),
            FormLayoutSection(
                key: "notes", title: "Notes",
                fieldKeys: ["notes"]
            )
        ])
    )

    // MARK: - WorkOrder

    /// Work Order — instance of producing `qty_to_produce` of `item`
    /// using `bom`. `wf-work-order` advances Draft → Submitted →
    /// InProgress → Completed; on entering "Completed" the
    /// `ManufacturingDerivationService` posts a "Manufacturing" Stock
    /// Entry that consumes the required raw materials from
    /// `source_warehouse` and produces the finished goods into
    /// `target_warehouse`.
    static let workOrder = DocType(
        id: "WorkOrder",
        name: "Work Order",
        module: "Manufacturing",
        appId: HubManifest.appID,
        isChildTable: false,
        isSubmittable: true,
        fields: [
            FieldDefinition(key: "item", label: "Item to Produce",
                            type: .link, required: true, linkedDocType: "Item"),
            FieldDefinition(key: "bom", label: "BOM",
                            type: .link, required: true, linkedDocType: "BOM"),
            FieldDefinition(key: "qty_to_produce", label: "Qty to Produce",
                            type: .decimal, required: true, defaultValue: .double(1)),
            FieldDefinition(key: "uom", label: "UOM",
                            type: .link, required: false, linkedDocType: "UOM"),
            FieldDefinition(key: "source_warehouse", label: "Source Warehouse",
                            type: .link, required: true, linkedDocType: "Warehouse"),
            FieldDefinition(key: "target_warehouse", label: "Target Warehouse",
                            type: .link, required: true, linkedDocType: "Warehouse"),
            FieldDefinition(key: "planned_start", label: "Planned Start",
                            type: .date, required: false),
            FieldDefinition(key: "planned_end", label: "Planned End",
                            type: .date, required: false),
            FieldDefinition(key: "required_items", label: "Required Items",
                            type: .table, required: false, childDocType: "WorkOrderItem",
                            allowOnSubmit: true),
            FieldDefinition(key: "produced_qty", label: "Produced Qty",
                            type: .decimal, required: false, defaultValue: .double(0),
                            allowOnSubmit: true),
            FieldDefinition(key: "against_sales_order", label: "Against Sales Order",
                            type: .link, required: false, linkedDocType: "SalesOrder"),
            FieldDefinition(key: "against_production_plan", label: "Against Production Plan",
                            type: .link, required: false, linkedDocType: "ProductionPlan"),
            FieldDefinition(key: "notes", label: "Notes",
                            type: .longText, required: false, allowOnSubmit: true)
        ],
        permissions: [systemManagerPermission],
        workflowId: "wf-work-order",
        autoname: "naming_series:WO-.YYYY.-.####",
        syncPolicy: submittableSyncPolicy,
        indexes: [],
        searchFields: ["item"],
        titleField: "item",
        formLayout: FormLayout(sections: [
            FormLayoutSection(
                key: "header", title: "Header", columns: 2,
                fieldKeys: ["item", "bom", "qty_to_produce", "uom"]
            ),
            FormLayoutSection(
                key: "warehouses", title: "Warehouses",
                helpText: "Raw materials are consumed from Source; finished goods are produced into Target.",
                columns: 2,
                fieldKeys: ["source_warehouse", "target_warehouse"]
            ),
            FormLayoutSection(
                key: "schedule", title: "Schedule", columns: 2,
                fieldKeys: ["planned_start", "planned_end"]
            ),
            FormLayoutSection(
                key: "required_items", title: "Required Items",
                helpText: "Derived from the BOM. Update transferred / consumed quantities as the floor consumes them.",
                fieldKeys: ["required_items"]
            ),
            FormLayoutSection(
                key: "progress", title: "Progress", columns: 2,
                fieldKeys: ["produced_qty"]
            ),
            FormLayoutSection(
                key: "links", title: "Linked Documents", columns: 2,
                fieldKeys: ["against_sales_order", "against_production_plan"]
            ),
            FormLayoutSection(
                key: "notes", title: "Notes",
                fieldKeys: ["notes"]
            )
        ])
    )

    // MARK: - JobCard

    /// Job Card — time-tracking record for one operation of one Work
    /// Order. Multiple Job Cards per Work Order are expected when the
    /// BOM has multiple operations or when the same operation runs
    /// across multiple shifts.
    static let jobCard = DocType(
        id: "JobCard",
        name: "Job Card",
        module: "Manufacturing",
        appId: HubManifest.appID,
        isChildTable: false,
        isSubmittable: true,
        fields: [
            FieldDefinition(key: "work_order", label: "Work Order",
                            type: .link, required: true, linkedDocType: "WorkOrder"),
            FieldDefinition(key: "operation", label: "Operation",
                            type: .link, required: true, linkedDocType: "Operation"),
            FieldDefinition(key: "workstation", label: "Workstation",
                            type: .link, required: false, linkedDocType: "Workstation"),
            FieldDefinition(key: "planned_time_minutes", label: "Planned Time (min)",
                            type: .decimal, required: false, defaultValue: .double(0)),
            FieldDefinition(key: "actual_time_minutes", label: "Actual Time (min)",
                            type: .decimal, required: false, defaultValue: .double(0),
                            allowOnSubmit: true),
            FieldDefinition(key: "completed_qty", label: "Completed Qty",
                            type: .decimal, required: false, defaultValue: .double(0),
                            allowOnSubmit: true),
            FieldDefinition(key: "started_at", label: "Started",
                            type: .datetime, required: false, allowOnSubmit: true),
            FieldDefinition(key: "finished_at", label: "Finished",
                            type: .datetime, required: false, allowOnSubmit: true),
            FieldDefinition(key: "notes", label: "Notes",
                            type: .longText, required: false, allowOnSubmit: true)
        ],
        permissions: [systemManagerPermission],
        workflowId: "wf-job-card",
        autoname: "naming_series:JC-.YYYY.-.####",
        syncPolicy: submittableSyncPolicy,
        indexes: [],
        searchFields: ["work_order", "operation"],
        titleField: "work_order",
        formLayout: FormLayout(sections: [
            FormLayoutSection(
                key: "header", title: "Header", columns: 2,
                fieldKeys: ["work_order", "operation", "workstation"]
            ),
            FormLayoutSection(
                key: "timing", title: "Timing", columns: 2,
                fieldKeys: ["planned_time_minutes", "actual_time_minutes",
                            "started_at", "finished_at"]
            ),
            FormLayoutSection(
                key: "progress", title: "Progress", columns: 2,
                fieldKeys: ["completed_qty"]
            ),
            FormLayoutSection(
                key: "notes", title: "Notes",
                fieldKeys: ["notes"]
            )
        ])
    )

    // MARK: - ProductionPlan

    /// Production Plan — aggregate planning document. Lists the items to
    /// manufacture (optionally pinned to Sales Order demand) and, on
    /// submit, kicks off one Draft `WorkOrder` per row via
    /// `ManufacturingDerivationService`.
    static let productionPlan = DocType(
        id: "ProductionPlan",
        name: "Production Plan",
        module: "Manufacturing",
        appId: HubManifest.appID,
        isChildTable: false,
        isSubmittable: true,
        fields: [
            FieldDefinition(key: "plan_name", label: "Plan Name",
                            type: .text, required: true, isSearchable: true),
            FieldDefinition(key: "planning_date", label: "Planning Date",
                            type: .date, required: true),
            FieldDefinition(key: "default_source_warehouse", label: "Default Source Warehouse",
                            type: .link, required: false, linkedDocType: "Warehouse"),
            FieldDefinition(key: "default_target_warehouse", label: "Default Target Warehouse",
                            type: .link, required: false, linkedDocType: "Warehouse"),
            FieldDefinition(key: "items_to_manufacture", label: "Items to Manufacture",
                            type: .table, required: true, childDocType: "ProductionPlanItem"),
            FieldDefinition(key: "notes", label: "Notes",
                            type: .longText, required: false, allowOnSubmit: true)
        ],
        permissions: [systemManagerPermission],
        workflowId: "wf-production-plan",
        autoname: "naming_series:PP-.YYYY.-.####",
        syncPolicy: submittableSyncPolicy,
        indexes: [],
        searchFields: ["plan_name"],
        titleField: "plan_name",
        formLayout: FormLayout(sections: [
            FormLayoutSection(
                key: "header", title: "Header", columns: 2,
                fieldKeys: ["plan_name", "planning_date"]
            ),
            FormLayoutSection(
                key: "defaults", title: "Default Warehouses",
                helpText: "Pre-fills source / target on each auto-created Work Order.",
                columns: 2,
                fieldKeys: ["default_source_warehouse", "default_target_warehouse"]
            ),
            FormLayoutSection(
                key: "items", title: "Items to Manufacture",
                fieldKeys: ["items_to_manufacture"]
            ),
            FormLayoutSection(
                key: "notes", title: "Notes",
                fieldKeys: ["notes"]
            )
        ])
    )

    // MARK: - Registration

    /// Install order matters: child DocTypes first (their parents
    /// reference them via `childDocType: ...`), then masters, then
    /// transactional parents. Matches the pattern in `Selling` and
    /// `Buying`.
    static let allDocTypes: [DocType] = [
        // Child DocTypes first
        bomItem, bomOperation, workOrderItem, productionPlanItem,
        // Masters
        workstation, operation,
        // Transactional parents
        bom, workOrder, jobCard, productionPlan
    ]
}
