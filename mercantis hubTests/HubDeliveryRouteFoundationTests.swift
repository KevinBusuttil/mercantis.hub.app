import XCTest
import MercantisCore
@testable import Mercantis_Hub

/// Phase 7 — Delivery Routes & Tracking wiring guards.
final class HubDeliveryRouteFoundationTests: XCTestCase {

    func test_route_doctypes_are_registered() {
        for id in ["Driver", "Vehicle", "DeliveryRoute", "DeliveryRouteStop", "DeliveryStatusEvent"] {
            XCTAssertNotNil(HubManifest.docType(for: id), "\(id) must be registered")
        }
    }

    func test_route_has_date_driver_vehicle_and_stops() {
        guard let route = HubManifest.docType(for: "DeliveryRoute") else { return XCTFail("DeliveryRoute missing") }
        let keys = Set(route.fields.map(\.key))
        XCTAssertTrue(keys.isSuperset(of: ["route_date", "driver", "vehicle", "status", "stops"]))
        let stops = route.fields.first { $0.key == "stops" }
        XCTAssertEqual(stops?.childDocType, "DeliveryRouteStop")
    }

    func test_stop_supports_required_status_vocabulary_and_sequence_and_pod() {
        guard let stop = HubManifest.docType(for: "DeliveryRouteStop") else { return XCTFail("stop missing") }
        XCTAssertTrue(stop.isChildTable)
        let keys = Set(stop.fields.map(\.key))
        XCTAssertTrue(keys.isSuperset(of: ["sequence", "sales_delivery", "status", "pod_note", "pod_image"]))

        let statusField = stop.fields.first { $0.key == "status" }
        let options = Set(statusField?.options ?? [])
        XCTAssertTrue(options.isSuperset(of: [
            "Pending", "Loaded", "Out for Delivery", "Delivered", "Failed", "Rescheduled",
        ]), "Stop must offer the full status vocabulary")
    }

    func test_sales_delivery_shows_linked_route_and_status() {
        let keys = Set(HubManifest.docType(for: "SalesDelivery")?.fields.map(\.key) ?? [])
        XCTAssertTrue(keys.contains("delivery_route"))
        XCTAssertTrue(keys.contains("route_status"))
    }

    func test_route_dashboard_and_today_report_registered() {
        XCTAssertNotNil(HubReports.report(forId: "todays-routes"))
        XCTAssertNotNil(HubDashboards.dashboard(forId: "deliveries-overview"))
    }

    func test_route_doctypes_surface_in_deliveries_module() {
        let module = HubNavigation.allModules.first { $0.id == "deliveries" }
        let docTypeIDs = (module?.groups ?? [])
            .flatMap { $0.items }
            .compactMap { item -> String? in
                if case .docType(let d, _) = item { return d.id }
                return nil
            }
        XCTAssertTrue(docTypeIDs.contains("DeliveryRoute"))
        XCTAssertTrue(docTypeIDs.contains("Driver"))
        XCTAssertTrue(docTypeIDs.contains("Vehicle"))
    }

    // MARK: - Pure planner

    func test_planner_emits_event_only_on_status_change() {
        XCTAssertTrue(DeliveryRoutePlanner.shouldEmitEvent(lastStatus: nil, current: "Pending"))
        XCTAssertTrue(DeliveryRoutePlanner.shouldEmitEvent(lastStatus: "Pending", current: "Delivered"))
        XCTAssertFalse(DeliveryRoutePlanner.shouldEmitEvent(lastStatus: "Delivered", current: "Delivered"))
    }

    func test_planner_event_id_is_deterministic() {
        XCTAssertEqual(
            DeliveryRoutePlanner.eventID(routeId: "ROUTE-1", sequence: 2, existingCount: 0),
            "DSE-ROUTE-1-2-0"
        )
    }
}
