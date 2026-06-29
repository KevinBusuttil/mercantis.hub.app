import Foundation
import MercantisCore

/// Proactive raw-material availability check for a Work Order, so completing one
/// can't silently fail (or drive stock negative) when the source warehouse is
/// short of a required material. Splits the pure shortage maths from the
/// engine-backed lookup so the arithmetic is unit-tested.
///
/// `nonisolated` (pure value work + the nonisolated engine API) so the UI and
/// any service can call it regardless of actor isolation.
nonisolated enum MaterialAvailabilityChecker {

    struct Shortage: Equatable {
        let item: String
        let required: Double
        let onHand: Double
        /// How much more is needed (always positive for a real shortage).
        var short: Double { required - onHand }
    }

    /// Required lines whose aggregated quantity exceeds the on-hand balance.
    /// `onHand` resolves an item's available quantity (missing → 0). Lines are
    /// summed per item so a material listed twice is checked against its total.
    static func shortages(
        required: [(item: String, qty: Double)],
        onHand: (String) -> Double,
        tolerance: Double = 0.0000001
    ) -> [Shortage] {
        var need: [String: Double] = [:]
        var order: [String] = []
        for line in required where !line.item.isEmpty {
            if need[line.item] == nil { order.append(line.item) }
            need[line.item, default: 0] += line.qty
        }
        var result: [Shortage] = []
        for item in order {
            let req = need[item] ?? 0
            guard req > tolerance else { continue }
            let have = onHand(item)
            if req > have + tolerance {
                result.append(Shortage(item: item, required: req, onHand: have))
            }
        }
        return result
    }

    /// Live shortages for a Work Order's `required_items` at its source
    /// warehouse. Empty when the company allows negative stock (the consume can
    /// proceed regardless), when no source warehouse is set, or nothing's short.
    static func shortages(forWorkOrder workOrder: Document, engine: DocumentEngine) -> [Shortage] {
        if allowsNegativeStock(engine: engine) { return [] }
        guard case .string(let warehouse)? = workOrder.fields["source_warehouse"], !warehouse.isEmpty else { return [] }
        let stock = StockBalanceService(engine: engine)
        let required: [(item: String, qty: Double)] = (workOrder.children["required_items"] ?? []).compactMap { row in
            guard case .string(let item)? = row.fields["item"], !item.isEmpty else { return nil }
            return (item, asDouble(row.fields["required_qty"]))
        }
        return shortages(required: required, onHand: { item in
            let bin = (try? stock.balance(item: item, warehouse: warehouse)) ?? nil
            return bin?.actualQty ?? 0
        })
    }

    /// One-line operator message for a set of shortages, or nil when none.
    static func message(for shortages: [Shortage]) -> String? {
        guard !shortages.isEmpty else { return nil }
        let parts = shortages.map { "\($0.item) (need \(qty($0.required)), have \(qty($0.onHand)))" }
        return "Not enough raw material to complete this Work Order: " + parts.joined(separator: ", ")
            + ". Receive or transfer stock into the source warehouse first, or enable “Allow Negative Stock” in the Business Profile."
    }

    // MARK: - Helpers

    private static func allowsNegativeStock(engine: DocumentEngine) -> Bool {
        guard let company = (try? engine.list(docType: "Company"))?.first else { return false }
        if case .bool(true)? = company.fields["allow_negative_stock"] { return true }
        return false
    }

    private static func asDouble(_ value: FieldValue?) -> Double {
        switch value {
        case .double(let d): return d
        case .int(let i):    return Double(i)
        default:             return 0
        }
    }

    private static func qty(_ value: Double) -> String { String(format: "%g", value) }
}
