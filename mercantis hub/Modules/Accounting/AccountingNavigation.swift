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
            HubMenuGroup(label: "Banking", items: [
                .flow(id: "opening-balances", label: "Opening Balances",
                      systemImage: "flag.checkered"),
                .flow(id: "bank-reconciliation", label: "Bank Reconciliation",
                      systemImage: "building.columns"),
                .docType(Banking.bankAccount, label: "Bank Accounts")
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
            HubMenuGroup(label: "Tax & Compliance", items: [
                .flow(id: "tax-return", label: "Tax Return",
                      systemImage: "doc.text.magnifyingglass"),
                .docType(Compliance.taxFiling, label: "Tax Filings"),
                .flow(id: "year-end-close", label: "Year-End Close",
                      systemImage: "calendar.badge.checkmark"),
                .flow(id: "books-lock", label: "Lock Books",
                      systemImage: "lock"),
                .flow(id: "accountant-export", label: "Accountant Export",
                      systemImage: "square.and.arrow.up.on.square"),
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
                        label: HubReports.trialBalance.name),
                .report(id: HubReports.generalLedger.id,
                        label: HubReports.generalLedger.name)
            ], visibility: .advanced),
            HubMenuGroup(label: "Dashboards", items: [
                .dashboard(id: HubDashboards.accountingOverview.id,
                           label: HubDashboards.accountingOverview.name)
            ])
        ]
    )
}
