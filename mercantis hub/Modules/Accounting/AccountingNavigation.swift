import MercantisCore
import MercantisCoreUI

extension Accounting {
    static let module = HubModule(
        id: "accounting",
        label: "Money",
        systemImage: "creditcard",
        tone: .accounting,
        groups: [
            HubMenuGroup(label: "Chart of Accounts", items: [
                .docType(Accounting.account)
            ]),
            // Guided money flows stay on the everyday surface; the raw
            // Payment Entry list is for accountants who want the spine.
            HubMenuGroup(label: "Payments", items: [
                .flow(id: "guided-receive-payment", label: "Receive Payment",
                      systemImage: "tray.and.arrow.down"),
                .flow(id: "guided-pay-supplier", label: "Pay Supplier",
                      systemImage: "tray.and.arrow.up"),
                .docType(Accounting.paymentEntry, label: "All Payments")
            ]),
            HubMenuGroup(label: "Receivables", items: [
                .report(id: HubReports.customerAging.id,
                        label: "Customer Aging"),
                .report(id: HubReports.customerStatement.id,
                        label: "Customer Statement")
            ]),
            HubMenuGroup(label: "Payables", items: [
                .report(id: HubReports.supplierLedger.id,
                        label: "Supplier Ledger"),
                .report(id: HubReports.supplierAging.id,
                        label: "Supplier Aging")
            ]),
            HubMenuGroup(label: "Tax", items: [
                .report(id: HubReports.vatSummary.id,
                        label: HubReports.vatSummary.name)
            ]),
            // Journals are an accountant tool — hidden until advanced mode.
            HubMenuGroup(label: "Journals", items: [
                .docType(Accounting.journalEntry)
            ], visibility: .advanced),
            // Internal AX-style audit/ledger spine — kept (it powers balances,
            // statements, reports and reversals) but hidden by default.
            HubMenuGroup(label: "General Ledger", items: [
                .docType(Accounting.glEntry)
            ], visibility: .advanced),
            HubMenuGroup(label: "Customer & Supplier Transactions", items: [
                .docType(Accounting.custTrans),
                .docType(Accounting.vendTrans),
                .docType(Accounting.settlement),
                .docType(Accounting.taxTrans)
            ], visibility: .advanced),
            HubMenuGroup(label: "Reports", items: [
                .report(id: HubReports.trialBalance.id,
                        label: HubReports.trialBalance.name)
            ], visibility: .advanced),
            HubMenuGroup(label: "Dashboards", items: [
                .dashboard(id: HubDashboards.accountingOverview.id,
                           label: HubDashboards.accountingOverview.name)
            ])
        ]
    )
}
