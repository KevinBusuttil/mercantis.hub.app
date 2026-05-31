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
                .docType(Accounting.paymentEntry, label: "Pay Supplier")
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
