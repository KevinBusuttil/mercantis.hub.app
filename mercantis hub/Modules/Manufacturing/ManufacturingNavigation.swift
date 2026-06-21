import MercantisCore
import MercantisCoreUI

extension Manufacturing {
    static let module = HubModule(
        id: "manufacturing",
        label: "Manufacturing",
        systemImage: "gearshape.2",
        tone: .manufacturing,
        groups: [
            HubMenuGroup(label: "Masters", items: [
                .docType(Manufacturing.workstation),
                .docType(Manufacturing.operation),
                .docType(Manufacturing.bom)
            ]),
            HubMenuGroup(label: "Production", items: [
                .docType(Manufacturing.productionPlan),
                .docType(Manufacturing.workOrder),
                .docType(Manufacturing.jobCard),
                .flow(id: "work-order-complete", label: "Complete Work Order",
                      systemImage: "hammer")
            ]),
            HubMenuGroup(label: "Dashboards", items: [
                .dashboard(id: HubDashboards.manufacturingOverview.id,
                           label: HubDashboards.manufacturingOverview.name)
            ])
        ],
        // Manufacturing is optional — surfaced only when the Light
        // Manufacturing preset (or its capability toggle) is enabled.
        requiresManufacturing: true
    )
}
