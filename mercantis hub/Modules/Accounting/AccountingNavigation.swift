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
            // Payments stay on the everyday surface.
            HubMenuGroup(label: "Payments", items: [
                .docType(Accounting.paymentEntry)
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
