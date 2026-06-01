import Foundation
import MercantisCore

/// Hub-side report definitions and the per-report computation routines
/// that produce `ReportResult`s.
///
/// Wall 9 registers five canonical reports with Core's `ReportEngine`:
/// Sales Register, Purchase Register, Stock Ledger View, Customer Aging,
/// Trial Balance. `ReportDefinition.allowedRoles` (Phase D / ADR-049)
/// gates visibility per role; `MercantisCoreUI.GenericReportView` renders
/// any `ReportResult` as a SwiftUI table.
///
/// ### Why a Hub-side computer
///
/// Core's `ReportEngine.execute(report:)` is a flat list-and-format
/// helper: one row per source document, no aggregation. Sales
/// Register / Purchase Register / Stock Ledger View fit that shape
/// natively. Customer Aging (sum-by-customer + age buckets) and
/// Trial Balance (sum-by-account, grouped by root_type) do not — they
/// need Hub-side aggregation. `HubReports.runResult(reportId:engine:)`
/// dispatches to the right routine per id so the UI layer never needs
/// to know which reports are flat vs aggregated.
public enum HubReports: Sendable {

    private static let financeRoles: [String] = ["System Manager", "Accounts Manager"]
    private static let salesRoles: [String]   = ["System Manager", "Sales Manager", "Sales User"]
    private static let buyingRoles: [String]  = ["System Manager", "Purchase Manager", "Purchase User"]
    private static let stockRoles: [String]   = ["System Manager", "Stock Manager", "Stock User"]

    // MARK: - Definitions

    public static let salesRegister = ReportDefinition(
        id: "sales-register",
        name: "Sales Register",
        docType: "SalesInvoice",
        columns: [
            "id", "transaction_date", "customer", "currency",
            "grand_total", "outstanding_amount", "status"
        ],
        filters: [
            ReportFilter(fieldKey: "customer", label: "Customer"),
            ReportFilter(fieldKey: "status",   label: "Status"),
        ],
        allowedRoles: financeRoles + salesRoles
    )

    public static let purchaseRegister = ReportDefinition(
        id: "purchase-register",
        name: "Purchase Register",
        docType: "PurchaseInvoice",
        columns: [
            "id", "transaction_date", "supplier", "currency",
            "grand_total", "outstanding_amount", "status"
        ],
        filters: [
            ReportFilter(fieldKey: "supplier", label: "Supplier"),
            ReportFilter(fieldKey: "status",   label: "Status"),
        ],
        allowedRoles: financeRoles + buyingRoles
    )

    public static let stockLedgerView = ReportDefinition(
        id: "stock-ledger-view",
        name: "Stock Ledger View",
        docType: "StockLedgerEntry",
        columns: [
            "posting_date", "voucher_no", "item", "warehouse",
            "qty_change", "valuation_rate", "amount", "is_reversal"
        ],
        filters: [
            ReportFilter(fieldKey: "item",      label: "Item"),
            ReportFilter(fieldKey: "warehouse", label: "Warehouse"),
        ],
        allowedRoles: financeRoles + stockRoles
    )

    /// Customer Aging — outstanding receivables bucketed by age.
    /// The `columns` here describe the **output** shape produced by
    /// `runResult`, not the underlying SalesInvoice columns.
    public static let customerAging = ReportDefinition(
        id: "customer-aging",
        name: "Customer Aging",
        docType: "SalesInvoice",
        columns: [
            "customer",
            "0-30 days", "31-60 days", "61-90 days", "90+ days",
            "Outstanding"
        ],
        filters: [
            ReportFilter(fieldKey: "customer", label: "Customer"),
        ],
        allowedRoles: financeRoles + salesRoles
    )

    /// Trial Balance — GL Entry rolled up per Account, sorted by root_type.
    public static let trialBalance = ReportDefinition(
        id: "trial-balance",
        name: "Trial Balance",
        docType: "GLEntry",
        columns: ["Root Type", "Account", "Debit", "Credit", "Closing Balance"],
        filters: [],
        allowedRoles: financeRoles
    )

    /// Customer Statement — Phase 5.7. CustTrans rows for a chosen
    /// customer in posting-date order with a running outstanding
    /// balance. The "Customer" filter is required at run time.
    public static let customerStatement = ReportDefinition(
        id: "customer-statement",
        name: "Customer Statement",
        docType: "CustTrans",
        columns: [
            "posting_date", "voucher_no", "trans_type",
            "amount", "running_balance"
        ],
        filters: [
            ReportFilter(fieldKey: "customer", label: "Customer"),
        ],
        allowedRoles: financeRoles + salesRoles
    )

