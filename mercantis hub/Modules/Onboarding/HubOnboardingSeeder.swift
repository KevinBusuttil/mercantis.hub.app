import Foundation
import MercantisCore

/// Phase 1 (Accounting Autopilot) — seeds the initial accounting setup the
/// first-run wizard promises, now driven by the chosen **jurisdiction**: a
/// currency, the current fiscal year, a default warehouse, a business-ready
/// chart of accounts (equity, expenses, clearing and tax-control accounts — not
/// the old 9-account stub), a starter set of tax codes, and a Business Profile
/// wired to those defaults.
///
/// Everything is idempotent (deterministic ids, skip-if-exists) so re-running
/// the wizard never duplicates config, and the posting-anchor account ids
/// (Cash, Debtors, Creditors, Sales, COGS, Stock, GRNI, VAT) are kept stable so
/// existing installs and the `PostingCoordinator` keep resolving.
enum HubOnboardingSeeder {

    struct Account: Equatable {
        let id: String
        let name: String
        let rootType: String
        let accountType: String
    }

    /// The legacy posting-anchor accounts. Retained as the canonical core so
    /// the company-default wiring (and existing tests) stay stable; the full
    /// jurisdiction chart is a superset of these.
    static let defaultAccounts: [Account] = [
        Account(id: "Cash",      name: "Cash",               rootType: "Asset",     accountType: "Cash"),
        Account(id: "Bank",      name: "Bank",               rootType: "Asset",     accountType: "Bank"),
        Account(id: "Debtors",   name: "Debtors",            rootType: "Asset",     accountType: "Receivable"),
        Account(id: "Stock",     name: "Stock In Hand",      rootType: "Asset",     accountType: "Stock"),
        Account(id: "Creditors", name: "Creditors",          rootType: "Liability", accountType: "Payable"),
        Account(id: "GRNI",      name: "Stock Received Not Billed", rootType: "Liability", accountType: "Stock Received But Not Billed"),
        Account(id: "VAT",       name: "VAT",                rootType: "Liability", accountType: "Tax"),
        Account(id: "Sales",     name: "Sales",              rootType: "Income",    accountType: "Income"),
        Account(id: "COGS",      name: "Cost of Goods Sold", rootType: "Expense",   accountType: "Expense"),
    ]

    static let warehouseId = "Main Store"

    struct Summary {
        var currency = false
        var fiscalYear = false
        var warehouse = false
        var accounts = 0
        var taxCodes = 0
        var company = false
    }

    /// First/last day of the calendar year — the fiscal-year bounds.
    static func fiscalYearBounds(year: Int, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
        let end = calendar.date(from: DateComponents(year: year, month: 12, day: 31)) ?? Date()
        return (start, end)
    }

    // MARK: - Entry points

    /// Legacy currency-only entry point (kept for compatibility). Maps the
    /// currency to a sensible jurisdiction and seeds a tax-registered setup.
    @discardableResult
    static func seed(engine: DocumentEngine, businessName: String, currencyCode: String) -> Summary {
        let code = currencyCode.isEmpty ? "EUR" : currencyCode.uppercased()
        var jurisdiction = HubJurisdictionLibrary.forCurrency(code)
        // Honour the explicitly chosen currency even if it differs from the
        // jurisdiction's suggested one.
        jurisdiction = Jurisdiction(id: jurisdiction.id, name: jurisdiction.name,
                                    currencyCode: code, taxStyle: jurisdiction.taxStyle,
                                    taxRegimeLabel: jurisdiction.taxRegimeLabel, taxIdLabel: jurisdiction.taxIdLabel)
        return seed(engine: engine, businessName: businessName, jurisdiction: jurisdiction,
                    registered: true, taxId: "", basis: .accrual)
    }

