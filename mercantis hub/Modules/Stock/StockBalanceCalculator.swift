import Foundation

/// Phase 3 (Stock Balance / Inventory Availability) — pure aggregation of
/// Stock Ledger Entry rows into per-(item, warehouse) balances.
///
/// Like `HubTaxEngine`, this type is deliberately free of `DocumentEngine`,
/// persistence, and SwiftUI so the receipt / issue / transfer / reversal
/// math is unit-testable with plain values. `StockBalanceService` reads the
/// ledger and feeds rows in; the report / Item workspace / POS availability
/// all consume the same `Balance` shape.
public enum StockBalanceCalculator {

    /// One Stock Ledger Entry, reduced to the fields balances care about.
    /// `amount` is derived as `qtyChange * (valuationRate ?? 0)` rather than
    /// trusting a stored formula field, so the value column is always
    /// internally consistent with the quantity.
    public struct Row: Equatable, Sendable {
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
    public struct Balance: Equatable, Sendable {
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
}