    /// Supplier Ledger — Phase 5.7. Symmetric to Customer Statement.
    public static let supplierLedger = ReportDefinition(
        id: "supplier-ledger",
        name: "Supplier Ledger",
        docType: "VendTrans",
        columns: [
            "posting_date", "voucher_no", "trans_type",
            "amount", "running_balance"
        ],
        filters: [
            ReportFilter(fieldKey: "supplier", label: "Supplier"),
        ],
        allowedRoles: financeRoles + buyingRoles
    )

    /// VAT Summary — Phase 2. `TaxTrans` rolled up per tax code, split into
    /// output (sales) and input (purchase) VAT, with the net payable.
    /// Reversal rows carry negative base / tax so cancelled invoices drop
    /// out of the totals automatically.
    public static let vatSummary = ReportDefinition(
        id: "vat-summary",
        name: "VAT Summary",
        docType: "TaxTrans",
        columns: [
            "Tax Code", "Rate",
            "Output Base", "Output VAT",
            "Input Base", "Input VAT",
            "Net VAT",
        ],
        filters: [],
        allowedRoles: financeRoles
    )

    public static let allReports: [ReportDefinition] = [
        salesRegister, purchaseRegister,
        stockLedgerView,
        customerAging, trialBalance,
        customerStatement, supplierLedger,
        vatSummary,
    ]

    public static func report(forId id: String) -> ReportDefinition? {
        allReports.first { $0.id == id }
    }

    // MARK: - Computation

    /// Build a `ReportResult` for the given Hub report id. Returns `nil`
    /// when the id is unknown so the caller can fall back to a placeholder
    /// or empty state.
    public static func runResult(
        reportId: String,
        engine: DocumentEngine,
        filters: [String: FieldValue] = [:]
    ) throws -> ReportResult? {
        guard let report = report(forId: reportId) else { return nil }
        switch reportId {
        case "sales-register", "purchase-register":
            return try runFlatList(report: report, engine: engine, filters: filters)
        case "stock-ledger-view":
            return try runStockLedger(report: report, engine: engine, filters: filters)
        case "customer-aging":
            return try runCustomerAging(engine: engine, filters: filters)
        case "trial-balance":
            return try runTrialBalance(engine: engine)
        case "customer-statement":
            return try runSubledgerStatement(
                report: customerStatement,
                docType: "CustTrans",
                partyField: "customer",
                filters: filters,
                engine: engine
            )
        case "supplier-ledger":
            return try runSubledgerStatement(
                report: supplierLedger,
                docType: "VendTrans",
                partyField: "supplier",
                filters: filters,
                engine: engine
            )
        case "vat-summary":
            return try runVatSummary(engine: engine)
        default:
            return nil
        }
    }

    // MARK: - Flat list runners

    private static func runFlatList(
        report: ReportDefinition,
        engine: DocumentEngine,
        filters: [String: FieldValue]
    ) throws -> ReportResult {
        let documents = try engine.list(
            docType: report.docType,
            filters: filters.isEmpty ? nil : filters,
            sortBy: [ListSort(fieldKey: "createdAt", direction: .descending)],
            applyRowAccess: false
        )
        let rows: [[String?]] = documents.map { doc in
            report.columns.map { col in
                // Render the status column with the document's business wording
                // (e.g. "Posted" / "Paid") instead of the raw workflow state.
                if col == "status" {
                    return HubWorkflowDisplayPolicy.policy
                        .statusDisplay(docTypeId: report.docType, state: doc.status)
                        .label
                }
                return format(value: lookup(key: col, in: doc))
            }
        }
        return ReportResult(columns: report.columns, rows: rows)
    }

    private static func runStockLedger(
        report: ReportDefinition,
        engine: DocumentEngine,
        filters: [String: FieldValue]
    ) throws -> ReportResult {
        let documents = try engine.list(
            docType: report.docType,
            filters: filters.isEmpty ? nil : filters,
            sortBy: [
                ListSort(fieldKey: "posting_date", direction: .descending),
                ListSort(fieldKey: "createdAt",   direction: .descending),
            ],
            applyRowAccess: false
        )
        let rows: [[String?]] = documents.map { doc in
            report.columns.map { col in
                format(value: lookup(key: col, in: doc))
            }
        }
        return ReportResult(columns: report.columns, rows: rows)
    }

    // MARK: - Customer Aging

