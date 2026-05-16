extension Buying {
    static let module = HubModule(
        id: "buying",
        label: "Buying",
        systemImage: "shippingbox",
        groups: [
            HubMenuGroup(label: "Suppliers", items: [
                .docType(Buying.supplier)
            ]),
            HubMenuGroup(label: "Transactions", items: [
                .docType(Buying.supplierQuotation),
                .docType(Buying.purchaseOrder),
                .docType(Buying.purchaseInvoice)
            ]),
            HubMenuGroup(label: "Reports", items: [
                .report(id: HubReports.purchaseRegister.id,
                        label: HubReports.purchaseRegister.name)
            ])
        ]
    )
}
