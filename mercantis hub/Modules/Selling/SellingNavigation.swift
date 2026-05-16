import MercantisCore

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
            ]),
            HubMenuGroup(label: "Reports", items: [
                .report(id: HubReports.salesRegister.id,
                        label: HubReports.salesRegister.name),
                .report(id: HubReports.customerAging.id,
                        label: HubReports.customerAging.name),
                .report(id: HubReports.customerStatement.id,
                        label: HubReports.customerStatement.name)
            ]),
            HubMenuGroup(label: "Dashboards", items: [
                .dashboard(id: HubDashboards.salesOverview.id,
                           label: HubDashboards.salesOverview.name)
            ])
        ]
    )
}
