import MercantisCore
import MercantisCoreUI

extension Buying {
    static let module = HubModule(
        id: "buying",
        label: "Buy",
        systemImage: "shippingbox",
        tone: .buying,
        groups: [
            HubMenuGroup(label: "Transactions", items: [
                .docType(Buying.purchaseOrder, label: "Purchase Orders"),
                .docType(Buying.purchaseInvoice, label: "Purchase Invoices"),
                .flow(id: "guided-pay-supplier", label: "Pay Supplier",
                      systemImage: "tray.and.arrow.up")
            ]),
            HubMenuGroup(label: "Receiving", items: [
                .docType(Buying.purchaseReceipt, label: "Purchase Receipts"),
                .report(id: HubReports.purchaseOrdersToReceive.id,
                        label: HubReports.purchaseOrdersToReceive.name),
                .report(id: HubReports.pendingReceipts.id,
                        label: HubReports.pendingReceipts.name)
            ]),
            HubMenuGroup(label: "Procurement", items: [
                .docType(Buying.supplierQuotation, label: "Supplier Quotations")
            ], visibility: .advanced),
            HubMenuGroup(label: "Reports", items: [
                .report(id: HubReports.purchaseRegister.id,
                        label: HubReports.purchaseRegister.name)
            ])
        ]
    )
}
