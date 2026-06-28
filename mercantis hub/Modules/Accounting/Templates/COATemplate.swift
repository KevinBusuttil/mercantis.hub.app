import Foundation

/// Phase 1 (Accounting Autopilot) — the chart-of-accounts template library.
///
/// A non-accountant owner should never build a chart of accounts. The seeder
/// applies one of these business-ready templates so the books arrive complete:
/// equity (owner capital / drawings / retained earnings), full operating
/// expenses, clearing accounts, and tax-control accounts — not the old 9-account
/// stub.
///
/// The record ids of the *posting-anchor* accounts (Cash, Debtors, Creditors,
/// Sales, COGS, Stock, GRNI, VAT) are deliberately kept identical to the legacy
/// starter chart so existing installs and the `PostingCoordinator` (which reads
/// the Business-Profile `default_*` links) keep resolving without migration.

/// Which Business-Profile default-account slot an account fills, if any. Only
/// these accounts are wired onto the Company record; the rest of the chart is
/// there for reporting, manual journals, opening balances (Phase 2), and
/// year-end (Phase 3).
enum HubAccountSlot: CaseIterable {
    case receivable, payable, income, expense, cashBank, stock, grni, vatControl

    var companyField: String {
        switch self {
        case .receivable: return "default_receivable_account"
        case .payable:    return "default_payable_account"
        case .income:     return "default_income_account"
        case .expense:    return "default_expense_account"
        case .cashBank:   return "default_cash_bank_account"
        case .stock:      return "default_stock_account"
        case .grni:       return "default_grni_account"
        case .vatControl: return "default_vat_account"
        }
    }
}

/// The flavour of indirect tax in a jurisdiction. Only changes the user-facing
/// *names* of the tax-control accounts; the record ids stay stable so the
/// posting wiring is unaffected.
enum HubTaxStyle: Equatable { case vat, salesTax, gstHst, none }

/// One account in a chart-of-accounts template.
struct COAAccount: Equatable {
    let id: String
    let code: String
    let name: String
    let rootType: String        // Asset / Liability / Equity / Income / Expense
    let accountType: String     // Account.account_type option ("" for groups)
    let parentId: String?
    let isGroup: Bool
    let normalBalance: String   // "Debit" / "Credit"
    let isTaxControl: Bool
    let slot: HubAccountSlot?
}

enum HubCOATemplateLibrary {

    /// The full, ordered chart for a tax style. Group headers come first so the
    /// tree links resolve when leaf accounts are seeded after them.
    static func accounts(taxStyle: HubTaxStyle) -> [COAAccount] {
        var out: [COAAccount] = groups
        out.append(contentsOf: assets(taxStyle))
        out.append(contentsOf: liabilities(taxStyle))
        out.append(contentsOf: equity)
        out.append(contentsOf: income)
        out.append(contentsOf: costOfSales)
        out.append(contentsOf: expenses)
        return out
    }

    // MARK: - Group headers (one level, parents the leaves)

    private static let groups: [COAAccount] = [
        group("ASSETS",    "1000", "Assets",         "Asset"),
        group("LIAB",      "2000", "Liabilities",    "Liability"),
        group("EQUITY",    "3000", "Equity",         "Equity"),
        group("INCOME",    "4000", "Income",         "Income"),
        group("COGSGRP",   "5000", "Cost of Sales",  "Expense"),
        group("EXPENSES",  "6000", "Expenses",       "Expense"),
    ]

    // MARK: - Sections

