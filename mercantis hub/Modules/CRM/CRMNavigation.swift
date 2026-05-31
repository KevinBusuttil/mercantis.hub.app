import MercantisCoreUI

extension CRM {
    static let module = HubModule(
        id: "crm",
        label: "Contacts",
        systemImage: "person.2",
        tone: .crm,
        groups: [
            HubMenuGroup(label: "Directory", items: [
                .docType(CRM.customer, label: "Customers"),
                .docType(Buying.supplier, label: "Suppliers"),
                .docType(CRM.contact, label: "Contacts"),
                .docType(CRM.address, label: "Addresses")
            ]),
            HubMenuGroup(label: "Sales Pipeline", items: [
                .docType(CRM.lead, label: "Leads")
            ])
        ]
    )
}
