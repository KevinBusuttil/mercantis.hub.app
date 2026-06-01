import Foundation
import MercantisCore

/// Phase 3 — maintains and queries `Bin` (Stock Balance) rows derived from
/// `StockLedgerEntry`.
///
/// Recomputation is full, not incremental: for an affected (item, warehouse)
/// pair we read every ledger row for that pair and fold them with
/// `StockBalanceCalculator`. That makes the result correct under submit,
/// cancel (reversal rows), and replay alike — there is no running counter to
/// drift. `LedgerDerivationService` calls `recompute(affectedBy:)` right
/// after it writes the Stock Ledger rows for a Stock Entry, so the order is
/// guaranteed (the rows exist before the roll-up reads them).
///
/// The query helpers (`availableQty`, `balance`, `balances(forItem:)`) read
/// the materialised `Bin` rows, giving POS and Deliveries a cheap, indexed
/// availability lookup without rescanning the ledger.
public nonisolated final class StockBalanceService: @unchecked Sendable {

    private let engine: DocumentEngine

    public init(engine: DocumentEngine) {
        self.engine = engine
    }

    // MARK: - Recompute

    /// Recompute the bins for every (item, warehouse) pair touched by a
    /// stock-moving document. Stock Entry lines carry `source_warehouse` /
    /// `target_warehouse`; Purchase Receipt / Sales Delivery lines carry a
    /// single `warehouse`. Unknown keys are simply skipped.
    public func recompute(affectedBy stockEntry: Document) throws {
        var seen = Set<String>()
        for row in stockEntry.children["items"] ?? [] {
            guard let item = nonEmptyString(row.fields["item"]) else { continue }
            for whKey in ["source_warehouse", "target_warehouse", "warehouse"] {
                guard let warehouse = nonEmptyString(row.fields[whKey]) else { continue }
                let key = "\(item)\u{1}\(warehouse)"
                guard seen.insert(key).inserted else { continue }
                try recompute(item: item, warehouse: warehouse)
            }
        }
    }

    /// Recompute one bin from the full ledger for that (item, warehouse).
    public func recompute(item: String, warehouse: String) throws {
        let entries = try engine.list(
            docType: "StockLedgerEntry",
            filters: ["item": .string(item), "warehouse": .string(warehouse)],
            applyRowAccess: false
        )
        let rows = entries.map { entry in
            StockBalanceCalculator.Row(
                item: item,
                warehouse: warehouse,
                qtyChange: doubleValue(entry.fields["qty_change"]) ?? 0,
                valuationRate: doubleValue(entry.fields["valuation_rate"]),
                postingDate: dateValue(entry.fields["posting_date"])
            )
        }
        let balance = StockBalanceCalculator.balance(item: item, warehouse: warehouse, rows: rows)
        try upsert(balance)
    }

    private func upsert(_ balance: StockBalanceCalculator.Balance) throws {
        let id = Self.binID(item: balance.item, warehouse: balance.warehouse)
        let fields = fieldValues(for: balance)

        // Update in place when the bin exists. Re-save the fetched document
        // untouched apart from its fields so its stored `updatedAt` still
        // matches — Core's `save` enforces optimistic concurrency by
        // comparing the incoming `updatedAt` to the stored row, then writes
        // its own fresh timestamp. (Same contract as adjustInvoiceOutstanding.)
        if var existing = try engine.fetch(docType: "Bin", id: id) {
            existing.fields = fields
            try engine.save(existing)
            return
        }

        let bin = Document(
            id: id,
            docType: "Bin",
            company: "",
            status: "",
            createdAt: Date(),
            updatedAt: Date(),
            syncVersion: 0,
            syncState: .local,
            fields: fields,
            children: [:]
        )
        try engine.save(bin)
    }

    private func fieldValues(for balance: StockBalanceCalculator.Balance) -> [String: FieldValue] {
        var fields: [String: FieldValue] = [
            "item":           .string(balance.item),
            "warehouse":      .string(balance.warehouse),
            "actual_qty":     .double(balance.actualQty),
            "valuation_rate": .double(balance.valuationRate),
            "stock_value":    .double(balance.stockValue),
        ]
        if let date = balance.lastMovementDate {
            fields["last_movement_date"] = .date(date)
        }
        return fields
    }

    // MARK: - Queries (reused by Item workspace, POS, Deliveries)

    /// Available quantity for one item in one warehouse (0 when no bin).
    public func availableQty(item: String, warehouse: String) throws -> Double {
        try balance(item: item, warehouse: warehouse)?.actualQty ?? 0
    }

    /// The stored balance for one (item, warehouse), or `nil` if untouched.
    public func balance(item: String, warehouse: String) throws -> StockBalanceCalculator.Balance? {
        let id = Self.binID(item: item, warehouse: warehouse)
        guard let bin = try engine.fetch(docType: "Bin", id: id) else { return nil }
        return makeBalance(from: bin)
    }

    /// Every warehouse balance for one item — used by the Item workspace
    /// stock-on-hand summary. Zero-quantity bins are kept so a item that
    /// has moved through a warehouse still shows the location.
    public func balances(forItem item: String) throws -> [StockBalanceCalculator.Balance] {
        let bins = try engine.list(
            docType: "Bin",
            filters: ["item": .string(item)],
            applyRowAccess: false
        )
        return bins
            .map(makeBalance(from:))
            .sorted { $0.warehouse < $1.warehouse }
    }

    // MARK: - Helpers

    static func binID(item: String, warehouse: String) -> String {
        "BIN-\(item)-\(warehouse)"
    }

    private func makeBalance(from bin: Document) -> StockBalanceCalculator.Balance {
        StockBalanceCalculator.Balance(
            item: nonEmptyString(bin.fields["item"]) ?? "",
            warehouse: nonEmptyString(bin.fields["warehouse"]) ?? "",
            actualQty: doubleValue(bin.fields["actual_qty"]) ?? 0,
            stockValue: doubleValue(bin.fields["stock_value"]) ?? 0,
            valuationRate: doubleValue(bin.fields["valuation_rate"]) ?? 0,
            lastMovementDate: dateValue(bin.fields["last_movement_date"])
        )
    }

    private func nonEmptyString(_ value: FieldValue?) -> String? {
        guard case .string(let s) = value else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func doubleValue(_ value: FieldValue?) -> Double? {
        switch value {
        case .double(let d): return d
        case .int(let i):    return Double(i)
        default:             return nil
        }
    }

    private func dateValue(_ value: FieldValue?) -> Date? {
        switch value {
        case .date(let d), .dateTime(let d): return d
        default: return nil
        }
    }
}
