extension Selling {
    static let module = HubModule(
        id: "selling",
        label: "Selling",
        systemImage: "cart",
        groups: [
            HubMenuGroup(label: "Catalogue", items: [
                .docType(Selling.item)
            ]),
            HubMenuGroup(label: "Transactions", items: [
                .docType(Selling.quotation),
                .docType(Selling.salesOrder),
                .docType(Selling.salesInvoice)
            ])
        ]
    )
}
