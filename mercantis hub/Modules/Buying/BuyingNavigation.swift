extension Buying {
    static let module = HubModule(
        id: "buying",
        label: "Buying",
        systemImage: "shippingbox",
        groups: [
            HubMenuGroup(label: "Suppliers", items: [
                .docType(Buying.supplier)
            ])
        ]
    )
}
