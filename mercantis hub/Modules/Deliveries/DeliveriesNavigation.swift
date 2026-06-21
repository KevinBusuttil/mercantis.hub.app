import MercantisCore
import MercantisCoreUI

extension Deliveries {
    static let module = HubModule(
        id: "deliveries",
        label: "Deliveries",
        systemImage: "truck.box",
        tone: .selling,
        groups: [
            HubMenuGroup(label: "Deliveries", items: [
                .docType(Deliveries.salesDelivery, label: "Sales Deliveries"),
                .report(id: HubReports.openDeliveries.id,
                        label: HubReports.openDeliveries.name)
            ]),
            HubMenuGroup(label: "Routes", items: [
                .docType(Deliveries.deliveryRoute, label: "Delivery Routes"),
                .report(id: HubReports.todaysRoutes.id,
                        label: HubReports.todaysRoutes.name),
                .flow(id: "driver-today", label: "Driver Today",
                      systemImage: "truck.box"),
                .flow(id: "delivery-route", label: "Route Stops",
                      systemImage: "map")
            ]),
            HubMenuGroup(label: "Fleet", items: [
                .docType(Deliveries.driver, label: "Drivers"),
                .docType(Deliveries.vehicle, label: "Vehicles")
            ]),
            HubMenuGroup(label: "Dashboards", items: [
                .dashboard(id: HubDashboards.deliveriesOverview.id,
                           label: HubDashboards.deliveriesOverview.name)
            ]),
            // Append-only status history — audit surface, hidden by default.
            HubMenuGroup(label: "Tracking", items: [
                .docType(Deliveries.deliveryStatusEvent, label: "Status Events")
            ], visibility: .advanced)
        ],
        requiresDeliveries: true
    )
}
