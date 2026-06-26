import XCTest
@testable import Mercantis_Hub

final class StockBalanceCalculatorTests: XCTestCase {

    private func day(_ d: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(d) * 86_400)
    }

    private func row(_ item: String, _ wh: String, qty: Double, rate: Double?, day d: Int)
        -> StockBalanceCalculator.Row
    {
        .init(item: item, warehouse: wh, qtyChange: qty, valuationRate: rate, postingDate: day(d))
    }

    func test_receipt_sets_qty_value_and_rate() {
        let balance = StockBalanceCalculator.balance(
            item: "A", warehouse: "W1",
            rows: [row("A", "W1", qty: 10, rate: 5, day: 1)]
        )
        XCTAssertEqual(balance.actualQty, 10, accuracy: 0.0001)
        XCTAssertEqual(balance.stockValue, 50, accuracy: 0.0001)
        XCTAssertEqual(balance.valuationRate, 5, accuracy: 0.0001)
        XCTAssertEqual(balance.lastMovementDate, day(1))
    }

    func test_receipt_then_issue_reduces_qty_and_value() {
        let balance = StockBalanceCalculator.balance(
            item: "A", warehouse: "W1",
            rows: [
                row("A", "W1", qty: 10, rate: 5, day: 1),
                row("A", "W1", qty: -4, rate: 5, day: 3),
            ]
        )
        XCTAssertEqual(balance.actualQty, 6, accuracy: 0.0001)
        XCTAssertEqual(balance.stockValue, 30, accuracy: 0.0001)
        XCTAssertEqual(balance.valuationRate, 5, accuracy: 0.0001)
        XCTAssertEqual(balance.lastMovementDate, day(3), "Last movement is the latest posting date")
    }

    func test_reversal_nets_balance_back_to_zero() {
        let balance = StockBalanceCalculator.balance(
            item: "A", warehouse: "W1",
            rows: [
                row("A", "W1", qty: 10, rate: 5, day: 1),
                row("A", "W1", qty: -10, rate: 5, day: 1),   // cancel reversal
            ]
        )
        XCTAssertEqual(balance.actualQty, 0, accuracy: 0.0001)
        XCTAssertEqual(balance.stockValue, 0, accuracy: 0.0001)
        XCTAssertEqual(balance.valuationRate, 0, accuracy: 0.0001, "No rate when out of stock")
    }

    func test_transfer_moves_qty_between_two_warehouses() throws {
        // Receipt into W1, then a transfer W1 → W2.
        let balances = StockBalanceCalculator.aggregate([
            row("A", "W1", qty: 10, rate: 5, day: 1),   // receipt
            row("A", "W1", qty: -10, rate: 5, day: 2),  // transfer out
            row("A", "W2", qty: 10, rate: 5, day: 2),   // transfer in
        ])
        XCTAssertEqual(balances.count, 2)
        let w1 = try XCTUnwrap(balances.first { $0.warehouse == "W1" })
        let w2 = try XCTUnwrap(balances.first { $0.warehouse == "W2" })
        XCTAssertEqual(w1.actualQty, 0, accuracy: 0.0001)
        XCTAssertEqual(w2.actualQty, 10, accuracy: 0.0001)
        XCTAssertEqual(w2.stockValue, 50, accuracy: 0.0001)
    }

    func test_aggregate_groups_per_item_and_warehouse_sorted() {
        let balances = StockBalanceCalculator.aggregate([
            row("B", "W1", qty: 1, rate: 2, day: 1),
            row("A", "W2", qty: 3, rate: 4, day: 1),
            row("A", "W1", qty: 5, rate: 1, day: 1),
        ])
        XCTAssertEqual(balances.map { "\($0.item)/\($0.warehouse)" },
                       ["A/W1", "A/W2", "B/W1"],
                       "Balances are stable-sorted by item then warehouse")
    }

    func test_balance_ignores_rows_for_other_pairs() {
        let balance = StockBalanceCalculator.balance(
            item: "A", warehouse: "W1",
            rows: [
                row("A", "W1", qty: 10, rate: 5, day: 1),
                row("A", "W2", qty: 99, rate: 5, day: 1),
                row("B", "W1", qty: 99, rate: 5, day: 1),
            ]
        )
        XCTAssertEqual(balance.actualQty, 10, accuracy: 0.0001)
    }

    func test_missing_valuation_rate_counts_qty_but_no_value() {
        let balance = StockBalanceCalculator.balance(
            item: "A", warehouse: "W1",
            rows: [row("A", "W1", qty: 7, rate: nil, day: 1)]
        )
        XCTAssertEqual(balance.actualQty, 7, accuracy: 0.0001)
        XCTAssertEqual(balance.stockValue, 0, accuracy: 0.0001)
    }

    // MARK: - FIFO

    func test_fifo_consumes_oldest_layers_first() {
        let rows = [
            row("A", "W1", qty: 10, rate: 5, day: 1),   // layer 1: 10 @ 5
            row("A", "W1", qty: 10, rate: 8, day: 2),   // layer 2: 10 @ 8
        ]
        // Issue 12: 10@5 + 2@8 = 66 → unit 5.5 (FIFO, not the 6.5 moving average).
        let unit = StockBalanceCalculator.fifoUnitCost(item: "A", warehouse: "W1", rows: rows, issueQty: 12)
        XCTAssertEqual(unit, 5.5, accuracy: 0.0001)
    }

    func test_fifo_skips_layers_already_consumed_by_earlier_lines() {
        let rows = [
            row("A", "W1", qty: 10, rate: 5, day: 1),
            row("A", "W1", qty: 10, rate: 8, day: 2),
        ]
        // An earlier line took all 10 of layer 1; this line of 4 draws from
        // layer 2 only: 4 @ 8 = 8.0/unit.
        let unit = StockBalanceCalculator.fifoUnitCost(
            item: "A", warehouse: "W1", rows: rows, alreadyConsumed: 10, issueQty: 4)
        XCTAssertEqual(unit, 8.0, accuracy: 0.0001)
    }

    func test_fifo_prior_issues_deplete_oldest_layer() {
        let rows = [
            row("A", "W1", qty: 10, rate: 5, day: 1),
            row("A", "W1", qty: 10, rate: 8, day: 2),
            row("A", "W1", qty: -10, rate: 5, day: 3),  // earlier issue drained layer 1
        ]
        // Layer 1 gone; next issue of 5 draws from layer 2: 8.0/unit.
        let unit = StockBalanceCalculator.fifoUnitCost(item: "A", warehouse: "W1", rows: rows, issueQty: 5)
        XCTAssertEqual(unit, 8.0, accuracy: 0.0001)
    }
}
