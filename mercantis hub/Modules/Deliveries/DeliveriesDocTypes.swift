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

/// Phase 4 — the customer-facing fulfilment layer. Sales Delivery (Delivery
/// Note) records goods physically sent to a customer, separate from the
/// financial Sales Invoice. It carries the delivery status lifecycle
/// (Draft → Scheduled → Loaded → Out for Delivery → Delivered / Failed) and
/// the minimal driver / vehicle / scheduled-date fields that the Phase 7
/// Delivery Routes module will build on. On submit it decrements stock at
/// each line's source warehouse via the Stock Ledger.
enum Deliveries {

    /// One delivered line. `warehouse` is the source the goods ship from;
    /// `valuation_rate` (cost) drives the stock value impact, while `rate`
    /// is the informational selling price.
    static let salesDeliveryItem = DocType(
        id: "SalesDeliveryItem",
        name: "Sales Delivery Item",
        module: "Deliveries",
        appId: HubManifest.appID,
        isChildTable: true,
        fields: [
            FieldDefinition(key: "item", label: "Item",
                            type: .link, required: true, linkedDocType: "Item"),
            FieldDefinition(key: "description", label: "Description",
                            type: .text, required: false,
                            fetchFrom: "item.description"),
            FieldDefinition(key: "qty", label: "Delivered Qty",
                            type: .decimal, required: true, defaultValue: .double(1)),
            FieldDefinition(key: "uom", label: "UOM",
                            type: .link, required: false, linkedDocType: "UOM"),
            FieldDefinition(key: "rate", label: "Rate",
                            type: .currency, required: false, defaultValue: .double(0)),
            FieldDefinition(key: "valuation_rate", label: "Valuation Rate",
                            type: .currency, required: false),
            FieldDefinition(key: "amount", label: "Amount",
                            type: .currency, required: false,
                            formulaExpression: "qty * rate"),
            FieldDefinition(key: "warehouse", label: "Warehouse",
                            type: .link, required: false, linkedDocType: "Warehouse"),
            FieldDefinition(key: "sales_order", label: "Sales Order",
                            type: .link, required: false, linkedDocType: "SalesOrder"),
            FieldDefinition(key: "sales_invoice", label: "Sales Invoice",
                            type: .link, required: false, linkedDocType: "SalesInvoice")
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: [],
        titleField: "item"
    )

    /// Sales Delivery / Delivery Note. Submittable so it flows through
    /// docStatus (and the Stock Ledger derivation) while its `status`
    /// tracks the physical delivery journey. Links back to the Sales Order
    /// / Sales Invoice it fulfils where practical.
    static let salesDelivery = DocType(
        id: "SalesDelivery",
        name: "Sales Delivery",
        module: "Deliveries",
        appId: HubManifest.appID,
        isChildTable: false,
        isSubmittable: true,
        fields: [
            FieldDefinition(key: "customer", label: "Customer",
                            type: .link, required: true, linkedDocType: "Customer"),
            FieldDefinition(key: "transaction_date", label: "Delivery Date",
                            type: .date, required: true),
            FieldDefinition(key: "sales_order", label: "Sales Order",
                            type: .link, required: false, linkedDocType: "SalesOrder"),
            FieldDefinition(key: "sales_invoice", label: "Sales Invoice",
                            type: .link, required: false, linkedDocType: "SalesInvoice"),
            FieldDefinition(key: "is_return", label: "Is Return (Goods In)",
                            type: .boolean, required: false, defaultValue: .bool(false)),
            FieldDefinition(key: "return_against", label: "Return Against",
                            type: .link, required: false, linkedDocType: "SalesDelivery"),
            FieldDefinition(key: "currency", label: "Currency",
                            type: .link, required: false, linkedDocType: "Currency"),
            FieldDefinition(key: "set_warehouse", label: "Default Warehouse",
                            type: .link, required: false, linkedDocType: "Warehouse"),
            // Route foundations (Phase 7 builds the routing module on these).
            FieldDefinition(key: "scheduled_date", label: "Scheduled Date",
                            type: .date, required: false, allowOnSubmit: true),
            FieldDefinition(key: "driver", label: "Driver",
                            type: .text, required: false, allowOnSubmit: true),
            FieldDefinition(key: "vehicle", label: "Vehicle",
                            type: .text, required: false, allowOnSubmit: true),
            // Set by DeliveryRouteService when this delivery is added to a
            // route as a stop (Phase 7). allowOnSubmit so they update on the
            // already-submitted delivery.
            FieldDefinition(key: "delivery_route", label: "Delivery Route",
                            type: .link, required: false, linkedDocType: "DeliveryRoute",
                            allowOnSubmit: true),
            FieldDefinition(key: "route_status", label: "Route Status",
                            type: .text, required: false, allowOnSubmit: true),
            FieldDefinition(key: "items", label: "Items",
                            type: .table, required: true, childDocType: "SalesDeliveryItem"),
            FieldDefinition(key: "total_qty", label: "Total Qty",
                            type: .decimal, required: false),
            FieldDefinition(key: "remarks", label: "Remarks",
                            type: .longText, required: false, allowOnSubmit: true)
        ],
        permissions: [systemManagerPermission],
        workflowId: "wf-sales-delivery",
        autoname: "naming_series:DN-.YYYY.-.####",
        syncPolicy: SyncPolicy(conflictResolution: .versionChecked, immutableAfterSubmit: true),
        indexes: [
            IndexDefinition(fieldKey: "customer", unique: false),
            IndexDefinition(fieldKey: "sales_order", unique: false)
        ],
        searchFields: ["customer"],
        titleField: "customer",
        formLayout: FormLayout(sections: [
            FormLayoutSection(
                key: "header",
                title: "Header",
                columns: 2,
                fieldKeys: ["customer", "transaction_date", "sales_order", "sales_invoice"]
            ),
            FormLayoutSection(
                key: "fulfilment",
                title: "Fulfilment",
                helpText: "Scheduling and driver details. The delivery status tracks the journey from Scheduled to Delivered.",
                columns: 2,
                fieldKeys: ["set_warehouse", "scheduled_date", "driver", "vehicle",
                            "delivery_route", "route_status"]
            ),
            FormLayoutSection(
                key: "items",
                title: "Items",
                helpText: "Submitting decreases stock at each line's warehouse.",
                fieldKeys: ["items"]
            ),
            FormLayoutSection(
                key: "totals",
                title: "Totals",
                fieldKeys: ["total_qty"]
            ),
            FormLayoutSection(
                key: "notes",
                title: "Notes",
                fieldKeys: ["remarks"]
            )
        ])
    )

    static let allDocTypes: [DocType] = [
        salesDeliveryItem,
        salesDelivery
    ] + routeDocTypes
}
