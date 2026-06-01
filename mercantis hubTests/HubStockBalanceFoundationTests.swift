import XCTest
import MercantisCore
@testable import Mercantis_Hub

/// Phase 3 — Stock Balance / Inventory Availability metadata wiring guards.
final class HubStockBalanceFoundationTests: XCTestCase {

    func test_bin_doctype_is_registered_and_not_submittable() {
        guard let bin = HubManifest.docType(for: "Bin") else {
            return XCTFail("Bin (Stock Balance) DocType must be registered")
        }
        XCTAssertFalse(bin.isSubmittable, "Bin is a derived projection, not a document")
        XCTAssertFalse(bin.isChildTable)
    }

    func test_bin_exposes_required_balance_fields() {
        guard let bin = HubManifest.docType(for: "Bin") else {
            return XCTFail("Bin not registered")
        }
        let keys = Set(bin.fields.map(\.key))
        XCTAssertTrue(keys.isSuperset(of: [
            "item", "warehouse", "actual_qty", "stock_value",
            "valuation_rate", "last_movement_date",
        ]))
    }

    func test_bin_id_is_deterministic_per_item_and_warehouse() {
        XCTAssertEqual(StockBalanceService.binID(item: "ITEM-1", warehouse: "W-1"), "BIN-ITEM-1-W-1")
    }

    func test_stock_on_hand_report_is_registered() {
        XCTAssertNotNil(HubReports.report(forId: "stock-on-hand"))
        XCTAssertTrue(HubReports.allReports.contains { $0.id == "stock-on-hand" })
        XCTAssertEqual(HubReports.stockOnHand.docType, "Bin")
    }
}
