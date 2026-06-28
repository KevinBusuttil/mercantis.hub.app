import MercantisCoreUI

/// The Hub's plain-language glossary of ERP / accounting terms. Injected into
/// the environment at app scope so jargon field labels, section titles, and the
/// Glossary window can all explain themselves to a new user. Terms are matched
/// case-insensitively, with trailing "(…)" qualifiers and a few leading
/// adjectives ("Default", "Source") stripped, so a single "Receivable" entry
/// covers the "Debit To (Receivable)" label and "Tax Code" covers "Default Tax
/// Code".
enum HubGlossary {

    static let glossary = Glossary(entries)

    private static let entries: [GlossaryEntry] = [
        // Document lifecycle
        .init(term: "Draft",
              summary: "A document you're still editing.",
              detail: "A draft has no effect on your stock or accounts until you submit it."),
        .init(term: "Submit",
              summary: "Finalises a document and posts its effects to stock and the ledger.",
              detail: "Once submitted, a document can't be edited directly — only cancelled, then amended into a new editable copy."),
        .init(term: "Posted",
              summary: "A submitted document whose amounts have been recorded in your accounts."),
        .init(term: "Cancel",
              summary: "Reverses a submitted document's stock and ledger effects and marks it cancelled."),
        .init(term: "Amend",
              summary: "Creates a fresh editable copy of a cancelled document so you can correct and resubmit it."),
        .init(term: "Outstanding",
              summary: "The unpaid balance remaining on an invoice."),

        // Accounting
        .init(term: "Fiscal Year",
              summary: "The 12-month period your accounts are reported over.",
              detail: "Most businesses use the calendar year. One fiscal year is marked active so the Hub knows the current accounting period."),
        .init(term: "Chart of Accounts",
              summary: "The full list of accounts your transactions are recorded against."),
        .init(term: "Receivable",
              summary: "Money your customers owe you.",
              detail: "Submitting a sales invoice increases your receivables until the customer pays."),
        .init(term: "Payable",
              summary: "Money you owe your suppliers.",
              detail: "Submitting a purchase invoice increases your payables until you pay the supplier."),
        .init(term: "Income Account",
              summary: "The revenue account a sale is credited to."),
        .init(term: "Expense Account",
              summary: "The account a purchase or cost is charged to."),
        .init(term: "Cost Center",
              summary: "A department, branch, or project you tag transactions to for reporting."),
        .init(term: "COGS",
              summary: "Cost of Goods Sold — what the items you sold cost you.",
              detail: "Recorded as an expense at the moment you sell stock, so profit reflects the cost of what went out the door."),
        .init(term: "GRNI",
              summary: "Goods Received Not Invoiced — stock you've received but haven't yet been billed for.",
              detail: "Held in a temporary liability account until the supplier's purchase invoice arrives and clears it."),
        .init(term: "Journal Entry",
              summary: "A direct, manual accounting entry of matching debits and credits."),
        .init(term: "Payment Entry",
              summary: "Records money received from a customer or paid to a supplier, settling invoices."),
        .init(term: "Reconcile",
              summary: "Match your recorded transactions against a bank or supplier statement to confirm they agree."),
        .init(term: "Exchange Rate",
              summary: "How many units of your base currency one unit of the document's currency is worth.",
              detail: "Only matters when the document isn't in your base currency. Leave at 1 otherwise."),

        // Stock & items
        .init(term: "Valuation Method",
              summary: "How the cost of stock is worked out when you sell.",
              detail: "Moving Average blends costs as you buy; FIFO uses the oldest cost first. Moving Average suits most businesses."),
        .init(term: "Warehouse",
              summary: "A place — physical or logical — where stock is held."),
        .init(term: "UOM",
              summary: "Unit of Measure — how an item is counted or sold (each, box, kg…)."),
        .init(term: "Item Group",
              summary: "A category used to organise and report on items."),

        // Selling / buying
        .init(term: "Price List",
              summary: "A named set of item prices.",
              detail: "Selecting one on a document auto-fills the line rates; leave it blank to type rates in by hand."),
        .init(term: "Tax Code",
              summary: "A reusable VAT / sales-tax rate applied to a line or document."),
        .init(term: "Currency",
              summary: "The currency a document is priced in. Defaults from your business profile."),
        .init(term: "Naming Series",
              summary: "The pattern used to auto-number documents, e.g. INV-2026-0001."),
        .init(term: "Quotation",
              summary: "A pre-sale price offer to a customer, before they commit to buy."),
        .init(term: "Sales Order",
              summary: "A confirmed sale awaiting delivery and invoicing."),
        .init(term: "Delivery Note",
              summary: "Records stock leaving your warehouse to a customer, without prices."),
    ]
}
