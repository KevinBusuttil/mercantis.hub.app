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
            ])
        ]
    )
}
