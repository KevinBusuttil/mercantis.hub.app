extension Selling {
    static let module = HubModule(
        id: "selling",
        label: "Selling",
        systemImage: "cart",
        groups: [
            HubMenuGroup(label: "Catalogue", items: [
                .docType(Selling.item)
            ])
        ]
    )
}
