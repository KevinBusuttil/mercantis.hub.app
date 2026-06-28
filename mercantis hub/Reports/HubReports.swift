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

    /// Stock on Hand — Phase 3. `Bin` (Stock Balance) rows: quantity,
    /// valuation, value and last movement per item / warehouse. Friendly
    /// column headers; the runner resolves item / warehouse display names.
    public static let stockOnHand = ReportDefinition(
        id: "stock-on-hand",
        name: "Stock on Hand",
        docType: "Bin",
        columns: [
            "Item", "Warehouse", "Actual Qty",
            "Valuation Rate", "Stock Value", "Last Movement",
        ],
        filters: [
            ReportFilter(fieldKey: "item",      label: "Item"),
            ReportFilter(fieldKey: "warehouse", label: "Warehouse"),
        ],
        allowedRoles: financeRoles + stockRoles
    )

    /// Open Deliveries — Phase 4. Sales Deliveries that have not yet reached
    /// a terminal state (Delivered / Cancelled): the "undelivered sales"
    /// view and the foundation for delivery-route planning.
    public static let openDeliveries = ReportDefinition(
        id: "open-deliveries",
        name: "Open Deliveries",
        docType: "SalesDelivery",
        columns: ["Delivery", "Customer", "Delivery Date", "Scheduled", "Status"],
        filters: [
            ReportFilter(fieldKey: "customer", label: "Customer"),
        ],
        allowedRoles: financeRoles + salesRoles
    )

    /// Pending Receipts — Phase 4. Purchase Receipts still in Draft, i.e.
    /// goods expected but not yet confirmed into stock.
    public static let pendingReceipts = ReportDefinition(
        id: "pending-receipts",
        name: "Pending Receipts",
        docType: "PurchaseReceipt",
        columns: ["Receipt", "Supplier", "Receipt Date", "Total Qty", "Status"],
        filters: [
            ReportFilter(fieldKey: "supplier", label: "Supplier"),
        ],
        allowedRoles: financeRoles + buyingRoles
    )

    /// Today's Routes — Phase 7. Delivery Routes dated today, with stop and
    /// delivered counts derived from each route's stops.
    public static let todaysRoutes = ReportDefinition(
        id: "todays-routes",
        name: "Today's Routes",
        docType: "DeliveryRoute",
        columns: ["Route", "Driver", "Vehicle", "Status", "Stops", "Delivered"],
        filters: [],
        allowedRoles: financeRoles + salesRoles + stockRoles
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

    /// Supplier Aging (Accounts Payable) — outstanding payables bucketed by
    /// age. Symmetric to `customerAging` but over PurchaseInvoice / supplier;
    /// the Swift app previously shipped only the AR (customer) aging. Mirrors
    /// the Flutter `ap_aging` report (`reports/aggregating_reports.dart`).
    public static let supplierAging = ReportDefinition(
        id: "supplier-aging",
        name: "Supplier Aging",
        docType: "PurchaseInvoice",
        columns: [
            "supplier",
            "0-30 days", "31-60 days", "61-90 days", "90+ days",
            "Outstanding"
        ],
        filters: [
            ReportFilter(fieldKey: "supplier", label: "Supplier"),
        ],
        allowedRoles: financeRoles + buyingRoles
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

    /// Balance Sheet — Asset / Liability / Equity account balances (normalized
    /// to their natural sign), with current-period net income folded into
    /// equity. Assets equal Liabilities + Equity because the GL balances.
    public static let balanceSheet = ReportDefinition(
        id: "balance-sheet",
        name: "Balance Sheet",
        docType: "GLEntry",
        columns: ["Section", "Account", "Amount"],
        filters: [],
        allowedRoles: financeRoles
    )

    /// Income Statement — Revenue and Expense account balances with Net Income.
    public static let incomeStatement = ReportDefinition(
        id: "income-statement",
        name: "Income Statement",
        docType: "GLEntry",
        columns: ["Section", "Account", "Amount"],
        filters: [],
        allowedRoles: financeRoles
    )

    /// General Ledger — every posted GL Entry, grouped by account in date order
    /// with a running balance. The transaction-level detail an accountant wants
    /// alongside the summary statements; part of the accountant export pack.
    public static let generalLedger = ReportDefinition(
        id: "general-ledger",
        name: "General Ledger",
        docType: "GLEntry",
        columns: ["Date", "Account", "Voucher", "Debit", "Credit", "Balance"],
        filters: [],
        allowedRoles: financeRoles
    )

    /// Posting Audit — Tier 3. Every `PostingBatch` written by the atomic
    /// posting path, problems first (failed / pending) then posted / reversed.
    /// This is the operator-facing view of posting health: because posting now
    /// commits in the same transaction as submit/cancel, a healthy system shows
    /// only `posted` and `reversed` batches and never a `failed` or orphaned
    /// `pending` one — a non-empty failed/pending section is the signal that
    /// something bypassed the atomic seam and needs attention.
    public static let postingAudit = ReportDefinition(
        id: "posting-audit",
        name: "Posting Audit",
        docType: "PostingBatch",
        columns: ["Batch", "Source Type", "Source", "Status", "Version", "Posted At", "Error"],
        filters: [],
        allowedRoles: financeRoles
    )

    public static let allReports: [ReportDefinition] = [
        salesRegister, purchaseRegister,
        stockLedgerView, stockOnHand,
        openDeliveries, pendingReceipts, todaysRoutes,
        customerAging, supplierAging,
        trialBalance, balanceSheet, incomeStatement, generalLedger,
        customerStatement, supplierLedger,
        vatSummary, postingAudit,
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
        case "stock-on-hand":
            return try runStockOnHand(engine: engine, filters: filters)
        case "open-deliveries":
            return try runOpenDeliveries(engine: engine, filters: filters)
        case "pending-receipts":
            return try runPendingReceipts(engine: engine, filters: filters)
        case "todays-routes":
            return try runTodaysRoutes(engine: engine)
        case "customer-aging":
            return try runAging(
                report: customerAging,
                docType: "CustTrans",
                partyField: "customer",
                engine: engine,
                filters: filters
            )
        case "supplier-aging":
            return try runAging(
                report: supplierAging,
                docType: "VendTrans",
                partyField: "supplier",
                engine: engine,
                filters: filters
            )
        case "trial-balance":
            return try runTrialBalance(engine: engine)
        case "balance-sheet":
            return try runBalanceSheet(engine: engine)
        case "income-statement":
            return try runIncomeStatement(engine: engine)
        case "general-ledger":
            return try runGeneralLedger(engine: engine)
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

    // MARK: - Stock on Hand (Phase 3)

    private static func runStockOnHand(
        engine: DocumentEngine,
        filters: [String: FieldValue]
    ) throws -> ReportResult {
        let bins = try engine.list(
            docType: "Bin",
            filters: filters.isEmpty ? nil : filters,
            sortBy: [
                ListSort(fieldKey: "item",      direction: .ascending),
                ListSort(fieldKey: "warehouse", direction: .ascending),
            ],
            applyRowAccess: false
        )

        let itemNames = displayNames(engine: engine, docType: "Item")
        let warehouseNames = displayNames(engine: engine, docType: "Warehouse")

        let rows: [[String?]] = bins.map { bin in
            let itemID = asString(bin.fields["item"]) ?? ""
            let warehouseID = asString(bin.fields["warehouse"]) ?? ""
            return [
                itemNames[itemID] ?? itemID,
                warehouseNames[warehouseID] ?? warehouseID,
                format(value: bin.fields["actual_qty"]),
                format(value: bin.fields["valuation_rate"]),
                format(value: bin.fields["stock_value"]),
                format(value: bin.fields["last_movement_date"]),
            ]
        }
        return ReportResult(columns: stockOnHand.columns, rows: rows)
    }

    /// Map document id → its `titleField` display value for a DocType, so
    /// reports can show names instead of raw link ids.
    private static func displayNames(engine: DocumentEngine, docType: String) -> [String: String] {
        guard let meta = HubManifest.docType(for: docType),
              let documents = try? engine.list(docType: docType, applyRowAccess: false) else {
            return [:]
        }
        var map: [String: String] = [:]
        for doc in documents {
            map[doc.id] = asString(doc.fields[meta.titleField]) ?? doc.id
        }
        return map
    }

    // MARK: - Fulfilment (Phase 4)

    private static func runOpenDeliveries(
        engine: DocumentEngine,
        filters: [String: FieldValue]
    ) throws -> ReportResult {
        let deliveries = try engine.list(
            docType: "SalesDelivery",
            filters: filters.isEmpty ? nil : filters,
            sortBy: [ListSort(fieldKey: "createdAt", direction: .descending)],
            applyRowAccess: false
        )
        let terminal: Set<String> = ["Delivered", "Cancelled"]
        let customerNames = displayNames(engine: engine, docType: "Customer")

        let rows: [[String?]] = deliveries.compactMap { doc in
            guard !terminal.contains(doc.status) else { return nil }
            let customerID = asString(doc.fields["customer"]) ?? ""
            return [
                doc.id,
                customerNames[customerID] ?? customerID,
                format(value: doc.fields["transaction_date"]),
                format(value: doc.fields["scheduled_date"]),
                statusLabel(docType: "SalesDelivery", state: doc.status),
            ]
        }
        return ReportResult(columns: openDeliveries.columns, rows: rows)
    }

    private static func runPendingReceipts(
        engine: DocumentEngine,
        filters: [String: FieldValue]
    ) throws -> ReportResult {
        let receipts = try engine.list(
            docType: "PurchaseReceipt",
            filters: filters.isEmpty ? nil : filters,
            sortBy: [ListSort(fieldKey: "createdAt", direction: .descending)],
            applyRowAccess: false
        )
        let supplierNames = displayNames(engine: engine, docType: "Supplier")

        // Pending = not yet submitted into stock (docStatus 0 / Draft).
        let rows: [[String?]] = receipts.compactMap { doc in
            guard doc.docStatus == 0 else { return nil }
            let supplierID = asString(doc.fields["supplier"]) ?? ""
            let totalQty = (doc.children["items"] ?? [])
                .reduce(0.0) { $0 + (asDouble($1.fields["qty"]) ?? 0) }
            return [
                doc.id,
                supplierNames[supplierID] ?? supplierID,
                format(value: doc.fields["transaction_date"]),
                formatCurrency(totalQty),
                statusLabel(docType: "PurchaseReceipt", state: doc.status),
            ]
        }
        return ReportResult(columns: pendingReceipts.columns, rows: rows)
    }

    private static func statusLabel(docType: String, state: String) -> String {
        HubWorkflowDisplayPolicy.policy.statusDisplay(docTypeId: docType, state: state).label
    }

    /// Delivery Routes dated today, with live stop / delivered counts.
    private static func runTodaysRoutes(engine: DocumentEngine) throws -> ReportResult {
        let routes = try engine.list(docType: "DeliveryRoute", applyRowAccess: false)
        let driverNames = displayNames(engine: engine, docType: "Driver")
        let vehicleNames = displayNames(engine: engine, docType: "Vehicle")

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start

        let rows: [[String?]] = routes.compactMap { route in
            guard let date = asDate(route.fields["route_date"]), date >= start, date < end else { return nil }
            let stops = route.children["stops"] ?? []
            let delivered = stops.filter { asString($0.fields["status"]) == "Delivered" }.count
            let driverID = asString(route.fields["driver"]) ?? ""
            let vehicleID = asString(route.fields["vehicle"]) ?? ""
            return [
                asString(route.fields["route_name"]) ?? route.id,
                driverNames[driverID] ?? (driverID.isEmpty ? "—" : driverID),
                vehicleNames[vehicleID] ?? (vehicleID.isEmpty ? "—" : vehicleID),
                asString(route.fields["status"]) ?? "Draft",
                String(stops.count),
                String(delivered),
            ]
        }
        return ReportResult(columns: todaysRoutes.columns, rows: rows)
    }

    // MARK: - AR / AP Aging

    /// Aging buckets for one party across its open invoices.
    private struct AgingBuckets {
        var b0_30:  Double = 0
        var b31_60: Double = 0
        var b61_90: Double = 0
        var b91:    Double = 0
        var total:  Double { b0_30 + b31_60 + b61_90 + b91 }

        mutating func add(days: Int, amount: Double) {
            switch days {
            case ...30:    b0_30  += amount
            case 31...60:  b31_60 += amount
            case 61...90:  b61_90 += amount
            default:       b91    += amount
            }
        }

        mutating func merge(_ other: AgingBuckets) {
            b0_30  += other.b0_30
            b31_60 += other.b31_60
            b61_90 += other.b61_90
            b91    += other.b91
        }
    }

    /// Generic receivables / payables aging. Sums each submitted invoice's
    /// `outstanding_amount` into 0-30 / 31-60 / 61-90 / 90+ buckets keyed by
    /// `partyField` ("customer" for AR, "supplier" for AP), then appends a
    /// grand-total row. Symmetric to the Flutter `_aging` routine.
    /// AR / AP aging built from the SUBLEDGER (`CustTrans` / `VendTrans`), not
    /// the source invoices' `outstanding_amount`. Reading the subledger makes
    /// the aging tie out to the GL control account: it sees every movement
    /// (invoices, payments, journal adjustments, reversals), not just
    /// invoice-driven ones. Charges (positive amounts) are aged by posting date;
    /// credits (payments / reversals, negative amounts) are applied oldest-first
    /// so the remaining, aged balance nets to the party's GL balance.
    private static func runAging(
        report: ReportDefinition,
        docType: String,
        partyField: String,
        engine: DocumentEngine,
        filters: [String: FieldValue]
    ) throws -> ReportResult {
        let entries = try engine.list(
            docType: docType,
            filters: filters.isEmpty ? nil : filters,
            applyRowAccess: false
        )

        let today = Date()
        struct Charge { let date: Date; var remaining: Double }
        var chargesByParty: [String: [Charge]] = [:]
        var creditsByParty: [String: Double] = [:]

        for entry in entries {
            guard let party = asString(entry.fields[partyField]) else { continue }
            let amount = asDouble(entry.fields["amount"]) ?? 0
            guard amount != 0 else { continue }
            let date = asDate(entry.fields["posting_date"]) ?? today
            if amount > 0 {
                chargesByParty[party, default: []].append(Charge(date: date, remaining: amount))
            } else {
                creditsByParty[party, default: 0] += -amount
            }
        }

        var perParty: [String: AgingBuckets] = [:]
        for (party, charges) in chargesByParty {
            var sortedCharges = charges.sorted { $0.date < $1.date }
            var credit = creditsByParty[party] ?? 0
            for index in sortedCharges.indices where credit > 0 {
                let applied = min(credit, sortedCharges[index].remaining)
                sortedCharges[index].remaining -= applied
                credit -= applied
            }
            var bucket = AgingBuckets()
            for charge in sortedCharges where charge.remaining > 0.0001 {
                let days = max(0, Int(today.timeIntervalSince(charge.date) / 86400))
                bucket.add(days: days, amount: charge.remaining)
            }
            if bucket.total > 0.0001 { perParty[party] = bucket }
        }

        let ordered = perParty.sorted { $0.value.total > $1.value.total }
        var total = AgingBuckets()
        var rows: [[String?]] = ordered.map { (party, b) in
            total.merge(b)
            return [
                party,
                formatCurrency(b.b0_30),
                formatCurrency(b.b31_60),
                formatCurrency(b.b61_90),
                formatCurrency(b.b91),
                formatCurrency(b.total),
            ]
        }
        // Grand-total row, matching the Flutter aging report's trailing total.
        if !rows.isEmpty {
            rows.append([
                "Total",
                formatCurrency(total.b0_30),
                formatCurrency(total.b31_60),
                formatCurrency(total.b61_90),
                formatCurrency(total.b91),
                formatCurrency(total.total),
            ])
        }
        return ReportResult(columns: report.columns, rows: rows)
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

    /// Debit / credit totals per account plus each account's root_type and
    /// display name — the shared basis for Trial Balance, Balance Sheet and
    /// Income Statement. Reversal rows carry swapped debit / credit, so they net
    /// out automatically without filtering.
    private struct GLBalances {
        var perAccount: [String: (debit: Double, credit: Double)] = [:]
        var root: [String: String] = [:]
        var name: [String: String] = [:]

        /// Account balance normalized to its natural sign: debit-positive for
        /// Asset / Expense, credit-positive for Liability / Income / Equity.
        func normalized(_ account: String) -> Double {
            let totals = perAccount[account] ?? (debit: 0, credit: 0)
            return Self.isCreditNatured(root[account] ?? "") ? (totals.credit - totals.debit) : (totals.debit - totals.credit)
        }

        /// Current-period net income (Income − Expense), folded into equity on
        /// the Balance Sheet.
        var netIncome: Double {
            var income = 0.0, expense = 0.0
            for (account, totals) in perAccount {
                switch root[account] ?? "" {
                case "Income":  income  += totals.credit - totals.debit
                case "Expense": expense += totals.debit - totals.credit
                default: break
                }
            }
            return income - expense
        }

        func accounts(in roots: Set<String>) -> [String] {
            perAccount.keys
                .filter { roots.contains(root[$0] ?? "Unclassified") }
                .sorted { (name[$0] ?? $0) < (name[$1] ?? $1) }
        }

        static func isCreditNatured(_ root: String) -> Bool {
            root == "Liability" || root == "Income" || root == "Equity"
        }
    }

    private static func glBalances(engine: DocumentEngine) throws -> GLBalances {
        var result = GLBalances()
        for entry in try engine.list(docType: "GLEntry", applyRowAccess: false) {
            guard let account = asString(entry.fields["account"]) else { continue }
            var totals = result.perAccount[account] ?? (debit: 0, credit: 0)
            // Consolidate in the company base currency: prefer the stamped base
            // amounts, falling back to the transaction amounts (which equal base
            // for same-currency / unstamped rows).
            totals.debit  += asDouble(entry.fields["base_debit"])  ?? asDouble(entry.fields["debit"])  ?? 0
            totals.credit += asDouble(entry.fields["base_credit"]) ?? asDouble(entry.fields["credit"]) ?? 0
            result.perAccount[account] = totals
        }
        for account in try engine.list(docType: "Account", applyRowAccess: false) {
            result.root[account.id] = asString(account.fields["root_type"]) ?? "Unclassified"
            result.name[account.id] = asString(account.fields["account_name"]) ?? account.id
        }
        return result
    }

    private static func runTrialBalance(engine: DocumentEngine) throws -> ReportResult {
        let balances = try glBalances(engine: engine)
        let rootOrder = ["Asset", "Liability", "Equity", "Income", "Expense", "Unclassified"]
        let sortedAccounts = balances.perAccount.keys.sorted { lhs, rhs in
            let lRoot = balances.root[lhs] ?? "Unclassified"
            let rRoot = balances.root[rhs] ?? "Unclassified"
            let lIdx = rootOrder.firstIndex(of: lRoot) ?? rootOrder.count
            let rIdx = rootOrder.firstIndex(of: rRoot) ?? rootOrder.count
            if lIdx != rIdx { return lIdx < rIdx }
            return (balances.name[lhs] ?? lhs) < (balances.name[rhs] ?? rhs)
        }

        var rows: [[String?]] = []
        var currentRoot: String? = nil
        for account in sortedAccounts {
            let totals = balances.perAccount[account] ?? (debit: 0, credit: 0)
            let root = balances.root[account] ?? "Unclassified"
            // Closing normalized to the account's natural sign so Liability /
            // Income / Equity read positive rather than negative.
            let closing = balances.normalized(account)
            let groupHeader = currentRoot == root ? "" : root
            currentRoot = root
            rows.append([
                groupHeader,
                balances.name[account] ?? account,
                formatCurrency(totals.debit),
                formatCurrency(totals.credit),
                formatCurrency(closing)
            ])
        }
        return ReportResult(columns: trialBalance.columns, rows: rows)
    }

    private static func runBalanceSheet(engine: DocumentEngine) throws -> ReportResult {
        let balances = try glBalances(engine: engine)
        var rows: [[String?]] = []

        func section(_ title: String, roots: Set<String>) -> Double {
            rows.append([title, nil, nil])
            var subtotal = 0.0
            for account in balances.accounts(in: roots) {
                let value = balances.normalized(account)
                subtotal += value
                rows.append([nil, balances.name[account] ?? account, formatCurrency(value)])
            }
            return subtotal
        }

        let assets = section("Assets", roots: ["Asset"])
        rows.append([nil, "Total Assets", formatCurrency(assets)])

        let liabilities = section("Liabilities", roots: ["Liability"])
        rows.append([nil, "Total Liabilities", formatCurrency(liabilities)])

        var equity = section("Equity", roots: ["Equity"])
        let netIncome = balances.netIncome
        equity += netIncome
        rows.append([nil, "Retained Earnings (current period)", formatCurrency(netIncome)])
        rows.append([nil, "Total Equity", formatCurrency(equity)])

        rows.append(["—", "Total Liabilities & Equity", formatCurrency(liabilities + equity)])
        return ReportResult(columns: balanceSheet.columns, rows: rows)
    }

    private static func runIncomeStatement(engine: DocumentEngine) throws -> ReportResult {
        let balances = try glBalances(engine: engine)
        var rows: [[String?]] = []

        func section(_ title: String, root: String) -> Double {
            rows.append([title, nil, nil])
            var subtotal = 0.0
            for account in balances.accounts(in: [root]) {
                let value = balances.normalized(account)
                subtotal += value
                rows.append([nil, balances.name[account] ?? account, formatCurrency(value)])
            }
            return subtotal
        }

        let revenue = section("Income", root: "Income")
        rows.append([nil, "Total Revenue", formatCurrency(revenue)])

        let expenses = section("Expenses", root: "Expense")
        rows.append([nil, "Total Expenses", formatCurrency(expenses)])

        rows.append(["—", "Net Income", formatCurrency(revenue - expenses)])
        return ReportResult(columns: incomeStatement.columns, rows: rows)
    }

    // MARK: - General Ledger detail (Phase 3)

    /// Every GL Entry, grouped by account name and ordered by date, with a
    /// per-account running balance (debit − credit, in base currency). Reversal
    /// rows carry swapped legs so a cancelled voucher nets back to zero.
    private static func runGeneralLedger(engine: DocumentEngine) throws -> ReportResult {
        let entries = try engine.list(docType: "GLEntry", applyRowAccess: false)
        let accountNames = Dictionary(
            (try engine.list(docType: "Account", applyRowAccess: false))
                .map { ($0.id, asString($0.fields["account_name"]) ?? $0.id) },
            uniquingKeysWith: { first, _ in first }
        )

        let sorted = entries.sorted { lhs, rhs in
            let lName = accountNames[asString(lhs.fields["account"]) ?? ""] ?? ""
            let rName = accountNames[asString(rhs.fields["account"]) ?? ""] ?? ""
            if lName != rName { return lName < rName }
            let lDate = asDate(lhs.fields["posting_date"]) ?? .distantPast
            let rDate = asDate(rhs.fields["posting_date"]) ?? .distantPast
            if lDate != rDate { return lDate < rDate }
            return lhs.createdAt < rhs.createdAt
        }

        var rows: [[String?]] = []
        var currentAccount: String? = nil
        var running = 0.0
        for entry in sorted {
            let account = asString(entry.fields["account"]) ?? ""
            let debit  = asDouble(entry.fields["base_debit"])  ?? asDouble(entry.fields["debit"])  ?? 0
            let credit = asDouble(entry.fields["base_credit"]) ?? asDouble(entry.fields["credit"]) ?? 0
            if currentAccount != account { running = 0; currentAccount = account }
            running += debit - credit
            rows.append([
                format(value: entry.fields["posting_date"]),
                accountNames[account] ?? account,
                asString(entry.fields["voucher_no"]) ?? "",
                formatCurrency(debit),
                formatCurrency(credit),
                formatCurrency(running),
            ])
        }
        return ReportResult(columns: generalLedger.columns, rows: rows)
    }

    // MARK: - Posting Audit (Tier 3)

    /// List every `PostingBatch`, problems first. Reads the `posting_batches`
    /// table through `PostingBatchStore` rather than the DocumentEngine — batches
    /// are a Core posting primitive, not a DocType. When no store is injected
    /// (previews / tests) it returns an empty result rather than failing.
    public static func runPostingAudit(store: PostingBatchStore?) throws -> ReportResult {
        let columns = postingAudit.columns
        guard let store else { return ReportResult(columns: columns, rows: []) }

        // Surface the statuses that demand attention first. A non-empty
        // failed / pending section means something bypassed the atomic seam.
        let statusRank: [PostingStatus: Int] = [.failed: 0, .pending: 1, .reversed: 2, .posted: 3]
        var all: [PostingBatch] = []
        for status in [PostingStatus.failed, .pending, .reversed, .posted] {
            all.append(contentsOf: try store.batches(withStatus: status, limit: 200))
        }
        let sorted = all.sorted { lhs, rhs in
            let lRank = statusRank[lhs.status] ?? 99
            let rRank = statusRank[rhs.status] ?? 99
            if lRank != rRank { return lRank < rRank }
            return lhs.sourceId < rhs.sourceId
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        let rows: [[String?]] = sorted.map { batch in
            [
                batch.id,
                batch.sourceType,
                batch.sourceId,
                batch.status.rawValue.capitalized,
                String(batch.version),
                batch.postedAt.map { dateFormatter.string(from: $0) } ?? "—",
                (batch.errorMessage?.isEmpty == false) ? batch.errorMessage : nil,
            ]
        }
        return ReportResult(columns: columns, rows: rows)
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
