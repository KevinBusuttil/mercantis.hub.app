import MercantisCore
import MercantisCoreUI

extension Stock {
    static let module = HubModule(
        id: "stock",
        label: "Stock",
        systemImage: "archivebox",
        tone: .stock,
        groups: [
            HubMenuGroup(label: "Masters", items: [
                .docType(Selling.item, label: "Items"),
                .docType(Setup.warehouse, label: "Warehouses")
            ]),
            HubMenuGroup(label: "Stock Movements", items: [
                .docType(Stock.stockEntry, label: "Stock Movements")
            ]),
            // Derived inventory availability — the normal user-facing
            // stock-on-hand surface (raw ledger stays advanced, below).
            HubMenuGroup(label: "Availability", items: [
                .docType(Stock.bin, label: "Stock Balance"),
                .report(id: HubReports.stockOnHand.id,
                        label: HubReports.stockOnHand.name)
            ]),
            // The Stock Ledger is the internal append-only audit table; it
            // powers the Stock Ledger View report, so it's hidden from the
            // primary surface and surfaced only in advanced mode.
            HubMenuGroup(label: "Stock Ledger", items: [
                .docType(Stock.stockLedgerEntry)
            ], visibility: .advanced),
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
