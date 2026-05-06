extension Stock {
    static let module = HubModule(
        id: "stock",
        label: "Stock",
        systemImage: "archivebox",
        groups: [
            HubMenuGroup(label: "Movements", items: [
                .docType(Stock.stockEntry)
            ])
        ]
    )
}