    private static func assets(_ tax: HubTaxStyle) -> [COAAccount] {
        var rows: [COAAccount] = [
            leaf("Cash",      "1010", "Cash on Hand",                 "Asset", "Cash",  "ASSETS", slot: .cashBank),
            leaf("Bank",      "1020", "Main Bank Account",            "Asset", "Bank",  "ASSETS"),
            leaf("BankSecondary", "1021", "Secondary Bank Account",   "Asset", "Bank",  "ASSETS"),
            leaf("CardClearing",  "1030", "Card Clearing",            "Asset", "Bank",  "ASSETS"),
            leaf("ProcessorClearing", "1040", "Payment Processor Clearing (Stripe / PayPal)", "Asset", "Bank", "ASSETS"),
            leaf("Debtors",   "1100", "Accounts Receivable",          "Asset", "Receivable", "ASSETS", slot: .receivable),
            leaf("Stock",     "1200", "Inventory",                    "Asset", "Stock", "ASSETS", slot: .stock),
            leaf("Prepayments", "1300", "Prepayments",                "Asset", "",      "ASSETS"),
            leaf("DepositsPaid", "1310", "Deposits Paid",             "Asset", "",      "ASSETS"),
            leaf("FixedAssets", "1500", "Fixed Assets",               "Asset", "Fixed Asset", "ASSETS"),
            leaf("AccumDepreciation", "1510", "Accumulated Depreciation", "Asset", "Fixed Asset", "ASSETS", normal: "Credit"),
        ]
        if tax != .none {
            rows.append(leaf("InputVAT", "1400", inputTaxName(tax), "Asset", "Tax", "ASSETS", taxControl: true))
        }
        return rows
    }

    private static func liabilities(_ tax: HubTaxStyle) -> [COAAccount] {
        var rows: [COAAccount] = [
            leaf("Creditors", "2010", "Accounts Payable",             "Liability", "Payable", "LIAB", slot: .payable),
            leaf("GRNI",      "2050", "Goods Received Not Invoiced",  "Liability", "Stock Received But Not Billed", "LIAB", slot: .grni),
            leaf("PayrollTax", "2030", "Payroll Taxes Payable",       "Liability", "Tax", "LIAB"),
            leaf("Accruals",  "2040", "Accruals",                     "Liability", "", "LIAB"),
            leaf("CustomerDeposits", "2060", "Customer Deposits / Deferred Income", "Liability", "", "LIAB"),
            leaf("CreditCard", "2070", "Credit Card Payable",         "Liability", "", "LIAB"),
            leaf("Loans",     "2200", "Loans Payable",                "Liability", "", "LIAB"),
        ]
        if tax != .none {
            // Stable id "VAT" (posting anchor) with a jurisdiction-aware name.
            rows.insert(leaf("VAT", "2020", outputTaxName(tax), "Liability", "Tax", "LIAB", taxControl: true, slot: .vatControl), at: 1)
        }
        return rows
    }

    private static let equity: [COAAccount] = [
        leaf("OwnerCapital",  "3010", "Owner Capital",        "Equity", "Equity", "EQUITY"),
        leaf("OwnerDrawings", "3020", "Owner Drawings",       "Equity", "Equity", "EQUITY", normal: "Debit"),
        leaf("RetainedEarnings", "3030", "Retained Earnings", "Equity", "Equity", "EQUITY"),
        leaf("OpeningBalanceEquity", "3090", "Opening Balance Equity", "Equity", "Equity", "EQUITY"),
    ]

    private static let income: [COAAccount] = [
        leaf("Sales",         "4010", "Sales",                "Income", "Income", "INCOME", slot: .income),
        leaf("ServiceIncome", "4020", "Service Income",       "Income", "Income", "INCOME"),
        leaf("POSSales",      "4030", "POS Sales",            "Income", "Income", "INCOME"),
        leaf("ShippingIncome", "4040", "Shipping Income",     "Income", "Income", "INCOME"),
        leaf("DiscountsAllowed", "4050", "Discounts Allowed", "Income", "Income", "INCOME", normal: "Debit"),
        leaf("SalesReturns",  "4060", "Sales Returns",        "Income", "Income", "INCOME", normal: "Debit"),
        leaf("OtherIncome",   "4090", "Other Income",         "Income", "Income", "INCOME"),
    ]

    private static let costOfSales: [COAAccount] = [
        leaf("COGS",          "5010", "Cost of Goods Sold",   "Expense", "Expense", "COGSGRP", slot: .expense),
        leaf("PurchaseReturns", "5020", "Purchase Returns",   "Expense", "Expense", "COGSGRP", normal: "Credit"),
        leaf("FreightIn",     "5030", "Freight-in / Landed Cost", "Expense", "Expense", "COGSGRP"),
        leaf("StockAdjustment", "5040", "Stock Adjustment",   "Expense", "Stock Adjustment", "COGSGRP"),
        leaf("InventoryWriteOff", "5050", "Inventory Write-off", "Expense", "Expense", "COGSGRP"),
    ]