    private static func runCustomerAging(
        engine: DocumentEngine,
        filters: [String: FieldValue]
    ) throws -> ReportResult {
        let invoices = try engine.list(
            docType: "SalesInvoice",
            filters: filters.isEmpty ? nil : filters,
            applyRowAccess: false
        )

        struct Buckets {
            var b0_30:  Double = 0
            var b31_60: Double = 0
            var b61_90: Double = 0
            var b91:    Double = 0
            var total:  Double { b0_30 + b31_60 + b61_90 + b91 }
        }

        let today = Date()
        var perCustomer: [String: Buckets] = [:]

        for invoice in invoices {
            guard invoice.docStatus == 1 else { continue }
            let outstanding = asDouble(invoice.fields["outstanding_amount"]) ?? 0
            guard outstanding > 0 else { continue }
            let customer = asString(invoice.fields["customer"]) ?? "(unknown)"
            let dueDate  = asDate(invoice.fields["due_date"])
                ?? asDate(invoice.fields["transaction_date"])
                ?? today
            let days = max(0, Int(today.timeIntervalSince(dueDate) / 86400))

            var bucket = perCustomer[customer] ?? Buckets()
            switch days {
            case ...30:    bucket.b0_30  += outstanding
            case 31...60:  bucket.b31_60 += outstanding
            case 61...90:  bucket.b61_90 += outstanding
            default:       bucket.b91    += outstanding
            }
            perCustomer[customer] = bucket
        }

        let ordered = perCustomer
            .sorted { $0.value.total > $1.value.total }
        let rows: [[String?]] = ordered.map { (customer, b) in
            [
                customer,
                formatCurrency(b.b0_30),
                formatCurrency(b.b31_60),
                formatCurrency(b.b61_90),
                formatCurrency(b.b91),
                formatCurrency(b.total),
            ]
        }
        return ReportResult(columns: customerAging.columns, rows: rows)
    }

    // MARK: - Customer Statement / Supplier Ledger (Phase 5.7)

    /// Render a subledger statement (CustTrans or VendTrans) for one
    /// party, in posting-date order, with a running balance column. The
    /// `partyField` filter ("customer" or "supplier") is required —
    /// statements without it would be unbounded and meaningless.
    private static func runSubledgerStatement(
        report: ReportDefinition,
        docType: String,
        partyField: String,
        filters: [String: FieldValue],
        engine: DocumentEngine
    ) throws -> ReportResult {
        // Require the party filter; if missing, return an empty result
        // so the UI can prompt the user instead of dumping every row.
        guard filters[partyField] != nil else {
            return ReportResult(columns: report.columns, rows: [])
        }

        let rows = try engine.list(
            docType: docType,
            filters: filters,
            sortBy: [
                ListSort(fieldKey: "posting_date", direction: .ascending),
                ListSort(fieldKey: "createdAt",   direction: .ascending),
            ],
            applyRowAccess: false
        )

        var output: [[String?]] = []
        var running: Double = 0
        for trans in rows {
            let amount = asDouble(trans.fields["amount"]) ?? 0
            running += amount
            output.append([
                format(value: trans.fields["posting_date"]),
                format(value: trans.fields["voucher_no"]),
                format(value: trans.fields["trans_type"]),
                formatCurrency(amount),
                formatCurrency(running),
            ])
        }
        return ReportResult(columns: report.columns, rows: output)
    }

    // MARK: - VAT Summary (Phase 2)

    /// Roll up `TaxTrans` rows per tax code into output (sales) vs input
    /// (purchase) VAT. Output is identified by the source voucher type
    /// (SalesInvoice / POS); everything else is treated as input.
    private static func runVatSummary(engine: DocumentEngine) throws -> ReportResult {
        let entries = try engine.list(docType: "TaxTrans", applyRowAccess: false)

        struct Bucket {
            var rate: Double = 0
            var outputBase: Double = 0
            var outputVat: Double = 0
            var inputBase: Double = 0
            var inputVat: Double = 0
        }

        // Resolve tax-code ids to their friendly names for display.
        let codeNames: [String: String] = Dictionary(
            (try engine.list(docType: "TaxCode", applyRowAccess: false))
                .map { ($0.id, asString($0.fields["tax_code_name"]) ?? $0.id) },
            uniquingKeysWith: { first, _ in first }
        )

        let outputVouchers: Set<String> = ["SalesInvoice", "POSInvoice", "POSSale"]
        var perCode: [String: Bucket] = [:]
        var order: [String] = []

        for entry in entries {
            let code = asString(entry.fields["tax"]) ?? "(none)"
            if perCode[code] == nil { order.append(code) }
            var bucket = perCode[code] ?? Bucket()
            bucket.rate = asDouble(entry.fields["rate"]) ?? bucket.rate
            let base = asDouble(entry.fields["base_amount"]) ?? 0
            let tax  = asDouble(entry.fields["tax_amount"]) ?? 0
            let voucher = asString(entry.fields["voucher_type"]) ?? ""
            if outputVouchers.contains(voucher) {
                bucket.outputBase += base
                bucket.outputVat  += tax
            } else {
                bucket.inputBase += base
                bucket.inputVat  += tax
            }
            perCode[code] = bucket
        }

        var rows: [[String?]] = []
        var totalOutVat = 0.0
        var totalInVat = 0.0
        for code in order {
            guard let b = perCode[code] else { continue }
            totalOutVat += b.outputVat
            totalInVat  += b.inputVat
            rows.append([
                codeNames[code] ?? code,
                formatRate(b.rate),
                formatCurrency(b.outputBase),
                formatCurrency(b.outputVat),
                formatCurrency(b.inputBase),
                formatCurrency(b.inputVat),
                formatCurrency(b.outputVat - b.inputVat),
            ])
        }
        // Net VAT payable (output) / reclaimable (input) across all codes.
        rows.append([
            "Total", "", "", formatCurrency(totalOutVat),
            "", formatCurrency(totalInVat),
            formatCurrency(totalOutVat - totalInVat),
        ])
        return ReportResult(columns: vatSummary.columns, rows: rows)
    }

