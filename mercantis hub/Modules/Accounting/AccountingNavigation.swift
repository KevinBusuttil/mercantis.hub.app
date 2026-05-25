import MercantisCore
import MercantisCoreUI

extension Accounting {
    static let module = HubModule(
        id: "accounting",
        label: "Accounting",
        systemImage: "creditcard",
        tone: .accounting,
        groups: [
            HubMenuGroup(label: "Chart", items: [
                .docType(Accounting.account)
            ]),
            HubMenuGroup(label: "Vouchers", items: [
                .docType(Accounting.journalEntry),
                .docType(Accounting.paymentEntry)
            ]),
            HubMenuGroup(label: "Ledger", items: [
                .docType(Accounting.glEntry)
            ]),
            HubMenuGroup(label: "Subledgers", items: [
                .docType(Accounting.custTrans),
                .docType(Accounting.vendTrans),
                .docType(Accounting.settlement),
                .docType(Accounting.taxTrans)
            ]),
            HubMenuGroup(label: "Reports", items: [
                .report(id: HubReports.trialBalance.id,
                        label: HubReports.trialBalance.name)
            ]),
            HubMenuGroup(label: "Dashboards", items: [
                .dashboard(id: HubDashboards.accountingOverview.id,
                           label: HubDashboards.accountingOverview.name)
            ])
        ]
    )
}