    /// Jurisdiction-aware setup. Seeds the chosen COA + tax templates and wires
    /// the Business Profile so the owner can invoice immediately with no manual
    /// accounting.
    @discardableResult
    static func seed(
        engine: DocumentEngine,
        businessName: String,
        jurisdiction: Jurisdiction,
        registered: Bool,
        taxId: String,
        basis: HubAccountingBasis,
        preset: HubPreset? = nil
    ) -> Summary {
        var summary = Summary()
        let code = jurisdiction.currencyCode.isEmpty ? "EUR" : jurisdiction.currencyCode.uppercased()

        // Currency
        summary.currency = ensure(engine: engine, docType: "Currency", id: code, fields: [
            "currency_name": .string(currencyName(for: code)),
            "iso_code": .string(code),
            "symbol": .string(currencySymbol(for: code)),
            "enabled": .bool(true),
        ])

        // Warehouse
        summary.warehouse = ensure(engine: engine, docType: "Warehouse", id: warehouseId, fields: [
            "warehouse_name": .string(warehouseId),
        ])

        // Fiscal year (current calendar year)
        let year = Calendar.current.component(.year, from: Date())
        let bounds = fiscalYearBounds(year: year)
        summary.fiscalYear = ensure(engine: engine, docType: "FiscalYear", id: "FY-\(year)", fields: [
            "year_name": .string("FY \(year)"),
            "year_start_date": .date(bounds.start),
            "year_end_date": .date(bounds.end),
            "is_active": .bool(true),
            "is_closed": .bool(false),
        ])

        // Chart of accounts (jurisdiction template; groups first so the tree
        // links resolve as leaves are created).
        let chart = HubCOATemplateLibrary.accounts(taxStyle: jurisdiction.taxStyle)
        for account in chart {
            var fields: [String: FieldValue] = [
                "account_name": .string(account.name),
                "account_number": .string(account.code),
                "root_type": .string(account.rootType),
                "account_type": .string(account.accountType),
                "is_group": .bool(account.isGroup),
                "normal_balance": .string(account.normalBalance),
                "is_tax_control": .bool(account.isTaxControl),
                "disabled": .bool(false),
            ]
            if let parent = account.parentId { fields["parent_account"] = .string(parent) }
            if !account.isGroup { fields["currency"] = .string(code) }
            if ensure(engine: engine, docType: "Account", id: account.id, fields: fields) {
                summary.accounts += 1
            }
        }

        // Tax codes (jurisdiction template). The control account is the stable
        // "VAT" id when the jurisdiction levies tax.
        let taxControlAccount = jurisdiction.taxStyle == .none ? "" : "VAT"
        for code in HubTaxTemplateLibrary.codes(for: jurisdiction, registered: registered) {
            var fields: [String: FieldValue] = [
                "tax_code_name": .string(code.name),
                "tax_type": .string(code.type),
                "rate": .double(code.rate),
                "is_default": .bool(code.isDefault),
                "enabled": .bool(true),
            ]
            if !taxControlAccount.isEmpty { fields["tax_account"] = .string(taxControlAccount) }
            if ensure(engine: engine, docType: "TaxCode", id: code.id, fields: fields) {
                summary.taxCodes += 1
            }
        }
        let defaultTaxCode = HubTaxTemplateLibrary.defaultCodeId(for: jurisdiction, registered: registered)

        // Bank accounts — wrap the Bank and Cash ledger accounts so the owner
        // can reconcile them from day one.
        for (id, name, gl, kind) in [("Bank-Bank", "Main Bank Account", "Bank", "Bank"),
                                     ("Bank-Cash", "Cash on Hand", "Cash", "Cash")] {
            _ = ensure(engine: engine, docType: "BankAccount", id: id, fields: [
                "account_name": .string(name),
                "account_kind": .string(kind),
                "gl_account": .string(gl),
                "currency": .string(code),
                "disabled": .bool(false),
            ])
        }

        // Business Profile — create when absent, otherwise backfill only the
        // defaults that are still empty (never clobber existing values). The
        // chosen business-type preset tailors the default income account
        // (Service Income for a service/consulting business, Sales for goods)
        // and is recorded on the Company record.
        var profileAccountDefaults = accountDefaults(from: chart)
        if let preset { profileAccountDefaults["default_income_account"] = preset.defaultIncomeAccountId }
        summary.company = ensureCompany(
            engine: engine,
            businessName: businessName,
            currencyCode: code,
            accountDefaults: profileAccountDefaults,
            defaultTaxCode: defaultTaxCode,
            jurisdiction: jurisdiction,
            registered: registered,
            taxId: taxId,
            basis: basis,
            businessType: preset?.rawValue ?? ""
        )

        return summary
    }

    // MARK: - Company defaults

    /// The legacy default-account wiring, kept for tests / reference. The
    /// jurisdiction seed computes the same mapping from the template via
    /// `accountDefaults(from:)`.
    static let companyDefaults: [String: String] = [
        "default_receivable_account": "Debtors",
        "default_payable_account":    "Creditors",
        "default_income_account":     "Sales",
        "default_expense_account":    "COGS",
        "default_cash_bank_account":  "Cash",
        "default_stock_account":      "Stock",
        "default_vat_account":        "VAT",
        "default_warehouse":          warehouseId,
    ]

