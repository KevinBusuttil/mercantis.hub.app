import MercantisCoreUI

extension CRM {
    static let module = HubModule(
        id: "crm",
        label: "CRM",
        systemImage: "person.2",
        tone: .crm,
        groups: [
            HubMenuGroup(label: "Masters", items: [
                .docType(CRM.customer),
                .docType(CRM.contact),
                .docType(CRM.address)
            ]),
            HubMenuGroup(label: "Sales Pipeline", items: [
                .docType(CRM.lead)
            ])
        ]
    )
}
