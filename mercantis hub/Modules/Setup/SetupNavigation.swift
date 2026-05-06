extension Setup {
    static let module = HubModule(
        id: "setup",
        label: "Setup",
        systemImage: "gearshape",
        groups: [
            HubMenuGroup(label: "Customer", items: [
                .docType(Setup.customerGroup),
                .docType(Setup.territory)
            ]),
            HubMenuGroup(label: "Supplier", items: [
                .docType(Setup.supplierGroup)
            ]),
            HubMenuGroup(label: "Item", items: [
                .docType(Setup.itemGroup),
                .docType(Setup.brand),
                .docType(Setup.uom)
            ]),
            HubMenuGroup(label: "Stock", items: [
                .docType(Setup.warehouse)
            ]),
            HubMenuGroup(label: "Accounting", items: [
                .docType(Setup.costCenter),
                .docType(Setup.currency),
                .docType(Setup.priceList)
            ])
        ]
    )
}
