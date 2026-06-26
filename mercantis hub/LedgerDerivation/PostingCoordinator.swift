//
//  PostingCoordinator.swift
//  mercantis hub
//
//  Phase 1 cutover — posts selected DocTypes INSIDE the submit/cancel
//  transaction via the Core UnitOfWork seam, so the source document and its
//  ledger rows commit together (or roll back together). This replaces the
//  post-commit event derivation for those DocTypes; everything else stays on the
//  legacy LedgerDerivationService event path until later increments.
//
//  Increment 2 added Journal Entry. Increment 3a adds the GL-only invoices
//  (Sales Invoice, Purchase Invoice). Phase 2 adds the stock DocTypes:
//  Sales Delivery (Issue + COGS at moving-average cost) and Purchase Receipt
//  (Receipt + the Dr Inventory / Cr GRNI accrual). Their Stock Ledger rows and
//  GL post inside the transaction; the derived Stock Balance (Bin) — a cache,
//  not a ledger — is recomputed post-commit by LedgerDerivationService from the
//  committed rows. Perpetual inventory (GRNI) is opt-in: the accrual posts only
//  when a GRNI account is mapped, and the Purchase Invoice then clears GRNI for
//  its stock lines. POS Invoice (cash sale: stock issue + COGS + Dr Cash /
//  Cr Income / Cr VAT) shares the outgoing-stock derivation. Stock Entry later.
//
//  The DocTypes posted here are listed in `atomicDocTypes`, which
//  LedgerDerivationService skips so there is no double-posting.
//

import Foundation
import SwiftUI
import MercantisCore

/// Posting failures that abort (and roll back) a submit/cancel.
public nonisolated enum PostingError: Error {
    /// The GL legs of a batch did not balance — debits must equal credits.
    case unbalanced(debit: Double, credit: Double)
}

