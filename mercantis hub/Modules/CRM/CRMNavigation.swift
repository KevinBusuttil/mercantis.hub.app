extension CRM {
    static let module = HubModule(
        id: "crm",
        label: "CRM",
        systemImage: "person.2",
        groups: [
            HubMenuGroup(label: "Masters", items: [
                .docType(CRM.customer)
            ])
        ]
    )
}