    private static let expenses: [COAAccount] = [
        leaf("Rent",          "6010", "Rent",                 "Expense", "Expense", "EXPENSES"),
        leaf("Utilities",     "6020", "Utilities",            "Expense", "Expense", "EXPENSES"),
        leaf("TelephoneInternet", "6030", "Telephone & Internet", "Expense", "Expense", "EXPENSES"),
        leaf("OfficeExpenses", "6040", "Office Expenses",     "Expense", "Expense", "EXPENSES"),
        leaf("RepairsMaintenance", "6050", "Repairs & Maintenance", "Expense", "Expense", "EXPENSES"),
        leaf("Advertising",   "6060", "Advertising & Marketing", "Expense", "Expense", "EXPENSES"),
        leaf("MotorTravel",   "6070", "Motor & Travel",       "Expense", "Expense", "EXPENSES"),
        leaf("ProfessionalFees", "6080", "Professional Fees", "Expense", "Expense", "EXPENSES"),
        leaf("BankCharges",   "6090", "Bank Charges",         "Expense", "Expense", "EXPENSES"),
        leaf("MerchantFees",  "6100", "Merchant / Processor Fees", "Expense", "Expense", "EXPENSES"),
        leaf("Insurance",     "6110", "Insurance",            "Expense", "Expense", "EXPENSES"),
        leaf("Software",      "6120", "Software Subscriptions", "Expense", "Expense", "EXPENSES"),
        leaf("Wages",         "6130", "Wages & Salaries",     "Expense", "Expense", "EXPENSES"),
        leaf("Depreciation",  "6140", "Depreciation",         "Expense", "Expense", "EXPENSES"),
        leaf("FXGainLoss",    "6150", "Foreign Exchange Gain / Loss", "Expense", "Expense", "EXPENSES"),
        leaf("RoundingOff",   "6160", "Rounding Differences", "Expense", "Expense", "EXPENSES"),
        leaf("Suspense",      "6900", "Suspense / Uncategorised", "Expense", "Expense", "EXPENSES"),
    ]

    // MARK: - Builders

    private static func group(_ id: String, _ code: String, _ name: String, _ root: String) -> COAAccount {
        COAAccount(id: id, code: code, name: name, rootType: root, accountType: "",
                   parentId: nil, isGroup: true, normalBalance: normalBalance(for: root),
                   isTaxControl: false, slot: nil)
    }

    private static func leaf(_ id: String, _ code: String, _ name: String, _ root: String,
                             _ type: String, _ parent: String, normal: String? = nil,
                             taxControl: Bool = false, slot: HubAccountSlot? = nil) -> COAAccount {
        COAAccount(id: id, code: code, name: name, rootType: root, accountType: type,
                   parentId: parent, isGroup: false, normalBalance: normal ?? normalBalance(for: root),
                   isTaxControl: taxControl, slot: slot)
    }

    /// The natural debit/credit side for a root type.
    static func normalBalance(for root: String) -> String {
        switch root {
        case "Asset", "Expense": return "Debit"
        default:                 return "Credit"   // Liability / Equity / Income
        }
    }

    private static func outputTaxName(_ tax: HubTaxStyle) -> String {
        switch tax {
        case .vat:      return "VAT Payable (Output)"
        case .salesTax: return "Sales Tax Payable"
        case .gstHst:   return "GST / HST Payable"
        case .none:     return "Tax Payable"
        }
    }

    private static func inputTaxName(_ tax: HubTaxStyle) -> String {
        switch tax {
        case .vat:      return "VAT Recoverable (Input)"
        case .salesTax: return "Sales Tax Recoverable"
        case .gstHst:   return "Input Tax Credits (ITC)"
        case .none:     return "Tax Recoverable"
        }
    }
}