/// Pre-posting guard failures: the submit is rejected (and the transaction
/// rolled back) before any ledger rows are written. Surfaced to the operator
/// via `LocalizedError`.
public nonisolated enum PostingValidationError: LocalizedError {
    /// The posting date falls in a fiscal period that has been closed.
    case closedPeriod(period: String)
    /// No fiscal year covers the posting date (and at least one is defined).
    case noOpenPeriod(date: Date)
    /// Issuing this line would drive stock negative and the company has not
    /// opted into negative stock.
    case insufficientStock(item: String, warehouse: String, onHand: Double, requested: Double)

    public var errorDescription: String? {
        switch self {
        case .closedPeriod(let period):
            return "The fiscal period \"\(period)\" is closed — documents can't be posted into it."
        case .noOpenPeriod(let date):
            return "No fiscal year covers \(Self.dateText(date)). Create and activate a fiscal year for this date before posting."
        case .insufficientStock(let item, let warehouse, let onHand, let requested):
            return "Not enough stock of \(item) in \(warehouse): \(Self.qtyText(requested)) requested but \(Self.qtyText(onHand)) on hand. Receive stock first, or enable “Allow Negative Stock” in the Business Profile."
        }
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private static func qtyText(_ qty: Double) -> String { String(format: "%g", qty) }
}

/// Builds the in-transaction posting closures passed to `DocumentEngine.submit`
/// / `cancel` for the DocTypes it owns.
///
/// `nonisolated` so it aligns with MercantisCore's nonisolated engine API and
/// the non-`@Sendable` `inTransaction` closure it produces, matching the
/// LedgerDerivationService pattern.
nonisolated final class PostingCoordinator {

    /// DocTypes posted atomically here — and therefore skipped by the legacy
    /// event path. Single source of truth shared with LedgerDerivationService.
    static let atomicDocTypes: Set<String> = ["JournalEntry", "SalesInvoice", "PurchaseInvoice", "PaymentEntry", "SalesDelivery", "PurchaseReceipt", "POSInvoice", "StockEntry"]

    /// Atomic DocTypes that move stock — LedgerDerivationService recomputes their
    /// Stock Balance (Bin) post-commit (posting itself is done in-transaction).
    static let atomicStockDocTypes: Set<String> = ["SalesDelivery", "PurchaseReceipt", "POSInvoice", "StockEntry"]

    /// Tolerance for the balanced-GL check (currency rounding).
    private static let balanceTolerance = 0.005

    private let engine: DocumentEngine

    init(engine: DocumentEngine) {
        self.engine = engine
    }

    /// Read-side inputs resolved OUTSIDE the write transaction (a read inside the
    /// write would be reentrant) and captured for posting: company-default
    /// accounts, the invoices a payment settles, and the per-line stock cost
    /// basis for atomic stock DocTypes.
    private struct PostingInputs {
        var fallbackVatAccount: String?
        var referencedInvoices: [String: Document] = [:]
        /// Per-line cost basis keyed by child `rowIndex` (Sales Delivery):
        /// moving-average cost on submit, original issue cost on cancel.
        var stockCostBasis: [Int: Double] = [:]
        var cogsAccount: String?
        var inventoryAccount: String?
        /// GRNI clearing account (perpetual inventory). Nil unless the operator
        /// has mapped it on the Business Profile — when nil the Purchase
        /// Receipt / Invoice posting stays on the legacy expense-based path.
        var grniAccount: String?
        /// item id → is_stock_item for the document's lines, so the GRNI loop
        /// can size the inventory accrual (Receipt) and the clearing leg
        /// (Invoice) to the stock-item portion only.
        var stockItemFlags: [String: Bool] = [:]
        /// Company-default fallbacks for the POS cash sale legs (the document's
        /// own cash_account / income_account take precedence when set).
        var incomeAccount: String?
        var cashAccount: String?
        /// A pre-posting guard failure (closed period / insufficient stock),
        /// resolved OUTSIDE the write transaction and thrown inside it so the
        /// submit rolls back. Only set on submit (never on reversal).
        var submitValidationError: PostingValidationError?
        /// Per-line UOM → stock-UOM conversion factor, keyed by child rowIndex.
        /// Absent entries mean factor 1 (line already in stock UOM). Stock
        /// quantities and per-unit rates are converted to the stock UOM so bins
        /// and valuation stay consistent.
        var uomFactors: [Int: Double] = [:]
        /// Exchange rate from the document's transaction currency to the company
        /// base currency (1 when same-currency). GL / subledger rows for the
        /// purely transaction-currency financial DocTypes are stamped with base
        /// amounts (amount × rate) so reporting can consolidate in base currency.
        var conversionRate: Double = 1
    }

    /// DocTypes whose GL / subledger legs are all in the document's transaction
    /// currency, so multiplying by the conversion rate yields correct base
    /// amounts. Stock DocTypes are excluded: their COGS / inventory legs are
    /// already in base currency (the moving-average cost), so base == amount.
    private static let baseStampDocTypes: Set<String> = ["JournalEntry", "SalesInvoice", "PurchaseInvoice", "PaymentEntry"]

    /// The `inTransaction` closure for submitting `doc`, or nil when `doc`'s
    /// DocType is not posted atomically here (caller submits normally).
    func submitClosure(for doc: Document) -> ((UnitOfWork) throws -> Void)? {
        guard Self.atomicDocTypes.contains(doc.docType) else { return nil }
        let engine = self.engine
        let inputs = Self.makeInputs(for: doc, reversal: false, engine: engine)
        return { uow in try Self.post(doc, reversal: false, inputs: inputs, engine: engine, in: uow) }
    }

    /// The `inTransaction` closure for cancelling `doc` (writes reversal rows).
    func cancelClosure(for doc: Document) -> ((UnitOfWork) throws -> Void)? {
        guard Self.atomicDocTypes.contains(doc.docType) else { return nil }
        let engine = self.engine
        let inputs = Self.makeInputs(for: doc, reversal: true, engine: engine)
        return { uow in try Self.post(doc, reversal: true, inputs: inputs, engine: engine, in: uow) }
    }

    // MARK: - Read-side inputs (resolved outside the write transaction)

    private static func makeInputs(for doc: Document, reversal: Bool, engine: DocumentEngine) -> PostingInputs {
        var inputs = PostingInputs(fallbackVatAccount: companyDefault("default_vat_account", engine: engine))
        inputs.referencedInvoices = referencedInvoices(for: doc, engine: engine)
        inputs.grniAccount = companyDefault("default_grni_account", engine: engine)
        let rate = asDouble(doc.fields["conversion_rate"]) ?? 1
        inputs.conversionRate = rate > 0 ? rate : 1
        if atomicStockDocTypes.contains(doc.docType) {
            inputs.cogsAccount = companyDefault("default_expense_account", engine: engine)
            inputs.inventoryAccount = companyDefault("default_stock_account", engine: engine)
            inputs.uomFactors = uomFactors(for: doc, engine: engine)
            inputs.stockCostBasis = stockCostBasis(for: doc, reversal: reversal, engine: engine, uomFactors: inputs.uomFactors)
        }
        // Per-line stock/service classification for the GRNI loop: Purchase
        // Receipt accrues to GRNI for stock-item lines; Purchase Invoice clears
        // GRNI for the same lines and expenses the rest.
        if doc.docType == "PurchaseReceipt" || doc.docType == "PurchaseInvoice" {
            inputs.stockItemFlags = stockItemFlags(for: doc, engine: engine)
        }
        if doc.docType == "POSInvoice" {
            inputs.incomeAccount = companyDefault("default_income_account", engine: engine)
            inputs.cashAccount = companyDefault("default_cash_bank_account", engine: engine)
        }
        // Pre-posting guards (submit only): reject posting into a closed/absent
        // fiscal period, or an issue that would drive stock negative. Resolved
        // here, OUTSIDE the write transaction; `post` throws it inside so the
        // submit rolls back. Reversals are exempt (a cancel must always be able
        // to unwind, and adding stock back can't go negative).
        if !reversal {
            inputs.submitValidationError = fiscalPeriodViolation(for: doc, engine: engine)
                ?? stockAvailabilityViolation(for: doc, engine: engine, uomFactors: inputs.uomFactors)
        }
        return inputs
    }

    /// Reject a posting whose date falls in a closed fiscal period, or — when at
    /// least one fiscal year is defined — a date no fiscal year covers. When no
    /// fiscal years exist at all the guard is dormant, so a fresh / unconfigured
    /// install is never blocked.
    private static func fiscalPeriodViolation(for doc: Document, engine: DocumentEngine) -> PostingValidationError? {
        guard let postingDate = asDate(doc.fields["posting_date"] ?? doc.fields["transaction_date"]) else { return nil }
        let fiscalYears = (try? engine.list(docType: "FiscalYear")) ?? []
        guard !fiscalYears.isEmpty else { return nil }
        let covering = fiscalYears.first { year in
            guard let start = asDate(year.fields["year_start_date"]),
                  let end = asDate(year.fields["year_end_date"]) else { return false }
            return start <= postingDate && postingDate <= end
        }
        guard let covering else { return .noOpenPeriod(date: postingDate) }
        if case .bool(true)? = covering.fields["is_closed"] {
            return .closedPeriod(period: nonEmptyString(covering.fields["year_name"]) ?? covering.id)
        }
        return nil
    }

    /// Reject an outgoing-stock submit that would drive a bin negative, unless
    /// the company has opted into negative stock. Requested quantities are
    /// aggregated per (item, warehouse) across the lines and compared to the
    /// current on-hand balance (read OUTSIDE the write transaction).
    private static func stockAvailabilityViolation(for doc: Document, engine: DocumentEngine, uomFactors: [Int: Double]) -> PostingValidationError? {
        guard ["SalesDelivery", "POSInvoice", "StockEntry"].contains(doc.docType) else { return nil }
        if allowsNegativeStock(engine: engine) { return nil }
        let defaultWarehouse = nonEmptyString(doc.fields["set_warehouse"])
            ?? nonEmptyString(doc.fields["warehouse"])
        var requested: [String: (item: String, warehouse: String, qty: Double)] = [:]
        for row in doc.children["items"] ?? [] {
            guard let itemId = nonEmptyString(row.fields["item"]) else { continue }
            // Compare on-hand (stock UOM) against the requested qty in stock UOM.
            let qty = (asDouble(row.fields["qty"]) ?? 0) * (uomFactors[row.rowIndex] ?? 1)
            guard qty > 0 else { continue }
            // The warehouse stock LEAVES: the line / default warehouse for a
            // fulfilment doc, the source warehouse for a Stock Entry (the target
            // leg only adds stock).
            let issueWarehouse = doc.docType == "StockEntry"
                ? nonEmptyString(row.fields["source_warehouse"])
                : nonEmptyString(row.fields["warehouse"]) ?? defaultWarehouse
            guard let whId = issueWarehouse else { continue }
            let key = "\(itemId)|\(whId)"
            let prior = requested[key]?.qty ?? 0
            requested[key] = (itemId, whId, prior + qty)
        }
        guard !requested.isEmpty else { return nil }
        let stockBalance = StockBalanceService(engine: engine)
        for entry in requested.values {
            let bin = (try? stockBalance.balance(item: entry.item, warehouse: entry.warehouse)) ?? nil
            let onHand = bin?.actualQty ?? 0
            if entry.qty > onHand + 0.0000001 {
                return .insufficientStock(item: entry.item, warehouse: entry.warehouse, onHand: onHand, requested: entry.qty)
            }
        }
        return nil
    }

    private static func allowsNegativeStock(engine: DocumentEngine) -> Bool {
        guard let company = (try? engine.list(docType: "Company"))?.first else { return false }
        if case .bool(true)? = company.fields["allow_negative_stock"] { return true }
        return false
    }

    private static func asDate(_ value: FieldValue?) -> Date? {
        if case .date(let d)? = value { return d }
        return nil
    }

    /// Map of item id → `is_stock_item` for the document's lines, read OUTSIDE
    /// the write transaction. An absent / non-bool flag defaults to true so an
    /// item still counts as stock (matching the field's default).
    private static func stockItemFlags(for doc: Document, engine: DocumentEngine) -> [String: Bool] {
        var flags: [String: Bool] = [:]
        for row in doc.children["items"] ?? [] {
            guard let itemId = nonEmptyString(row.fields["item"]), flags[itemId] == nil else { continue }
            let item = try? engine.fetch(docType: "Item", id: itemId)
            if case .bool(let isStock)? = item?.fields["is_stock_item"] {
                flags[itemId] = isStock
            } else {
                flags[itemId] = true
            }
        }
        return flags
    }

    /// Per-line conversion factor from the line UOM to the item's stock UOM,
    /// keyed by child rowIndex, read OUTSIDE the write transaction. Only lines
    /// whose UOM differs from the stock UOM and have a defined conversion get an
    /// entry; everything else is treated as factor 1. `qty_in_stock = line_qty ×
    /// factor`.
    private static func uomFactors(for doc: Document, engine: DocumentEngine) -> [Int: Double] {
        var factors: [Int: Double] = [:]
        var itemCache: [String: Document?] = [:]
        for row in doc.children["items"] ?? [] {
            guard let lineUom = nonEmptyString(row.fields["uom"]),
                  let itemId = nonEmptyString(row.fields["item"]) else { continue }
            let item: Document?
            if let cached = itemCache[itemId] {
                item = cached
            } else {
                item = try? engine.fetch(docType: "Item", id: itemId)
                itemCache[itemId] = item
            }
            guard let item else { continue }
            // Already in the stock UOM — no conversion.
            if let stockUom = nonEmptyString(item.fields["stock_uom"]), stockUom == lineUom { continue }
            if let conversion = (item.children["uoms"] ?? []).first(where: { nonEmptyString($0.fields["uom"]) == lineUom }),
               let factor = asDouble(conversion.fields["conversion_factor"]), factor > 0 {
                factors[row.rowIndex] = factor
            }
        }
        return factors
    }

    /// Per-line valuation rate for a Sales Delivery's stock issue, read OUTSIDE
    /// the write transaction. On submit the warehouse MOVING-AVERAGE cost (never
    /// the selling rate); on cancel the ORIGINAL issue cost (read back from the
    /// issue SLE) so the reversal's stock value and COGS net to zero. Keyed by
    /// child `rowIndex`.
    private static func stockCostBasis(for doc: Document, reversal: Bool, engine: DocumentEngine, uomFactors: [Int: Double]) -> [Int: Double] {
        guard doc.docType == "SalesDelivery" || doc.docType == "POSInvoice" else { return [:] }
        let defaultWarehouse = nonEmptyString(doc.fields["set_warehouse"])
            ?? nonEmptyString(doc.fields["warehouse"])
        let stockBalance = StockBalanceService(engine: engine)
        var basis: [Int: Double] = [:]
        // Caches so a multi-line document reads each item's method / ledger once,
        // and FIFO layers are consumed across lines of the same (item, warehouse).
        var isFIFOByItem: [String: Bool] = [:]
        var fifoRowsByKey: [String: [StockBalanceCalculator.Row]] = [:]
        var fifoConsumedByKey: [String: Double] = [:]
        for row in doc.children["items"] ?? [] {
            guard let itemId = nonEmptyString(row.fields["item"]) else { continue }
            guard let whId = nonEmptyString(row.fields["warehouse"]) ?? defaultWarehouse else { continue }
            let unitCost: Double
            if reversal {
                // Reversal uses the ORIGINAL issue cost (read back from the issue
                // SLE) so the cancellation's stock value and COGS net to zero —
                // method-independent.
                let origRate = (try? engine.fetch(docType: "StockLedgerEntry", id: "SLE-\(doc.id)-\(row.rowIndex)"))?.fields["valuation_rate"]
                unitCost = asDouble(origRate) ?? 0
            } else {
                let isFIFO: Bool
                if let cached = isFIFOByItem[itemId] {
                    isFIFO = cached
                } else {
                    let item = try? engine.fetch(docType: "Item", id: itemId)
                    isFIFO = asString(item?.fields["valuation_method"]) == "FIFO"
                    isFIFOByItem[itemId] = isFIFO
                }
                if isFIFO {
                    let key = "\(itemId)|\(whId)"
                    let ledgerRows: [StockBalanceCalculator.Row]
                    if let cached = fifoRowsByKey[key] {
                        ledgerRows = cached
                    } else {
                        ledgerRows = stockLedgerRows(item: itemId, warehouse: whId, engine: engine)
                        fifoRowsByKey[key] = ledgerRows
                    }
                    let stockQty = (asDouble(row.fields["qty"]) ?? 0) * (uomFactors[row.rowIndex] ?? 1)
                    let consumed = fifoConsumedByKey[key] ?? 0
                    unitCost = StockBalanceCalculator.fifoUnitCost(
                        item: itemId, warehouse: whId, rows: ledgerRows,
                        alreadyConsumed: consumed, issueQty: stockQty)
                    fifoConsumedByKey[key] = consumed + stockQty
                } else {
                    let bin = (try? stockBalance.balance(item: itemId, warehouse: whId)) ?? nil
                    unitCost = bin?.valuationRate ?? asDouble(row.fields["valuation_rate"]) ?? 0
                }
            }
            basis[row.rowIndex] = unitCost
        }
        return basis
    }

    /// Read the Stock Ledger rows for one (item, warehouse) and map them into the
    /// calculator's `Row` shape, for the FIFO cost replay. Read OUTSIDE the write
    /// transaction.
    private static func stockLedgerRows(item: String, warehouse: String, engine: DocumentEngine) -> [StockBalanceCalculator.Row] {
        let entries = (try? engine.list(
            docType: "StockLedgerEntry",
            filters: ["item": .string(item), "warehouse": .string(warehouse)],
            applyRowAccess: false
        )) ?? []
        return entries.map { entry in
            StockBalanceCalculator.Row(
                item: item, warehouse: warehouse,
                qtyChange: asDouble(entry.fields["qty_change"]) ?? 0,
                valuationRate: asDouble(entry.fields["valuation_rate"]),
                postingDate: asDate(entry.fields["posting_date"])
            )
        }
    }

    // MARK: - Posting

    private static func post(
        _ doc: Document, reversal: Bool, inputs: PostingInputs,
        engine: DocumentEngine, in uow: UnitOfWork
    ) throws {
        // Idempotency: one batch per (source, direction). Post is v1, reverse v2,
        // so cancel doesn't collide with the original and a re-fire is a no-op.
        let version = reversal ? 2 : 1
        let batchId = PostingBatch.makeID(sourceId: doc.id, version: version)
        if try uow.postingBatchExists(id: batchId) { return }

        // Pre-posting guards (resolved outside the transaction in makeInputs):
        // throw here, inside the write, so a closed-period or negative-stock
        // submit rolls back with nothing written.
        if !reversal, let violation = inputs.submitValidationError { throw violation }

        let ledgerDocs: [Document]
        switch doc.docType {
        case "JournalEntry":    ledgerDocs = journalEntryRows(doc, reversal: reversal)
        case "SalesInvoice":    ledgerDocs = salesInvoiceRows(doc, reversal: reversal, fallbackVatAccount: inputs.fallbackVatAccount)
        case "PurchaseInvoice": ledgerDocs = purchaseInvoiceRows(doc, reversal: reversal, fallbackVatAccount: inputs.fallbackVatAccount, grniAccount: inputs.grniAccount, stockItemFlags: inputs.stockItemFlags)
        case "PaymentEntry":    ledgerDocs = paymentEntryRows(doc, reversal: reversal, referencedInvoices: inputs.referencedInvoices)
        case "SalesDelivery":   ledgerDocs = salesDeliveryRows(doc, reversal: reversal, costBasis: inputs.stockCostBasis, cogsAccount: inputs.cogsAccount, inventoryAccount: inputs.inventoryAccount, uomFactors: inputs.uomFactors)
        case "PurchaseReceipt": ledgerDocs = purchaseReceiptRows(doc, reversal: reversal, stockItemFlags: inputs.stockItemFlags, inventoryAccount: inputs.inventoryAccount, grniAccount: inputs.grniAccount, uomFactors: inputs.uomFactors)
        case "POSInvoice":      ledgerDocs = posInvoiceRows(doc, reversal: reversal, costBasis: inputs.stockCostBasis, cogsAccount: inputs.cogsAccount, inventoryAccount: inputs.inventoryAccount, incomeAccount: inputs.incomeAccount, cashAccount: inputs.cashAccount, fallbackVatAccount: inputs.fallbackVatAccount, uomFactors: inputs.uomFactors)
        case "StockEntry":      ledgerDocs = stockEntryRows(doc, reversal: reversal, uomFactors: inputs.uomFactors)
        default:                return
        }

        // Stamp base-currency amounts on the transaction-currency financial
        // DocTypes so reports can consolidate in the company base currency.
        let stampedDocs = baseStampDocTypes.contains(doc.docType)
            ? stampBaseAmounts(ledgerDocs, rate: inputs.conversionRate, currency: doc.fields["currency"])
            : ledgerDocs

        // Payment Entry's GL legs can legitimately be single-sided in some
        // account models (the contra side lives in the subledger), and the
        // legacy event path never balance-checked it — so don't reject it here.
        let enforceBalance = doc.docType != "PaymentEntry"
        try commit(stampedDocs, sourceType: doc.docType, source: doc, reversal: reversal, version: version, enforceBalance: enforceBalance, engine: engine, in: uow)
    }

    /// Add base-currency amounts to GL Entry and subledger rows: `base_debit` /
    /// `base_credit` = amount × rate, the source `currency`, and the rate. Only
    /// applied to DocTypes whose legs are all in transaction currency.
    private static func stampBaseAmounts(_ docs: [Document], rate: Double, currency: FieldValue?) -> [Document] {
        docs.map { row in
            var row = row
            switch row.docType {
            case "GLEntry":
                let debit  = asDouble(row.fields["debit"])  ?? 0
                let credit = asDouble(row.fields["credit"]) ?? 0
                row.fields["conversion_rate"] = .double(rate)
                row.fields["base_debit"]  = .double(debit * rate)
                row.fields["base_credit"] = .double(credit * rate)
                if let currency { row.fields["currency"] = currency }
            case "CustTrans", "VendTrans":
                let amount = asDouble(row.fields["amount"]) ?? 0
                row.fields["conversion_rate"] = .double(rate)
                row.fields["base_amount"] = .double(amount * rate)
            default:
                break
            }
            return row
        }
    }

    /// Validate the GL legs balance (when required), then write every ledger row
    /// and the PostingBatch in the unit of work. A failed balance (or any write)
    /// throws, rolling the whole submit/cancel back.
    private static func commit(
        _ ledgerDocs: [Document],
        sourceType: String,
        source: Document,
        reversal: Bool,
        version: Int,
        enforceBalance: Bool,
        engine: DocumentEngine,
        in uow: UnitOfWork
    ) throws {
        if enforceBalance {
            var totalDebit = 0.0
            var totalCredit = 0.0
            for row in ledgerDocs where row.docType == "GLEntry" {
                totalDebit  += asDouble(row.fields["debit"]) ?? 0
                totalCredit += asDouble(row.fields["credit"]) ?? 0
            }
            guard abs(totalDebit - totalCredit) < balanceTolerance else {
                throw PostingError.unbalanced(debit: totalDebit, credit: totalCredit)
            }
        }

        for row in ledgerDocs {
            try engine.writeDocument(row, action: reversal ? "reverse" : "post", in: uow)
        }

        try uow.recordPostingBatch(PostingBatch(
            id: PostingBatch.makeID(sourceId: source.id, version: version),
            sourceType: sourceType,
            sourceId: source.id,
            status: reversal ? .reversed : .posted,
            version: version,
            postedAt: Date(),
            reversalOfBatch: reversal ? PostingBatch.makeID(sourceId: source.id, version: 1) : nil
        ))
    }

    // MARK: - Row builders (mirror LedgerDerivationService.derive*)

    static func journalEntryRows(_ doc: Document, reversal: Bool) -> [Document] {
        let postingDate = doc.fields["posting_date"] ?? .date(Date())
        let currency = doc.fields["company_currency"]
        var docs: [Document] = []

        for row in doc.children["accounts"] ?? [] {
            guard let account = row.fields["account"] else { continue }
            let debit  = reversal ? (row.fields["credit"] ?? .double(0)) : (row.fields["debit"]  ?? .double(0))
            let credit = reversal ? (row.fields["debit"]  ?? .double(0)) : (row.fields["credit"] ?? .double(0))

            docs.append(glRow(
                id: "GL-\(doc.id)-\(row.rowIndex)\(suffix(reversal))",
                postingDate: postingDate, account: account,
                debit: debit, credit: credit,
                partyType: asString(row.fields["party_type"]), party: row.fields["party"],
                costCenter: row.fields["cost_center"],
                voucherType: "JournalEntry", voucherNo: doc.id, reversal: reversal, company: doc.company
            ))

            guard case .string(let partyTypeValue)? = row.fields["party_type"],
                  case .string(let partyId)? = row.fields["party"], !partyId.isEmpty else { continue }
            let net = (asDouble(debit) ?? 0) - (asDouble(credit) ?? 0)
            guard net != 0 else { continue }

            switch partyTypeValue {
            case "Customer":
                docs.append(custTransRow(
                    id: "CT-\(doc.id)-\(row.rowIndex)\(suffix(reversal))",
                    transType: "Adjustment", customer: .string(partyId),
                    postingDate: postingDate, dueDate: nil, amount: .double(net),
                    currency: currency, voucherType: "JournalEntry", voucherNo: doc.id,
                    reversal: reversal, company: doc.company
                ))
            case "Supplier":
                docs.append(vendTransRow(
                    id: "VT-\(doc.id)-\(row.rowIndex)\(suffix(reversal))",
                    transType: "Adjustment", supplier: .string(partyId),
                    postingDate: postingDate, dueDate: nil, amount: .double(-net),
                    currency: currency, voucherType: "JournalEntry", voucherNo: doc.id,
                    reversal: reversal, company: doc.company
                ))
            default:
                break
            }
        }
        return docs
    }

    static func salesInvoiceRows(_ doc: Document, reversal: Bool, fallbackVatAccount: String?) -> [Document] {
        guard let receivable = doc.fields["debit_to"],
              let income = doc.fields["income_account"] else { return [] }
        let postingDate = doc.fields["transaction_date"] ?? .date(Date())
        let amount   = doc.fields["grand_total"] ?? .double(0)
        let costCenter = doc.fields["cost_center"]
        let customer = doc.fields["customer"]
        let currency = doc.fields["currency"]
        let dueDate  = doc.fields["due_date"]
        let taxRowsChildren = doc.children["taxes"] ?? []
        let grand = asDouble(amount) ?? 0
        let net   = asDouble(doc.fields["net_total"]) ?? (grand - totalTax(taxRowsChildren))

        var docs: [Document] = []
        // Dr AR (gross), Cr Income (net).
        docs.append(glRow(
            id: "GL-\(doc.id)-debit\(suffix(reversal))", postingDate: postingDate, account: receivable,
            debit: .double(reversal ? 0 : grand), credit: .double(reversal ? grand : 0),
            partyType: "Customer", party: customer, costCenter: costCenter,
            voucherType: "SalesInvoice", voucherNo: doc.id, reversal: reversal, company: doc.company
        ))
        docs.append(glRow(
            id: "GL-\(doc.id)-credit\(suffix(reversal))", postingDate: postingDate, account: income,
            debit: .double(reversal ? net : 0), credit: .double(reversal ? 0 : net),
            partyType: nil, party: nil, costCenter: costCenter,
            voucherType: "SalesInvoice", voucherNo: doc.id, reversal: reversal, company: doc.company
        ))
        docs += taxRowDocs(doc, rows: taxRowsChildren, party: customer, partyTypeValue: "Customer", isOutput: true, reversal: reversal, fallbackVatAccount: fallbackVatAccount)

        if let customerValue = customer {
            docs.append(custTransRow(
                id: "CT-\(doc.id)\(suffix(reversal))", transType: reversal ? "CreditNote" : "Invoice",
                customer: customerValue, postingDate: postingDate, dueDate: dueDate,
                amount: signed(amount, negate: reversal), currency: currency,
                voucherType: "SalesInvoice", voucherNo: doc.id, reversal: reversal, company: doc.company
            ))
        }
        return docs
    }

    static func purchaseInvoiceRows(
        _ doc: Document, reversal: Bool, fallbackVatAccount: String?,
        grniAccount: String?, stockItemFlags: [String: Bool]
    ) -> [Document] {
        guard let payable = doc.fields["credit_to"],
              let expense = doc.fields["expense_account"] else { return [] }
        let postingDate = doc.fields["transaction_date"] ?? .date(Date())
        let amount   = doc.fields["grand_total"] ?? .double(0)
        let costCenter = doc.fields["cost_center"]
        let supplier = doc.fields["supplier"]
        let currency = doc.fields["currency"]
        let dueDate  = doc.fields["due_date"]
        let taxRowsChildren = doc.children["taxes"] ?? []
        let grand = asDouble(amount) ?? 0
        let net   = asDouble(doc.fields["net_total"]) ?? (grand - totalTax(taxRowsChildren))

        var docs: [Document] = []
        // Cr AP (gross).
        docs.append(glRow(
            id: "GL-\(doc.id)-credit\(suffix(reversal))", postingDate: postingDate, account: payable,
            debit: .double(reversal ? grand : 0), credit: .double(reversal ? 0 : grand),
            partyType: "Supplier", party: supplier, costCenter: costCenter,
            voucherType: "PurchaseInvoice", voucherNo: doc.id, reversal: reversal, company: doc.company
        ))

        // Dr side (net of tax). With a GRNI account mapped, the value of the
        // stock-item lines clears the receipt accrual (Dr GRNI) and only the
        // remainder hits Expense; without it the whole net is Dr Expense, so
        // the books are byte-for-byte the legacy behaviour. `stockNet` is
        // clamped to `net` so a discount can never over-clear GRNI.
        // Floor at 0 so a negative stock line (a return / credit line on the
        // invoice) can never flip the GRNI leg to a credit; clamp to `net` so a
        // discount can never over-clear it.
        let stockNet = grniAccount == nil ? 0 : max(0, min(net, stockLineNet(doc, stockItemFlags: stockItemFlags)))
        let expenseNet = net - stockNet
        if let grniAccount, stockNet > 0.0001 {
            docs.append(glRow(
                id: "GL-\(doc.id)-grni\(suffix(reversal))", postingDate: postingDate, account: .string(grniAccount),
                debit: .double(reversal ? 0 : stockNet), credit: .double(reversal ? stockNet : 0),
                partyType: nil, party: nil, costCenter: costCenter,
                voucherType: "PurchaseInvoice", voucherNo: doc.id, reversal: reversal, company: doc.company
            ))
        }
        if abs(expenseNet) > 0.0001 || stockNet <= 0.0001 {
            docs.append(glRow(
                id: "GL-\(doc.id)-debit\(suffix(reversal))", postingDate: postingDate, account: expense,
                debit: .double(reversal ? 0 : expenseNet), credit: .double(reversal ? expenseNet : 0),
                partyType: nil, party: nil, costCenter: costCenter,
                voucherType: "PurchaseInvoice", voucherNo: doc.id, reversal: reversal, company: doc.company
            ))
        }
        docs += taxRowDocs(doc, rows: taxRowsChildren, party: supplier, partyTypeValue: "Supplier", isOutput: false, reversal: reversal, fallbackVatAccount: fallbackVatAccount)

        if let supplierValue = supplier {
            docs.append(vendTransRow(
                id: "VT-\(doc.id)\(suffix(reversal))", transType: reversal ? "CreditNote" : "Invoice",
                supplier: supplierValue, postingDate: postingDate, dueDate: dueDate,
                amount: signed(amount, negate: reversal), currency: currency,
                voucherType: "PurchaseInvoice", voucherNo: doc.id, reversal: reversal, company: doc.company
            ))
        }
        return docs
    }

    /// Mirrors `deriveStockDocument` for an outgoing Sales Delivery: a Stock
    /// Ledger Issue row per line (-qty on submit, +qty on reversal) carrying the
    /// pre-resolved `costBasis` as `valuation_rate`, plus the inventory GL —
    /// Dr COGS / Cr Inventory at moving-average cost (reversal flips). The
    /// derived Stock Balance (Bin) is recomputed post-commit by
    /// LedgerDerivationService, since it reads the now-committed ledger rows.
    private static func salesDeliveryRows(
        _ doc: Document, reversal: Bool, costBasis: [Int: Double],
        cogsAccount: String?, inventoryAccount: String?, uomFactors: [Int: Double]
    ) -> [Document] {
        stockIssueRows(doc, voucherType: "SalesDelivery", reversal: reversal,
                       costBasis: costBasis, cogsAccount: cogsAccount, inventoryAccount: inventoryAccount,
                       uomFactors: uomFactors)
    }

    /// Shared outgoing-stock derivation for Sales Delivery and POS Invoice: a
    /// Stock Ledger Issue row per line (-qty on submit, +qty on reversal)
    /// carrying the pre-resolved `costBasis` as `valuation_rate`, plus the
    /// inventory GL — Dr COGS / Cr Inventory at moving-average cost (reversal
    /// flips). Skipped when the COGS / Stock accounts are unset (mirrors the
    /// legacy event path). The derived Stock Balance (Bin) is recomputed
    /// post-commit by LedgerDerivationService from the committed ledger rows.
    static func stockIssueRows(
        _ doc: Document, voucherType: String, reversal: Bool, costBasis: [Int: Double],
        cogsAccount: String?, inventoryAccount: String?, uomFactors: [Int: Double] = [:]
    ) -> [Document] {
        let postingDate = doc.fields["posting_date"] ?? doc.fields["transaction_date"] ?? .date(Date())
        let postingTime = doc.fields["posting_time"]
        let defaultWarehouse = nonEmptyString(doc.fields["set_warehouse"])
            ?? nonEmptyString(doc.fields["warehouse"])

        var docs: [Document] = []
        var cogsTotal = 0.0
        for row in doc.children["items"] ?? [] {
            guard let itemId = nonEmptyString(row.fields["item"]) else { continue }
            guard let whId = nonEmptyString(row.fields["warehouse"]) ?? defaultWarehouse else { continue }
            // Convert the line qty to the item's stock UOM; the cost basis is
            // already per stock UOM (read from the bin).
            let stockQty = (asDouble(row.fields["qty"]) ?? 0) * (uomFactors[row.rowIndex] ?? 1)
            // Issue: -qty on submit, +qty on reversal.
            let signedQty = signed(.double(stockQty), negate: !reversal)
            let unitCost = costBasis[row.rowIndex] ?? 0
            docs.append(sleRow(
                id: "SLE-\(doc.id)-\(row.rowIndex)\(suffix(reversal))",
                transType: "Issue", item: .string(itemId), warehouse: .string(whId),
                postingDate: postingDate, postingTime: postingTime,
                voucherType: voucherType, voucherNo: doc.id,
                qtyChange: signedQty, rate: .double(unitCost), reversal: reversal, company: doc.company
            ))
            cogsTotal += stockQty * unitCost
        }

        if abs(cogsTotal) > 0.0001, let cogsAccount, let inventoryAccount {
            let amount = FieldValue.double(cogsTotal)
            let zero = FieldValue.double(0)
            docs.append(glRow(
                id: "GL-\(doc.id)-cogs\(suffix(reversal))", postingDate: postingDate, account: .string(cogsAccount),
                debit: reversal ? zero : amount, credit: reversal ? amount : zero,
                partyType: nil, party: nil, costCenter: nil,
                voucherType: voucherType, voucherNo: doc.id, reversal: reversal, company: doc.company
            ))
            docs.append(glRow(
                id: "GL-\(doc.id)-inventory\(suffix(reversal))", postingDate: postingDate, account: .string(inventoryAccount),
                debit: reversal ? amount : zero, credit: reversal ? zero : amount,
                partyType: nil, party: nil, costCenter: nil,
                voucherType: voucherType, voucherNo: doc.id, reversal: reversal, company: doc.company
            ))
        }
        return docs
    }

    /// POS Invoice is a cash sale: the outgoing stock + COGS (shared with Sales
    /// Delivery) plus the financial legs — Dr Cash (gross) / Cr Income (net) /
    /// Cr Output VAT (+ TaxTrans). No AR / CustTrans, since it is paid at the
    /// till. The document's own cash / income accounts take precedence over the
    /// company-default fallbacks. Reversal flips every leg.
    private static func posInvoiceRows(
        _ doc: Document, reversal: Bool, costBasis: [Int: Double],
        cogsAccount: String?, inventoryAccount: String?,
        incomeAccount: String?, cashAccount: String?, fallbackVatAccount: String?,
        uomFactors: [Int: Double]
    ) -> [Document] {
        var docs = stockIssueRows(doc, voucherType: "POSInvoice", reversal: reversal,
                                  costBasis: costBasis, cogsAccount: cogsAccount, inventoryAccount: inventoryAccount,
                                  uomFactors: uomFactors)

        let postingDate = doc.fields["transaction_date"] ?? doc.fields["posting_date"] ?? .date(Date())
        let taxRowsChildren = doc.children["taxes"] ?? []
        let grand = asDouble(doc.fields["grand_total"]) ?? 0
        let net   = asDouble(doc.fields["net_total"]) ?? (grand - totalTax(taxRowsChildren))
        let customer = doc.fields["customer"]

        // Skip the financial legs when the accounts aren't configured (stock
        // still posts) — mirrors the legacy derivePOSInvoice guard.
        guard let cash = nonEmptyString(doc.fields["cash_account"]) ?? cashAccount,
              let income = nonEmptyString(doc.fields["income_account"]) ?? incomeAccount
        else { return docs }

        let zero = FieldValue.double(0)
        // Dr Cash / Bank — gross received.
        docs.append(glRow(
            id: "GL-\(doc.id)-cash\(suffix(reversal))", postingDate: postingDate, account: .string(cash),
            debit: reversal ? zero : .double(grand), credit: reversal ? .double(grand) : zero,
            partyType: nil, party: nil, costCenter: nil,
            voucherType: "POSInvoice", voucherNo: doc.id, reversal: reversal, company: doc.company
        ))
        // Cr Income — net of tax.
        docs.append(glRow(
            id: "GL-\(doc.id)-income\(suffix(reversal))", postingDate: postingDate, account: .string(income),
            debit: reversal ? .double(net) : zero, credit: reversal ? zero : .double(net),
            partyType: nil, party: nil, costCenter: nil,
            voucherType: "POSInvoice", voucherNo: doc.id, reversal: reversal, company: doc.company
        ))
        docs += taxRowDocs(doc, rows: taxRowsChildren, party: customer, partyTypeValue: "Customer", isOutput: true, reversal: reversal, fallbackVatAccount: fallbackVatAccount)
        return docs
    }

    /// Stock Entry moves material between warehouses with no GL: an outbound
    /// Stock Ledger leg from each line's source warehouse (-qty on submit,
    /// +qty on reversal) and an inbound leg into its target warehouse (+qty on
    /// submit, -qty on reversal), at the line's stated valuation rate. A line
    /// may have only one of the two (a pure receipt or issue). The trans_type
    /// follows the entry's purpose; the Bin cache is recomputed post-commit.
    static func stockEntryRows(_ doc: Document, reversal: Bool, uomFactors: [Int: Double] = [:]) -> [Document] {
        let postingDate = doc.fields["posting_date"] ?? .date(Date())
        let postingTime = doc.fields["posting_time"]
        let transType = stockLedgerTransType(forPurpose: doc.fields["purpose"])

        var docs: [Document] = []
        for row in doc.children["items"] ?? [] {
            guard let itemId = nonEmptyString(row.fields["item"]) else { continue }
            // Convert to stock UOM; the entry's valuation_rate is per stock UOM.
            let stockQty = FieldValue.double((asDouble(row.fields["qty"]) ?? 0) * (uomFactors[row.rowIndex] ?? 1))
            let rate = row.fields["valuation_rate"]

            if let sourceWh = nonEmptyString(row.fields["source_warehouse"]) {
                docs.append(sleRow(
                    id: "SLE-\(doc.id)-\(row.rowIndex)-out\(suffix(reversal))",
                    transType: transType, item: .string(itemId), warehouse: .string(sourceWh),
                    postingDate: postingDate, postingTime: postingTime,
                    voucherType: "StockEntry", voucherNo: doc.id,
                    qtyChange: signed(stockQty, negate: !reversal), rate: rate, reversal: reversal, company: doc.company
                ))
            }
            if let targetWh = nonEmptyString(row.fields["target_warehouse"]) {
                docs.append(sleRow(
                    id: "SLE-\(doc.id)-\(row.rowIndex)-in\(suffix(reversal))",
                    transType: transType, item: .string(itemId), warehouse: .string(targetWh),
                    postingDate: postingDate, postingTime: postingTime,
                    voucherType: "StockEntry", voucherNo: doc.id,
                    qtyChange: signed(stockQty, negate: reversal), rate: rate, reversal: reversal, company: doc.company
                ))
            }
        }
        return docs
    }

    /// Map a Stock Entry `purpose` to the StockLedgerEntry `trans_type`
    /// (mirrors LedgerDerivationService.stockLedgerTransType).
    private static func stockLedgerTransType(forPurpose purpose: FieldValue?) -> String {
        guard case .string(let p)? = purpose else { return "Issue" }
        switch p {
        case "Material Receipt":                        return "Receipt"
        case "Material Issue":                          return "Issue"
        case "Material Transfer":                       return "Transfer"
        case "Repack":                                  return "Adjustment"
        case "Manufacturing", "Send to Subcontractor":  return "Production"
        default:                                        return "Issue"
        }
    }

    /// Purchase Receipt brings goods IN: a Stock Ledger Receipt row per line at
    /// the line's receipt cost (+qty submit / -qty reversal), plus the inventory
    /// accrual GL — Dr Inventory / Cr GRNI for the value of the stock-item lines
    /// (reversal flips). The accrual is opt-in: posted only when both the Stock
    /// and GRNI accounts are mapped; otherwise the receipt moves stock only,
    /// exactly as the legacy event path did. The matching Purchase Invoice
    /// clears GRNI for the same lines so the loop nets to Dr Inventory / Cr AP.
    static func purchaseReceiptRows(
        _ doc: Document, reversal: Bool, stockItemFlags: [String: Bool],
        inventoryAccount: String?, grniAccount: String?, uomFactors: [Int: Double] = [:]
    ) -> [Document] {
        let postingDate = doc.fields["transaction_date"] ?? doc.fields["posting_date"] ?? .date(Date())
        let postingTime = doc.fields["posting_time"]
        let defaultWarehouse = nonEmptyString(doc.fields["set_warehouse"])
            ?? nonEmptyString(doc.fields["warehouse"])

        var docs: [Document] = []
        var inventoryTotal = 0.0
        for row in doc.children["items"] ?? [] {
            guard let itemId = nonEmptyString(row.fields["item"]) else { continue }
            guard let whId = nonEmptyString(row.fields["warehouse"]) ?? defaultWarehouse else { continue }
            let factor = uomFactors[row.rowIndex] ?? 1
            let lineQty = asDouble(row.fields["qty"]) ?? 0
            let lineRate = asDouble(row.fields["valuation_rate"] ?? row.fields["rate"]) ?? 0
            // Convert to stock UOM: qty scales up by the factor, the per-unit
            // rate scales down by it, so the line VALUE (qty × rate) is invariant.
            let stockQty = lineQty * factor
            let stockRate = factor != 0 ? lineRate / factor : lineRate
            // Receipt: +qty on submit, -qty on reversal.
            let signedQty = signed(.double(stockQty), negate: reversal)
            docs.append(sleRow(
                id: "SLE-\(doc.id)-\(row.rowIndex)\(suffix(reversal))",
                transType: "Receipt", item: .string(itemId), warehouse: .string(whId),
                postingDate: postingDate, postingTime: postingTime,
                voucherType: "PurchaseReceipt", voucherNo: doc.id,
                qtyChange: signedQty, rate: .double(stockRate), reversal: reversal, company: doc.company
            ))
            if stockItemFlags[itemId] ?? true {
                inventoryTotal += stockQty * stockRate
            }
        }

        if abs(inventoryTotal) > 0.0001, let inventoryAccount, let grniAccount {
            let amount = FieldValue.double(inventoryTotal)
            let zero = FieldValue.double(0)
            docs.append(glRow(
                id: "GL-\(doc.id)-inventory\(suffix(reversal))", postingDate: postingDate, account: .string(inventoryAccount),
                debit: reversal ? zero : amount, credit: reversal ? amount : zero,
                partyType: nil, party: nil, costCenter: nil,
                voucherType: "PurchaseReceipt", voucherNo: doc.id, reversal: reversal, company: doc.company
            ))
            docs.append(glRow(
                id: "GL-\(doc.id)-grni\(suffix(reversal))", postingDate: postingDate, account: .string(grniAccount),
                debit: reversal ? amount : zero, credit: reversal ? zero : amount,
                partyType: nil, party: nil, costCenter: nil,
                voucherType: "PurchaseReceipt", voucherNo: doc.id, reversal: reversal, company: doc.company
            ))
        }
        return docs
    }

    /// Mirrors `derivePaymentEntry`: GL leg(s) for the cash movement, a
    /// Cust/VendTrans payment row, a Settlement row per allocation, and the
    /// matching invoice `outstanding_amount` decrement (applied as an updated
    /// invoice document so it commits in the same transaction). The referenced
    /// invoices are pre-fetched outside the write transaction.
    private static func paymentEntryRows(_ doc: Document, reversal: Bool, referencedInvoices: [String: Document]) -> [Document] {
        let postingDate = doc.fields["posting_date"] ?? .date(Date())
        let amount   = doc.fields["paid_amount"] ?? .double(0)
        let paidFrom = doc.fields["paid_from"]
        let paidTo   = doc.fields["paid_to"]
        let partyType = asString(doc.fields["party_type"])
        let party    = doc.fields["party"]
        let currency = doc.fields["currency"]

        var docs: [Document] = []
        // Cash leaves paid_from (Cr), arrives at paid_to (Dr). Reversal flips.
        if let paidFrom {
            docs.append(glRow(
                id: "GL-\(doc.id)-from\(suffix(reversal))", postingDate: postingDate, account: paidFrom,
                debit: reversal ? amount : .double(0), credit: reversal ? .double(0) : amount,
                partyType: partyType, party: party, costCenter: nil,
                voucherType: "PaymentEntry", voucherNo: doc.id, reversal: reversal, company: doc.company
            ))
        }
        if let paidTo {
            docs.append(glRow(
                id: "GL-\(doc.id)-to\(suffix(reversal))", postingDate: postingDate, account: paidTo,
                debit: reversal ? .double(0) : amount, credit: reversal ? amount : .double(0),
                partyType: partyType, party: party, costCenter: nil,
                voucherType: "PaymentEntry", voucherNo: doc.id, reversal: reversal, company: doc.company
            ))
        }

        // Subledger + settlement only for party payments (not Internal Transfer).
        guard case .string(let kind)? = doc.fields["payment_type"], kind != "Internal Transfer",
              case .string(let partyId)? = party, !partyId.isEmpty else { return docs }

        let subledgerAmount = signed(amount, negate: !reversal)
        switch kind {
        case "Receive":
            docs.append(custTransRow(
                id: "CT-\(doc.id)\(suffix(reversal))", transType: reversal ? "Adjustment" : "Payment",
                customer: .string(partyId), postingDate: postingDate, dueDate: nil,
                amount: subledgerAmount, currency: currency,
                voucherType: "PaymentEntry", voucherNo: doc.id, reversal: reversal, company: doc.company
            ))
        case "Pay":
            docs.append(vendTransRow(
                id: "VT-\(doc.id)\(suffix(reversal))", transType: reversal ? "Adjustment" : "Payment",
                supplier: .string(partyId), postingDate: postingDate, dueDate: nil,
                amount: subledgerAmount, currency: currency,
                voucherType: "PaymentEntry", voucherNo: doc.id, reversal: reversal, company: doc.company
            ))
        default:
            break
        }

        // Settlement row per allocation + accumulate the outstanding delta per
        // invoice (delta is signed: submit decrements, cancel restores).
        var outstandingDelta: [String: Double] = [:]
        for (idx, ref) in (doc.children["references"] ?? []).enumerated() {
            guard case .string(let invType)? = ref.fields["reference_doctype"],
                  case .string(let invNo)? = ref.fields["reference_name"],
                  let allocated = ref.fields["allocated_amount"] else { continue }
            docs.append(settlementRow(
                id: "STL-\(doc.id)-\(idx)\(suffix(reversal))",
                paymentVoucherNo: doc.id, invoiceVoucherType: invType, invoiceVoucherNo: invNo,
                partyType: kind == "Receive" ? "Customer" : "Supplier", party: partyId,
                allocatedAmount: signed(allocated, negate: reversal), postingDate: postingDate,
                reversal: reversal, company: doc.company
            ))
            outstandingDelta[invNo, default: 0] += asDouble(signed(allocated, negate: !reversal)) ?? 0
        }

        // Updated invoice documents with the adjusted outstanding_amount
        // (allowOnSubmit on Sales/Purchase Invoice), written in the same tx.
        for (invNo, delta) in outstandingDelta {
            guard var invoice = referencedInvoices[invNo] else { continue }
            let current = asDouble(invoice.fields["outstanding_amount"])
                ?? asDouble(invoice.fields["grand_total"]) ?? 0
            invoice.fields["outstanding_amount"] = .double(current + delta)
            docs.append(invoice)
        }

        return docs
    }

    private static func settlementRow(
        id: String, paymentVoucherNo: String, invoiceVoucherType: String, invoiceVoucherNo: String,
        partyType: String, party: String, allocatedAmount: FieldValue, postingDate: FieldValue,
        reversal: Bool, company: String
    ) -> Document {
        let fields: [String: FieldValue] = [
            "payment_voucher_type": .string("PaymentEntry"),
            "payment_voucher_no":   .string(paymentVoucherNo),
            "invoice_voucher_type": .string(invoiceVoucherType),
            "invoice_voucher_no":   .string(invoiceVoucherNo),
            "party_type":           .string(partyType),
            "party":                .string(party),
            "allocated_amount":     allocatedAmount,
            "posting_date":         postingDate,
            "is_reversal":          .bool(reversal),
        ]
        return ledger(id: id, docType: "Settlement", company: company, fields: fields)
    }

    /// Pre-fetch the invoices a Payment Entry settles, keyed by id, OUTSIDE the
    /// write transaction. Empty for non-PaymentEntry DocTypes.
    private static func referencedInvoices(for doc: Document, engine: DocumentEngine) -> [String: Document] {
        guard doc.docType == "PaymentEntry" else { return [:] }
        var result: [String: Document] = [:]
        for ref in doc.children["references"] ?? [] {
            guard case .string(let invType)? = ref.fields["reference_doctype"], !invType.isEmpty,
                  case .string(let invNo)? = ref.fields["reference_name"], !invNo.isEmpty,
                  result[invNo] == nil else { continue }
            if let invoice = try? engine.fetch(docType: invType, id: invNo) {
                result[invNo] = invoice
            }
        }
        return result
    }

    /// VAT GL leg (Cr output / Dr input) + TaxTrans row per tax child row.
    private static func taxRowDocs(
        _ doc: Document, rows: [ChildRow], party: FieldValue?, partyTypeValue: String,
        isOutput: Bool, reversal: Bool, fallbackVatAccount: String?
    ) -> [Document] {
        guard !rows.isEmpty else { return [] }
        let postingDate = doc.fields["transaction_date"] ?? doc.fields["posting_date"] ?? .date(Date())
        let fallbackAccount = fallbackVatAccount
        var docs: [Document] = []

        for (idx, row) in rows.enumerated() {
            let taxAmount = asDouble(row.fields["tax_amount"]) ?? 0
            let taxable   = asDouble(row.fields["taxable_amount"]) ?? 0
            let account   = nonEmptyString(row.fields["tax_account"]) ?? fallbackAccount

            if taxAmount != 0, let account {
                let amt = FieldValue.double(taxAmount)
                let zero = FieldValue.double(0)
                let debit:  FieldValue
                let credit: FieldValue
                if isOutput {
                    debit  = reversal ? amt : zero
                    credit = reversal ? zero : amt
                } else {
                    debit  = reversal ? zero : amt
                    credit = reversal ? amt : zero
                }
                docs.append(glRow(
                    id: "GL-\(doc.id)-tax-\(idx)\(suffix(reversal))", postingDate: postingDate,
                    account: .string(account), debit: debit, credit: credit,
                    partyType: nil, party: nil, costCenter: nil,
                    voucherType: doc.docType, voucherNo: doc.id, reversal: reversal, company: doc.company
                ))
            }

            var taxFields: [String: FieldValue] = [
                "tax_type":     .string(asString(row.fields["tax_type"]) ?? "VAT"),
                "posting_date": postingDate,
                "base_amount":  signed(.double(taxable), negate: reversal),
                "tax_amount":   signed(.double(taxAmount), negate: reversal),
                "party_type":   .string(partyTypeValue),
                "voucher_type": .string(doc.docType),
                "voucher_no":   .string(doc.id),
                "is_reversal":  .bool(reversal),
            ]
            if let taxCode = asString(row.fields["tax_code"]) { taxFields["tax"] = .string(taxCode) }
            if let rate = row.fields["rate"] { taxFields["rate"] = rate }
            if let party { taxFields["party"] = party }
            docs.append(ledger(id: "TT-\(doc.id)-\(idx)\(suffix(reversal))", docType: "TaxTrans", company: doc.company, fields: taxFields))
        }
        return docs
    }

    // MARK: - Ledger document builders

    private static func glRow(
        id: String, postingDate: FieldValue, account: FieldValue,
        debit: FieldValue, credit: FieldValue,
        partyType: String?, party: FieldValue?, costCenter: FieldValue?,
        voucherType: String, voucherNo: String, reversal: Bool, company: String
    ) -> Document {
        var fields: [String: FieldValue] = [
            "posting_date": postingDate,
            "account":      account,
            "debit":        debit,
            "credit":       credit,
            "voucher_type": .string(voucherType),
            "voucher_no":   .string(voucherNo),
            "is_reversal":  .bool(reversal),
        ]
        if let partyType  { fields["party_type"]  = .string(partyType) }
        if let party      { fields["party"]       = party }
        if let costCenter { fields["cost_center"] = costCenter }
        return ledger(id: id, docType: "GLEntry", company: company, fields: fields)
    }

    /// Stock Ledger Entry row (mirrors LedgerDerivationService.writeSLE's field
    /// shape) for the atomic stock path.
    private static func sleRow(
        id: String, transType: String, item: FieldValue, warehouse: FieldValue,
        postingDate: FieldValue, postingTime: FieldValue?,
        voucherType: String, voucherNo: String, qtyChange: FieldValue,
        rate: FieldValue?, reversal: Bool, company: String
    ) -> Document {
        var fields: [String: FieldValue] = [
            "trans_type":   .string(transType),
            "item":         item,
            "warehouse":    warehouse,
            "posting_date": postingDate,
            "voucher_type": .string(voucherType),
            "voucher_no":   .string(voucherNo),
            "qty_change":   qtyChange,
            "is_reversal":  .bool(reversal),
        ]
        if let postingTime { fields["posting_time"] = postingTime }
        if let rate        { fields["valuation_rate"] = rate }
        return ledger(id: id, docType: "StockLedgerEntry", company: company, fields: fields)
    }

    private static func custTransRow(
        id: String, transType: String, customer: FieldValue, postingDate: FieldValue,
        dueDate: FieldValue?, amount: FieldValue, currency: FieldValue?,
        voucherType: String, voucherNo: String, reversal: Bool, company: String
    ) -> Document {
        var fields: [String: FieldValue] = [
            "trans_type":   .string(transType),
            "customer":     customer,
            "posting_date": postingDate,
            "amount":       amount,
            "voucher_type": .string(voucherType),
            "voucher_no":   .string(voucherNo),
            "is_reversal":  .bool(reversal),
        ]
        if let dueDate  { fields["due_date"] = dueDate }
        if let currency { fields["currency"] = currency }
        return ledger(id: id, docType: "CustTrans", company: company, fields: fields)
    }

    private static func vendTransRow(
        id: String, transType: String, supplier: FieldValue, postingDate: FieldValue,
        dueDate: FieldValue?, amount: FieldValue, currency: FieldValue?,
        voucherType: String, voucherNo: String, reversal: Bool, company: String
    ) -> Document {
        var fields: [String: FieldValue] = [
            "trans_type":   .string(transType),
            "supplier":     supplier,
            "posting_date": postingDate,
            "amount":       amount,
            "voucher_type": .string(voucherType),
            "voucher_no":   .string(voucherNo),
            "is_reversal":  .bool(reversal),
        ]
        if let dueDate  { fields["due_date"] = dueDate }
        if let currency { fields["currency"] = currency }
        return ledger(id: id, docType: "VendTrans", company: company, fields: fields)
    }

    private static func ledger(id: String, docType: String, company: String, fields: [String: FieldValue]) -> Document {
        Document(
            id: id, docType: docType, company: company, status: "",
            createdAt: Date(), updatedAt: Date(),
            syncVersion: 0, syncState: .local,
            fields: fields, children: [:]
        )
    }

    // MARK: - Value helpers

    private static func suffix(_ reversal: Bool) -> String { reversal ? "-reversal" : "" }

    private static func totalTax(_ rows: [ChildRow]) -> Double {
        rows.reduce(0) { $0 + (asDouble($1.fields["tax_amount"]) ?? 0) }
    }

    /// Sum of the stock-item line amounts (tax-exclusive) on a purchase
    /// document, used to size the GRNI clearing leg on a Purchase Invoice.
    private static func stockLineNet(_ doc: Document, stockItemFlags: [String: Bool]) -> Double {
        var total = 0.0
        for row in doc.children["items"] ?? [] {
            guard let itemId = nonEmptyString(row.fields["item"]), stockItemFlags[itemId] ?? true else { continue }
            let amount = asDouble(row.fields["amount"])
                ?? ((asDouble(row.fields["qty"]) ?? 0) * (asDouble(row.fields["rate"]) ?? 0))
            total += amount
        }
        return total
    }

    private static func signed(_ value: FieldValue, negate: Bool) -> FieldValue {
        guard negate else { return value }
        return .double(-(asDouble(value) ?? 0))
    }

    private static func companyDefault(_ key: String, engine: DocumentEngine) -> String? {
        guard let company = (try? engine.list(docType: "Company"))?.first else { return nil }
        return nonEmptyString(company.fields[key])
    }

    private static func asDouble(_ value: FieldValue?) -> Double? {
        switch value {
        case .double(let d): return d
        case .int(let i): return Double(i)
        case .string(let s): return Double(s)
        default: return nil
        }
    }

    private static func asString(_ value: FieldValue?) -> String? {
        if case .string(let s)? = value { return s }
        return nil
    }

    private static func nonEmptyString(_ value: FieldValue?) -> String? {
        // Trim to match LedgerDerivationService / StockBalanceService, which
        // store and key Bin / SLE warehouse and account ids on the trimmed
        // value. Without trimming, a warehouse like "WH-1 " would write an SLE
        // the post-commit Bin recompute and moving-average lookup never match.
        guard let s = asString(value) else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Environment injection

private struct PostingCoordinatorKey: EnvironmentKey {
    static let defaultValue: PostingCoordinator? = nil
}

extension EnvironmentValues {
    /// The app's posting coordinator, injected at app scope so the form's
    /// submit/cancel actions can route atomic-posting DocTypes through the
    /// submit transaction. Nil in previews / tests that don't inject it.
    var postingCoordinator: PostingCoordinator? {
        get { self[PostingCoordinatorKey.self] }
        set { self[PostingCoordinatorKey.self] = newValue }
    }
}
