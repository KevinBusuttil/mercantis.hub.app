import Foundation
import MercantisCore

/// Phase 8 — seeds the initial Business Setup records the first-run wizard
/// promises: a currency, the current fiscal year, a default warehouse, a
/// minimal chart of accounts, and a Business Profile wired to those
/// defaults. Everything is idempotent (deterministic ids, skip-if-exists)
/// so re-running the wizard never duplicates config, and it is purely
/// foundational setup — not demo/sample product data.
enum HubOnboardingSeeder {

    struct Account: Equatable {
        let id: String
        let name: String
        let rootType: String
        let accountType: String
    }

    /// A deliberately small starter chart: enough for sales, purchases,
    /// payments, VAT, stock, and POS to post without further setup.
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
        var company = false
    }

    /// First/last day of the calendar year — the fiscal-year bounds.
    static func fiscalYearBounds(year: Int, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
        let end = calendar.date(from: DateComponents(year: year, month: 12, day: 31)) ?? Date()
        return (start, end)
    }

    @discardableResult
    static func seed(engine: DocumentEngine, businessName: String, currencyCode: String) -> Summary {
        var summary = Summary()
        let code = currencyCode.isEmpty ? "EUR" : currencyCode.uppercased()

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

        // Chart of accounts
        for account in defaultAccounts {
            let created = ensure(engine: engine, docType: "Account", id: account.id, fields: [
                "account_name": .string(account.name),
                "root_type": .string(account.rootType),
                "account_type": .string(account.accountType),
                "currency": .string(code),
            ])
            if created { summary.accounts += 1 }
        }

        // Business Profile (single record). Create when absent; otherwise
        // backfill only the defaults that are still empty, never clobbering.
        summary.company = ensureCompany(engine: engine, businessName: businessName, currencyCode: code)

        return summary
    }

    // MARK: - Helpers

    /// The default-account wiring applied to the Business Profile.
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

    private static func ensureCompany(engine: DocumentEngine, businessName: String, currencyCode: String) -> Bool {
        let existing = (try? engine.list(docType: "Company"))?.first
        if var company = existing {
            // Backfill empty defaults only.
            var changed = false
            if isEmpty(company.fields["default_currency"]) {
                company.fields["default_currency"] = .string(currencyCode); changed = true
            }
            for (key, accountId) in companyDefaults where isEmpty(company.fields[key]) {
                company.fields[key] = .string(accountId); changed = true
            }
            if isEmpty(company.fields["business_name"]), !businessName.isEmpty {
                company.fields["business_name"] = .string(businessName); changed = true
            }
            if changed { _ = try? engine.save(company) }
            return false
        }

        var fields: [String: FieldValue] = [
            "business_name": .string(businessName.isEmpty ? "My Business" : businessName),
            "default_currency": .string(currencyCode),
        ]
        for (key, accountId) in companyDefaults { fields[key] = .string(accountId) }
        let company = Document(
            id: "", docType: "Company", company: "", status: "",
            createdAt: Date(), updatedAt: Date(), syncVersion: 0, syncState: .local,
            fields: fields, children: [:]
        )
        _ = try? engine.save(company)
        return true
    }

    /// Create a record with a fixed id if it doesn't already exist.
    /// Returns `true` when a new record was written.
    private static func ensure(engine: DocumentEngine, docType: String, id: String, fields: [String: FieldValue]) -> Bool {
        if (try? engine.fetch(docType: docType, id: id)) != nil { return false }
        let doc = Document(
            id: "", docType: docType, company: "", status: "",
            createdAt: Date(), updatedAt: Date(), syncVersion: 0, syncState: .local,
            fields: fields, children: [:]
        )
        do {
            _ = try engine.save(doc, userSuppliedName: id)
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
        case "MTL": return "Maltese Lira"
        default:    return code
        }
    }

    private static func currencySymbol(for code: String) -> String {
        switch code {
        case "EUR": return "€"
        case "USD": return "$"
        case "GBP": return "£"
        default:    return code
        }
    }
}
