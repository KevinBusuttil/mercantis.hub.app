extension Setup {
    static let module = HubModule(
        id: "setup",
        label: "Setup",
        systemImage: "gearshape",
        groups: [
            HubMenuGroup(label: "Masters", items: [
                .docType(Setup.customerGroup),
                .docType(Setup.territory),
                .docType(Setup.itemGroup)
            ])
        ]
    )
}
