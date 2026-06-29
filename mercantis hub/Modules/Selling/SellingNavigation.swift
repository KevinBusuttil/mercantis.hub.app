import MercantisCore
import MercantisCoreUI

extension Selling {
    static let module = HubModule(
        id: "selling",
        label: "Sell",
        systemImage: "cart",
        tone: .selling,
        groups: [
            HubMenuGroup(label: "Transactions", items: [
                .docType(Selling.quotation, label: "Quotes"),
                .docType(Selling.salesOrder, label: "Sales Orders"),
                .docType(Selling.salesInvoice, label: "Sales Invoices"),
                .flow(id: "guided-receive-payment", label: "Receive Payment",
                      systemImage: "tray.and.arrow.down")
            ]),
            HubMenuGroup(label: "Operations", items: [
                .flow(id: "sales-orders", label: "Sales Order Board",
                      systemImage: "cart"),
                .flow(id: "customer-account", label: "Customer Accounts",
                      systemImage: "person.2")
            ]),
            HubMenuGroup(label: "Reports", items: [
                .report(id: HubReports.salesRegister.id,
                        label: HubReports.salesRegister.name),
                .report(id: HubReports.salesOrdersToDeliver.id,
                        label: HubReports.salesOrdersToDeliver.name),
                .report(id: HubReports.customerAging.id,
                        label: HubReports.customerAging.name)
            ]),
            HubMenuGroup(label: "Dashboards", items: [
                .dashboard(id: HubDashboards.salesOverview.id,
                           label: HubDashboards.salesOverview.name)
            ])
        ]
    )
}