    /// Map the slot-bearing accounts of a chart to their Business-Profile field
    /// keys, so the wiring always matches the seeded chart.
    static func accountDefaults(from chart: [COAAccount]) -> [String: String] {
        var map: [String: String] = ["default_warehouse": warehouseId]
        for account in chart {
            if let slot = account.slot {
                map[HubAccountResolver.companyField(for: slot)] = account.id
            }
        }
        return map
    }

    private static func ensureCompany(
        engine: DocumentEngine,
        businessName: String,
        currencyCode: String,
        accountDefaults: [String: String],
        defaultTaxCode: String?,
        jurisdiction: Jurisdiction,
        registered: Bool,
        taxId: String,
        basis: HubAccountingBasis,
        businessType: String = ""
    ) -> Bool {
        // The jurisdiction/identity fields backfilled onto the Company record.
        var profileDefaults: [String: FieldValue] = [
            "default_currency": .string(currencyCode),
            "country": .string(jurisdiction.name),
            "tax_regime": .string(jurisdiction.taxRegimeLabel),
            "tax_registered": .bool(registered),
            "accounting_basis": .string(basis.rawValue),
        ]
        if !businessType.isEmpty { profileDefaults["business_type"] = .string(businessType) }
        for (key, accountId) in accountDefaults { profileDefaults[key] = .string(accountId) }
        if let defaultTaxCode { profileDefaults["default_tax_code"] = .string(defaultTaxCode) }
        let trimmedTaxId = taxId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTaxId.isEmpty { profileDefaults["vat_tax_number"] = .string(trimmedTaxId) }

        let existing = (try? engine.list(docType: "Company"))?.first
        if var company = existing {
            var changed = false
            for (key, value) in profileDefaults where isEmpty(company.fields[key]) {
                company.fields[key] = value; changed = true
            }
            if isEmpty(company.fields["business_name"]), !businessName.isEmpty {
                company.fields["business_name"] = .string(businessName); changed = true
            }
            if changed { _ = try? engine.save(company) }
            return false
        }

        var fields: [String: FieldValue] = [
            "business_name": .string(businessName.isEmpty ? "My Business" : businessName),
        ]
        for (key, value) in profileDefaults { fields[key] = value }
        let company = Document(
            id: "", docType: "Company", company: "", status: "",
            createdAt: Date(), updatedAt: Date(), syncVersion: 0, syncState: .local,
            fields: fields, children: [:]
        )
        _ = try? engine.save(company)
        return true
    }

    // MARK: - Helpers

    /// Create a record with a fixed id if it doesn't already exist.
    /// Returns `true` when a new record was written.
    ///
    /// The id is set on the document **directly** (not via `userSuppliedName`):
    /// `Account`, `Currency`, `Warehouse` and `FiscalYear` have no name-based
    /// `autoname`, so a supplied name would be ignored and the record would get a
    /// UUID — which then breaks the stable ids the chart's `parent_account` /
    /// `currency` links and the posting wiring depend on (e.g. "Cash", "VAT",
    /// "Sales"). `DocumentEngine.save` keeps a non-empty id as-is, so this gives
    /// every seeded master its intended stable id and keeps re-runs idempotent.
    private static func ensure(engine: DocumentEngine, docType: String, id: String, fields: [String: FieldValue]) -> Bool {
        if (try? engine.fetch(docType: docType, id: id)) != nil { return false }
        let doc = Document(
            id: id, docType: docType, company: "", status: "",
            createdAt: Date(), updatedAt: Date(), syncVersion: 0, syncState: .local,
            fields: fields, children: [:]
        )
        do {
            _ = try engine.save(doc)
            return true
        } catch {
            return false
        }
    }

    private static func isEmpty(_ value: FieldValue?) -> Bool {
        guard case .string(let s)? = value else { return value == nil }
        return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func currencyName(for code: String) -> String {
        switch code {
        case "EUR": return "Euro"
        case "USD": return "US Dollar"
        case "GBP": return "Pound Sterling"
        case "CAD": return "Canadian Dollar"
        case "MTL": return "Maltese Lira"
        default:    return code
        }
    }

    private static func currencySymbol(for code: String) -> String {
        switch code {
        case "EUR": return "€"
        case "USD": return "$"
        case "GBP": return "£"
        case "CAD": return "$"
        default:    return code
        }
    }
}
