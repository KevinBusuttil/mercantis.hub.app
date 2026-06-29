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
            businessType: preset?.title ?? ""
        )

        return summary
    }

    // MARK: - Repair / re-seed

    struct RepairSummary {
        var accountsAdded = 0
        var taxCodesAdded = 0
        var orphansRemoved = 0
        var changed: Bool { accountsAdded > 0 || taxCodesAdded > 0 || orphansRemoved > 0 }
    }

    /// Top up an incomplete or pre-fix chart of accounts **in place**: re-seed
    /// every missing account and tax code with its stable id (idempotent), then
    /// remove the stray UUID-id group headers an older, broken seed left behind.
    /// Safe to run any time — it reconstructs the tax context from the existing
    /// Business Profile and never touches a correctly-id'd account, a posted
    /// account, or one still used as a parent. Scoped to the chart (and the
    /// currency its accounts link to) so it never duplicates other masters.
    @discardableResult
    static func repairChart(engine: DocumentEngine) -> RepairSummary {
        var summary = RepairSummary()
        let company = (try? engine.list(docType: "Company"))?.first
        let code = (nonEmptyString(company?.fields["default_currency"]) ?? "EUR").uppercased()
        let base = HubJurisdictionLibrary.forCurrency(code)
        let taxStyle = base.taxStyle
        let registered = boolValue(company?.fields["tax_registered"]) ?? (taxStyle != .none)

        // The currency must exist (with its stable id) before the leaf accounts
        // that link to it, or their save would be rejected.
        _ = ensure(engine: engine, docType: "Currency", id: code, fields: [
            "currency_name": .string(currencyName(for: code)),
            "iso_code": .string(code),
            "symbol": .string(currencySymbol(for: code)),
            "enabled": .bool(true),
        ])

        // Chart of accounts (groups first so leaf parent links resolve).
        for account in HubCOATemplateLibrary.accounts(taxStyle: taxStyle) {
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
                summary.accountsAdded += 1
            }
        }

        // Tax codes (control account is the stable "VAT" id where tax applies).
        let taxControlAccount = taxStyle == .none ? "" : "VAT"
        for tax in HubTaxTemplateLibrary.codes(for: base, registered: registered) {
            var fields: [String: FieldValue] = [
                "tax_code_name": .string(tax.name),
                "tax_type": .string(tax.type),
                "rate": .double(tax.rate),
                "is_default": .bool(tax.isDefault),
                "enabled": .bool(true),
            ]
            if !taxControlAccount.isEmpty { fields["tax_account"] = .string(taxControlAccount) }
            if ensure(engine: engine, docType: "TaxCode", id: tax.id, fields: fields) {
                summary.taxCodesAdded += 1
            }
        }

        summary.orphansRemoved = removeOrphanGroups(engine: engine, taxStyle: taxStyle)
        return summary
    }

    /// Remove the duplicate, stray group headers a pre-fix seed created with a
    /// UUID id (instead of the stable template id). Strictly gated: only a
    /// group whose id is NOT a template id, whose account number matches a
    /// template group, that is not used as anyone's parent and has no ledger
    /// activity, is removed.
    private static func removeOrphanGroups(engine: DocumentEngine, taxStyle: HubTaxStyle) -> Int {
        let chart = HubCOATemplateLibrary.accounts(taxStyle: taxStyle)
        let templateIds = Set(chart.map(\.id))
        let groupCodes = Set(chart.filter(\.isGroup).map(\.code))
        let accounts = (try? engine.list(docType: "Account")) ?? []
        let usedAsParent = Set(accounts.compactMap { nonEmptyString($0.fields["parent_account"]) })
        let posted = Set(((try? engine.list(docType: "GLEntry")) ?? []).compactMap { nonEmptyString($0.fields["account"]) })

        var removed = 0
        for account in accounts {
            guard boolValue(account.fields["is_group"]) == true,
                  !templateIds.contains(account.id),
                  let number = nonEmptyString(account.fields["account_number"]),
                  groupCodes.contains(number),
                  !usedAsParent.contains(account.id),
                  !posted.contains(account.id) else { continue }
            if (try? engine.delete(docType: "Account", id: account.id)) != nil { removed += 1 }
        }
        return removed
    }

    private static func boolValue(_ value: FieldValue?) -> Bool? {
        if case .bool(let b)? = value { return b }
        return nil
    }

    private static func nonEmptyString(_ value: FieldValue?) -> String? {
        guard case .string(let s)? = value else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
        // The wizard choices the user just made (identity, jurisdiction, tax,
        // accounting basis). These are applied AUTHORITATIVELY — overwriting any
        // existing value — so re-running setup actually updates them. (They used
        // to be backfill-only, which is why a changed Accounting Basis / Country
        // / Tax Regime never took effect on an existing profile.)
        var authoritative: [String: FieldValue] = [
            "default_currency": .string(currencyCode),
            "country": .string(jurisdiction.name),
            "tax_regime": .string(jurisdiction.taxRegimeLabel),
            "tax_registered": .bool(registered),
            "accounting_basis": .string(basis.rawValue),
        ]
        if !businessType.isEmpty { authoritative["business_type"] = .string(businessType) }
        if let defaultTaxCode { authoritative["default_tax_code"] = .string(defaultTaxCode) }
        let trimmedTaxId = taxId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTaxId.isEmpty { authoritative["vat_tax_number"] = .string(trimmedTaxId) }

        // The default-account links — BACKFILLED only, so a manual re-mapping is
        // never clobbered by a re-seed.
        var accountLinks: [String: FieldValue] = [:]
        for (key, accountId) in accountDefaults { accountLinks[key] = .string(accountId) }

        let existing = (try? engine.list(docType: "Company"))?.first
        if var company = existing {
            var changed = false
            // Upgrade a legacy raw business-type value ("tradeDistribution") to
            // its friendly label, when this run isn't itself setting one.
            if authoritative["business_type"] == nil,
               case .string(let stored)? = company.fields["business_type"],
               let preset = HubPreset(rawValue: stored) {
                company.fields["business_type"] = .string(preset.title); changed = true
            }
            for (key, value) in authoritative where company.fields[key] != value {
                company.fields[key] = value; changed = true
            }
            for (key, value) in accountLinks where isEmpty(company.fields[key]) {
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
        for (key, value) in authoritative { fields[key] = value }
        for (key, value) in accountLinks { fields[key] = value }
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
