import MercantisCore

/// Phase 7 — Delivery Routes & Tracking. Manual route planning on top of the
/// Phase 4 Sales Delivery fulfilment layer: group deliveries into a dated
/// route, assign a driver + vehicle, sequence the stops, and track each stop
/// from Pending through Delivered / Failed. `DeliveryRouteService` reacts to
/// route saves to mirror each stop's status onto its Sales Delivery and to
/// append an append-only Delivery Status Event history.
///
/// No route optimisation, maps, GPS, or mobile app in v1 (per the epic).
extension Deliveries {

    private static let routePermission = PermissionRule(
        role: "System Manager",
        canRead: true, canWrite: true, canCreate: true,
        canDelete: true, canSubmit: false, canAmend: false
    )

    /// The status values a single stop moves through. Shared so the report,
    /// service, and tests agree on the vocabulary.
    static let stopStatuses = [
        "Pending", "Loaded", "Out for Delivery", "Delivered", "Failed", "Rescheduled",
    ]

    // MARK: - Fleet masters

    static let driver = DocType(
        id: "Driver",
        name: "Driver",
        module: "Deliveries",
        appId: HubManifest.appID,
        isChildTable: false,
        fields: [
            FieldDefinition(key: "driver_name", label: "Driver Name",
                            type: .text, required: true, isSearchable: true),
            FieldDefinition(key: "phone", label: "Phone", type: .phone, required: false),
            FieldDefinition(key: "license_no", label: "Licence No", type: .text, required: false),
            FieldDefinition(key: "enabled", label: "Enabled",
                            type: .boolean, required: false, defaultValue: .bool(true))
        ],
        permissions: [routePermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["driver_name"],
        titleField: "driver_name"
    )

    static let vehicle = DocType(
        id: "Vehicle",
        name: "Vehicle",
        module: "Deliveries",
        appId: HubManifest.appID,
        isChildTable: false,
        fields: [
            FieldDefinition(key: "vehicle_name", label: "Vehicle / Plate",
                            type: .text, required: true, isSearchable: true),
            FieldDefinition(key: "model", label: "Model", type: .text, required: false),
            FieldDefinition(key: "capacity", label: "Capacity", type: .number, required: false),
            FieldDefinition(key: "enabled", label: "Enabled",
                            type: .boolean, required: false, defaultValue: .bool(true))
        ],
        permissions: [routePermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["vehicle_name"],
        titleField: "vehicle_name"
    )

    // MARK: - Route stop (child)

    /// One stop on a route: a Sales Delivery plus its manual sequence and a
    /// per-stop status. `pod_note` / `pod_image` are the proof-of-delivery
    /// placeholders (no capture flow in v1).
    static let deliveryRouteStop = DocType(
        id: "DeliveryRouteStop",
        name: "Delivery Route Stop",
        module: "Deliveries",
        appId: HubManifest.appID,
        isChildTable: true,
        fields: [
            FieldDefinition(key: "sequence", label: "Seq",
                            type: .number, required: false, defaultValue: .int(1)),
            FieldDefinition(key: "sales_delivery", label: "Sales Delivery",
                            type: .link, required: true, linkedDocType: "SalesDelivery"),
            FieldDefinition(key: "customer", label: "Customer",
                            type: .link, required: false, linkedDocType: "Customer"),
            FieldDefinition(key: "address", label: "Address", type: .text, required: false),
            FieldDefinition(key: "status", label: "Status",
                            type: .select, required: false, defaultValue: .string("Pending"),
                            options: stopStatuses),
            FieldDefinition(key: "pod_note", label: "Delivery Note", type: .text, required: false),
            FieldDefinition(key: "pod_image", label: "Proof of Delivery",
                            type: .attachment, required: false)
        ],
        permissions: [routePermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: [],
        titleField: "sales_delivery"
    )

    // MARK: - Delivery Route (parent)

    /// A dated route. Status is a simple select (Draft → Dispatched →
    /// Completed / Cancelled) — manual planning, no ledger impact, so it is
    /// not submittable.
    static let deliveryRoute = DocType(
        id: "DeliveryRoute",
        name: "Delivery Route",
        module: "Deliveries",
        appId: HubManifest.appID,
        isChildTable: false,
        fields: [
            FieldDefinition(key: "route_date", label: "Route Date",
                            type: .date, required: true, isSearchable: true),
            FieldDefinition(key: "route_name", label: "Route Name", type: .text, required: false),
            FieldDefinition(key: "driver", label: "Driver",
                            type: .link, required: false, linkedDocType: "Driver"),
            FieldDefinition(key: "vehicle", label: "Vehicle",
                            type: .link, required: false, linkedDocType: "Vehicle"),
            FieldDefinition(key: "status", label: "Status",
                            type: .select, required: false, defaultValue: .string("Draft"),
                            options: ["Draft", "Dispatched", "Completed", "Cancelled"]),
            FieldDefinition(key: "stops", label: "Stops",
                            type: .table, required: false, childDocType: "DeliveryRouteStop"),
            FieldDefinition(key: "notes", label: "Notes", type: .longText, required: false)
        ],
        permissions: [routePermission],
        autoname: "naming_series:ROUTE-.YYYY.-.####",
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [
            IndexDefinition(fieldKey: "route_date", unique: false),
            IndexDefinition(fieldKey: "status", unique: false)
        ],
        searchFields: ["route_name", "route_date"],
        titleField: "route_name",
        formLayout: FormLayout(sections: [
            FormLayoutSection(key: "header", title: "Route", columns: 2,
                              fieldKeys: ["route_date", "route_name", "driver", "vehicle", "status"]),
            FormLayoutSection(key: "stops", title: "Stops",
                              helpText: "Add Sales Deliveries as stops, set their order, and update each stop's status as the round progresses.",
                              fieldKeys: ["stops"]),
            FormLayoutSection(key: "notes", title: "Notes", fieldKeys: ["notes"])
        ])
    )

    // MARK: - Status event (append-only history)

    /// Append-only record of each stop status change. Written by
    /// `DeliveryRouteService` when a route is saved and a stop's status
    /// differs from its last recorded event.
    static let deliveryStatusEvent = DocType(
        id: "DeliveryStatusEvent",
        name: "Delivery Status Event",
        module: "Deliveries",
        appId: HubManifest.appID,
        isChildTable: false,
        fields: [
            FieldDefinition(key: "delivery_route", label: "Delivery Route",
                            type: .link, required: false, linkedDocType: "DeliveryRoute"),
            FieldDefinition(key: "sales_delivery", label: "Sales Delivery",
                            type: .link, required: false, linkedDocType: "SalesDelivery", isSearchable: true),
            FieldDefinition(key: "stop_sequence", label: "Seq", type: .number, required: false),
            FieldDefinition(key: "status", label: "Status", type: .text, required: true),
            FieldDefinition(key: "event_time", label: "Time", type: .datetime, required: false),
            FieldDefinition(key: "note", label: "Note", type: .text, required: false)
        ],
        permissions: [routePermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [
            IndexDefinition(fieldKey: "delivery_route", unique: false),
            IndexDefinition(fieldKey: "sales_delivery", unique: false)
        ],
        searchFields: ["sales_delivery"],
        titleField: "status"
    )

    static let routeDocTypes: [DocType] = [
        deliveryRouteStop,
        driver,
        vehicle,
        deliveryRoute,
        deliveryStatusEvent
    ]
}
