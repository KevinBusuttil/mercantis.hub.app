import MercantisCore
import MercantisCoreUI

extension POS {
    static let module = HubModule(
        id: "pos",
        label: "POS",
        systemImage: "creditcard.and.123",
        tone: .selling,
        groups: [
            HubMenuGroup(label: "Till", items: [
                .flow(id: "pos-checkout", label: "Point of Sale", systemImage: "cart.badge.plus")
            ]),
            HubMenuGroup(label: "Records", items: [
                .docType(POS.posInvoice, label: "POS Sales"),
                .docType(POS.posSession, label: "Sessions")
            ]),
            HubMenuGroup(label: "Reports", items: [
                .report(id: HubReports.posXReport.id, label: HubReports.posXReport.name),
                .report(id: HubReports.posZReport.id, label: HubReports.posZReport.name),
                .report(id: HubReports.posShifts.id, label: HubReports.posShifts.name)
            ]),
            HubMenuGroup(label: "Setup", items: [
                .docType(POS.posProfile, label: "POS Profiles")
            ])
        ],
        requiresPOS: true
    )
}
