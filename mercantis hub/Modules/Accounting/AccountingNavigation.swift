import MercantisCore

extension Accounting {
    static let module = HubModule(
        id: "accounting",
        label: "Accounting",
        systemImage: "creditcard",
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
