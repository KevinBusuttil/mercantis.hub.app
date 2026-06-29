import XCTest
import MercantisCore
@testable import Mercantis_Hub

/// Manufacturing gap closers: the raw-material availability check and the
/// Production Plan produced-rollup maths / wiring.
final class HubManufacturingGapsTests: XCTestCase {

    // MARK: - Material availability

    func test_shortages_aggregatePerItem_andFlagShortfalls() {
        let required = [(item: "A", qty: 10.0), (item: "B", qty: 5.0), (item: "A", qty: 2.0)]
        let onHand: [String: Double] = ["A": 8, "B": 5]
        let shorts = MaterialAvailabilityChecker.shortages(
            required: required, onHand: { onHand[$0] ?? 0 })
        XCTAssertEqual(shorts, [MaterialAvailabilityChecker.Shortage(item: "A", required: 12, onHand: 8)])
        XCTAssertEqual(shorts.first?.short, 4)
    }

    func test_shortages_noneWhenStockSufficient() {
        let shorts = MaterialAvailabilityChecker.shortages(
            required: [(item: "A", qty: 3)], onHand: { _ in 5 })
        XCTAssertTrue(shorts.isEmpty)
    }

    func test_shortages_missingItemTreatedAsZeroOnHand() {
        let shorts = MaterialAvailabilityChecker.shortages(
            required: [(item: "A", qty: 1)], onHand: { _ in 0 })
        XCTAssertEqual(shorts.count, 1)
        XCTAssertEqual(shorts.first?.onHand, 0)
    }

    func test_message_nilWhenNoShortage() {
        XCTAssertNil(MaterialAvailabilityChecker.message(for: []))
        XCTAssertNotNil(MaterialAvailabilityChecker.message(
            for: [MaterialAvailabilityChecker.Shortage(item: "A", required: 5, onHand: 1)]))
    }

    // MARK: - Production rollup

    func test_productionStatus_thresholds() {
        XCTAssertEqual(SalesOrderFulfilmentCalculator.productionStatus(plannedQty: 10, producedQty: 0), "To Produce")
        XCTAssertEqual(SalesOrderFulfilmentCalculator.productionStatus(plannedQty: 10, producedQty: 4), "In Production")
        XCTAssertEqual(SalesOrderFulfilmentCalculator.productionStatus(plannedQty: 10, producedQty: 10), "Produced")
    }

    func test_productionPlan_hasProgressFields_allAllowOnSubmit() {
        guard let plan = HubManifest.docType(for: "ProductionPlan") else { return XCTFail("ProductionPlan missing") }
        for key in ["production_status", "produced_qty", "per_produced"] {
            guard let field = plan.fields.first(where: { $0.key == key }) else {
                return XCTFail("ProductionPlan missing progress field \(key)")
            }
            XCTAssertTrue(field.allowOnSubmit, "\(key) must be editable on the submitted plan")
        }
    }
}
