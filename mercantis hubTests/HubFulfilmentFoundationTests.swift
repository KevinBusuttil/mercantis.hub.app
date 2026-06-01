import XCTest
import MercantisCore
@testable import Mercantis_Hub

/// Phase 4 — Purchase Receipt & Sales Delivery fulfilment wiring guards.
final class HubFulfilmentFoundationTests: XCTestCase {

    // MARK: - DocTypes

    func test_fulfilment_doctypes_are_registered() {
        for id in ["PurchaseReceipt", "PurchaseReceiptItem", "SalesDelivery", "SalesDeliveryItem"] {
            XCTAssertNotNil(HubManifest.docType(for: id), "\(id) must be registered")
        }
    }

    func test_receipt_and_delivery_are_submittable_parents() {
        for id in ["PurchaseReceipt", "SalesDelivery"] {
            guard let docType = HubManifest.docType(for: id) else { return XCTFail("\(id) missing") }
            XCTAssertTrue(docType.isSubmittable)
            XCTAssertFalse(docType.isChildTable)
        }
    }

    func test_line_items_carry_item_qty_and_warehouse() {
        for id in ["PurchaseReceiptItem", "SalesDeliveryItem"] {
            guard let docType = HubManifest.docType(for: id) else { return XCTFail("\(id) missing") }
            XCTAssertTrue(docType.isChildTable)
            let keys = Set(docType.fields.map(\.key))
            XCTAssertTrue(keys.isSuperset(of: ["item", "qty", "warehouse"]), "\(id) needs item/qty/warehouse")
        }
    }

    func test_purchase_receipt_links_to_purchase_order() {
        let keys = Set(HubManifest.docType(for: "PurchaseReceipt")?.fields.map(\.key) ?? [])
        XCTAssertTrue(keys.contains("purchase_order"))
    }

    func test_sales_delivery_links_to_sales_order_and_invoice() {
        let keys = Set(HubManifest.docType(for: "SalesDelivery")?.fields.map(\.key) ?? [])
        XCTAssertTrue(keys.contains("sales_order"))
        XCTAssertTrue(keys.contains("sales_invoice"))
    }

    func test_sales_delivery_has_route_foundation_fields() {
        let keys = Set(HubManifest.docType(for: "SalesDelivery")?.fields.map(\.key) ?? [])
        XCTAssertTrue(keys.isSuperset(of: ["scheduled_date", "driver", "vehicle"]),
                      "Delivery must carry the minimal route foundations")
    }

    // MARK: - Workflows

    func test_sales_delivery_workflow_has_full_status_model() {
        guard let wf = HubWorkflows.workflow(forDocTypeId: "SalesDelivery") else {
            return XCTFail("wf-sales-delivery missing")
        }
        let states = Set(wf.states.map(\.name))
        XCTAssertEqual(states, [
            "Draft", "Scheduled", "Loaded", "Out for Delivery",
            "Delivered", "Failed", "Cancelled",
        ])
        // Submit must originate from Draft so the Hub submit flow + stock
        // derivation fire.
        XCTAssertTrue(wf.transitions.contains { $0.from == "Draft" && $0.action == "Submit" })
        // Cancel must be reachable from an active state.
        XCTAssertTrue(wf.transitions.contains { $0.action == "Cancel" })
    }

    func test_purchase_receipt_workflow_registered() {
        guard let wf = HubWorkflows.workflow(forDocTypeId: "PurchaseReceipt") else {
            return XCTFail("wf-purchase-receipt missing")
        }
        XCTAssertTrue(wf.transitions.contains { $0.from == "Draft" && $0.action == "Submit" })
    }

    // MARK: - Reports & navigation

    func test_fulfilment_reports_registered() {
        XCTAssertNotNil(HubReports.report(forId: "open-deliveries"))
        XCTAssertNotNil(HubReports.report(forId: "pending-receipts"))
    }

    func test_deliveries_module_is_in_navigation() {
        XCTAssertTrue(HubNavigation.allModules.contains { $0.id == "deliveries" })
    }
}
