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
            ])
        ]
    )
}
