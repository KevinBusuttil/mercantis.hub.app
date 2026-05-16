extension Stock {
    static let module = HubModule(
        id: "stock",
        label: "Stock",
        systemImage: "archivebox",
        groups: [
            HubMenuGroup(label: "Movements", items: [
                .docType(Stock.stockEntry)
            ]),
            HubMenuGroup(label: "Ledger", items: [
                .docType(Stock.stockLedgerEntry)
            ]),
            HubMenuGroup(label: "Reports", items: [
                .report(id: HubReports.stockLedgerView.id,
                        label: HubReports.stockLedgerView.name)
            ]),
            HubMenuGroup(label: "Dashboards", items: [
                .dashboard(id: HubDashboards.inventoryOverview.id,
                           label: HubDashboards.inventoryOverview.name)
            ])
        ]
    )
}