    private static func formatRate(_ rate: Double) -> String {
        rate == rate.rounded()
            ? String(format: "%.0f%%", rate)
            : String(format: "%.2f%%", rate)
    }

    // MARK: - Trial Balance

    private static func runTrialBalance(engine: DocumentEngine) throws -> ReportResult {
        // 1. Sum debit / credit per account across every GL Entry. Reversal
        //    rows already carry swapped debit / credit so they net out
        //    automatically — we don't filter them out, the math is correct.
        let entries = try engine.list(docType: "GLEntry", applyRowAccess: false)
        struct Totals { var debit: Double = 0; var credit: Double = 0 }
        var perAccount: [String: Totals] = [:]
        for entry in entries {
            guard let account = asString(entry.fields["account"]) else { continue }
            let debit  = asDouble(entry.fields["debit"])  ?? 0
            let credit = asDouble(entry.fields["credit"]) ?? 0
            var totals = perAccount[account] ?? Totals()
            totals.debit  += debit
            totals.credit += credit
            perAccount[account] = totals
        }

        // 2. Look up each Account to find its root_type so we can group.
        let accounts = try engine.list(docType: "Account", applyRowAccess: false)
        let rootTypeByAccount: [String: String] = Dictionary(
            uniqueKeysWithValues: accounts.map { ($0.id, asString($0.fields["root_type"]) ?? "Unclassified") }
        )

        // 3. Walk accounts in a stable order: by root_type then by name.
        let rootOrder = ["Asset", "Liability", "Equity", "Income", "Expense", "Unclassified"]
        let sortedAccounts = perAccount.keys.sorted { lhs, rhs in
            let lRoot = rootTypeByAccount[lhs] ?? "Unclassified"
            let rRoot = rootTypeByAccount[rhs] ?? "Unclassified"
            let lIdx = rootOrder.firstIndex(of: lRoot) ?? rootOrder.count
            let rIdx = rootOrder.firstIndex(of: rRoot) ?? rootOrder.count
            if lIdx != rIdx { return lIdx < rIdx }
            return lhs < rhs
        }

        var rows: [[String?]] = []
        var currentRoot: String? = nil
        for account in sortedAccounts {
            let totals = perAccount[account] ?? Totals()
            let root = rootTypeByAccount[account] ?? "Unclassified"
            let closing = totals.debit - totals.credit
            let groupHeader = currentRoot == root ? "" : root
            currentRoot = root
            rows.append([
                groupHeader,
                account,
                formatCurrency(totals.debit),
                formatCurrency(totals.credit),
                formatCurrency(closing)
            ])
        }
        return ReportResult(columns: trialBalance.columns, rows: rows)
    }

    // MARK: - Cell helpers

    private static func lookup(key: String, in document: Document) -> FieldValue? {
        if let v = document.fields[key] { return v }
        switch key {
        case "id":        return .string(document.id)
        case "status":    return .string(document.status)
        case "docStatus": return .int(document.docStatus)
        default:          return nil
        }
    }

    private static func format(value: FieldValue?) -> String? {
        guard let value else { return nil }
        switch value {
        case .string(let s): return s
        case .int(let i):    return String(i)
        case .double(let d): return formatCurrency(d)
        case .bool(let b):   return b ? "Yes" : "No"
        case .null:          return nil
        case .date(let d), .dateTime(let d):
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .none
            return f.string(from: d)
        case .data:          return nil
        case .array(let xs): return "\(xs.count) items"
        }
    }

    private static func formatCurrency(_ d: Double) -> String {
        String(format: "%.2f", d)
    }

    private static func asDouble(_ v: FieldValue?) -> Double? {
        switch v {
        case .double(let d): return d
        case .int(let i):    return Double(i)
        default:             return nil
        }
    }

    private static func asString(_ v: FieldValue?) -> String? {
        if case .string(let s) = v { return s }
        return nil
    }

    private static func asDate(_ v: FieldValue?) -> Date? {
        switch v {
        case .date(let d), .dateTime(let d): return d
        default: return nil
        }
    }
}
