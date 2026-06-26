import Foundation

/// Phase 3 (Stock Balance / Inventory Availability) — pure aggregation of
/// Stock Ledger Entry rows into per-(item, warehouse) balances.
///
/// Like `HubTaxEngine`, this type is deliberately free of `DocumentEngine`,
/// persistence, and SwiftUI so the receipt / issue / transfer / reversal
/// math is unit-testable with plain values. `StockBalanceService` reads the
/// ledger and feeds rows in; the report / Item workspace / POS availability
/// all consume the same `Balance` shape.
///
/// `nonisolated` because the module compiles with main-actor-by-default
/// isolation, but `StockBalanceService` (a `nonisolated` derivation service)
/// must call this off the main actor.
public nonisolated enum StockBalanceCalculator {

    /// One Stock Ledger Entry, reduced to the fields balances care about.
    /// `amount` is derived as `qtyChange * (valuationRate ?? 0)` rather than
    /// trusting a stored formula field, so the value column is always
    /// internally consistent with the quantity.
    public nonisolated struct Row: Equatable, Sendable {
        public let item: String
        public let warehouse: String
        public let qtyChange: Double
        public let valuationRate: Double?
        public let postingDate: Date?

        public init(
            item: String,
            warehouse: String,
            qtyChange: Double,
            valuationRate: Double?,
            postingDate: Date?
        ) {
            self.item = item
            self.warehouse = warehouse
            self.qtyChange = qtyChange
            self.valuationRate = valuationRate
            self.postingDate = postingDate
        }

        var value: Double { qtyChange * (valuationRate ?? 0) }
    }

    /// Stock on hand for one item in one warehouse.
    public nonisolated struct Balance: Equatable, Sendable {
        public let item: String
        public let warehouse: String
        public let actualQty: Double
        public let stockValue: Double
        /// Moving-average rate: `stockValue / actualQty` (0 when out of stock).
        public let valuationRate: Double
        public let lastMovementDate: Date?

        public init(
            item: String,
            warehouse: String,
            actualQty: Double,
            stockValue: Double,
            valuationRate: Double,
            lastMovementDate: Date?
        ) {
            self.item = item
            self.warehouse = warehouse
            self.actualQty = actualQty
            self.stockValue = stockValue
            self.valuationRate = valuationRate
            self.lastMovementDate = lastMovementDate
        }
    }

    /// Aggregate one (item, warehouse) pair's ledger rows into a single
    /// balance. Rows for other pairs are ignored, so callers can pass a
    /// pre-filtered slice or the whole ledger.
    public static func balance(item: String, warehouse: String, rows: [Row]) -> Balance {
        let scoped = rows.filter { $0.item == item && $0.warehouse == warehouse }
        return fold(item: item, warehouse: warehouse, rows: scoped)
    }

    /// Aggregate an arbitrary set of ledger rows into one balance per
    /// (item, warehouse), ordered by item then warehouse for stable output.
    public static func aggregate(_ rows: [Row]) -> [Balance] {
        var order: [String] = []
        var grouped: [String: [Row]] = [:]
        for row in rows {
            let key = "\(row.item)\u{1}\(row.warehouse)"
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(row)
        }
        return order.compactMap { key -> Balance? in
            guard let group = grouped[key], let first = group.first else { return nil }
            return fold(item: first.item, warehouse: first.warehouse, rows: group)
        }
        .sorted { ($0.item, $0.warehouse) < ($1.item, $1.warehouse) }
    }

    // MARK: - Core fold

    private static func fold(item: String, warehouse: String, rows: [Row]) -> Balance {
        var qty = 0.0
        var value = 0.0
        var lastDate: Date?
        for row in rows {
            qty += row.qtyChange
            value += row.value
            if let d = row.postingDate {
                lastDate = lastDate.map { Swift.max($0, d) } ?? d
            }
        }
        let roundedQty = round3(qty)
        let roundedValue = round2(value)
        let rate = roundedQty != 0 ? round2(roundedValue / roundedQty) : 0
        return Balance(
            item: item,
            warehouse: warehouse,
            actualQty: roundedQty,
            stockValue: roundedValue,
            valuationRate: rate,
            lastMovementDate: lastDate
        )
    }

    static func round2(_ value: Double) -> Double { (value * 100).rounded() / 100 }
    static func round3(_ value: Double) -> Double { (value * 1000).rounded() / 1000 }

    // MARK: - FIFO valuation

    /// FIFO unit cost for issuing `issueQty` of (item, warehouse). Replays the
    /// ledger `rows` into FIFO layers (receipts add a layer at their rate;
    /// issues consume the oldest layers), skips `alreadyConsumed` units already
    /// taken by earlier lines of the same document, then consumes `issueQty`,
    /// returning the blended cost ÷ `issueQty`. When stock runs short the last
    /// known rate is used for the shortfall (mirrors the moving-average
    /// fallback). Use this instead of `Balance.valuationRate` for FIFO items.
    public static func fifoUnitCost(
        item: String, warehouse: String, rows: [Row],
        alreadyConsumed: Double = 0, issueQty: Double
    ) -> Double {
        guard issueQty > 0 else { return 0 }
        let scoped = rows
            .filter { $0.item == item && $0.warehouse == warehouse }
            .sorted { ($0.postingDate ?? .distantPast) < ($1.postingDate ?? .distantPast) }

        var layers: [(qty: Double, rate: Double)] = []
        func consume(_ amount: Double) -> Double {
            var remaining = amount
            var cost = 0.0
            while remaining > 0.0000001, !layers.isEmpty {
                let take = Swift.min(remaining, layers[0].qty)
                cost += take * layers[0].rate
                layers[0].qty -= take
                remaining -= take
                if layers[0].qty <= 0.0000001 { layers.removeFirst() }
            }
            if remaining > 0.0000001 {
                let lastRate = layers.last?.rate ?? scoped.last(where: { $0.qtyChange > 0 })?.valuationRate ?? 0
                cost += remaining * lastRate
            }
            return cost
        }

        // Rebuild current on-hand layers from the full prior ledger.
        for row in scoped {
            if row.qtyChange > 0 {
                layers.append((row.qtyChange, row.valuationRate ?? 0))
            } else {
                _ = consume(-row.qtyChange)
            }
        }
        // Earlier lines of this same document already took from the front.
        if alreadyConsumed > 0 { _ = consume(alreadyConsumed) }
        return consume(issueQty) / issueQty
    }
}
