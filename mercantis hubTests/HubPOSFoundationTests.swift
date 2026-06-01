import XCTest
import MercantisCore
@testable import Mercantis_Hub

/// Phase 6 — POS v1 wiring guards.
@MainActor
final class HubPOSFoundationTests: XCTestCase {

    func test_pos_doctypes_are_registered() {
        for id in ["POSProfile", "POSSession", "POSInvoice", "PaymentTender"] {
            XCTAssertNotNil(HubManifest.docType(for: id), "\(id) must be registered")
        }
    }

    func test_pos_invoice_reuses_shared_line_and_tax_rows() {
        guard let pos = HubManifest.docType(for: "POSInvoice") else { return XCTFail("POSInvoice missing") }
        XCTAssertTrue(pos.isSubmittable)
        let items = pos.fields.first { $0.key == "items" }
        let taxes = pos.fields.first { $0.key == "taxes" }
        let tenders = pos.fields.first { $0.key == "tenders" }
        XCTAssertEqual(items?.childDocType, "SalesItem", "POS lines reuse SalesItem")
        XCTAssertEqual(taxes?.childDocType, "TaxCharge", "POS taxes reuse the shared tax row")
        XCTAssertEqual(tenders?.childDocType, "PaymentTender")
        let keys = Set(pos.fields.map(\.key))
        XCTAssertTrue(keys.isSuperset(of: ["grand_total", "net_total", "total_taxes",
                                           "paid_amount", "change_amount", "warehouse"]))
    }

    func test_pos_invoice_is_tax_aware() {
        XCTAssertTrue(HubTaxCalculationPolicy.supportedDocTypes.contains("POSInvoice"))
    }

    func test_pos_workflow_registered() {
        guard let wf = HubWorkflows.workflow(forDocTypeId: "POSInvoice") else {
            return XCTFail("wf-pos-invoice missing")
        }
        XCTAssertTrue(wf.transitions.contains { $0.from == "Draft" && $0.action == "Submit" })
    }

    func test_pos_module_is_gated_behind_the_feature_flag() {
        guard let posModule = HubNavigation.allModules.first(where: { $0.id == "pos" }) else {
            return XCTFail("POS module not registered")
        }
        XCTAssertTrue(posModule.requiresPOS)

        let settings = HubVisibilitySettings()
        settings.posEnabled = false
        XCTAssertFalse(settings.isModuleVisible(posModule), "POS hidden when the flag is off")
        settings.posEnabled = true
        XCTAssertTrue(settings.isModuleVisible(posModule), "POS visible when enabled")
    }

    func test_pos_checkout_flow_routes_through_navigation() {
        let flowIDs = HubNavigation.allModules
            .flatMap { $0.groups }.flatMap { $0.items }
            .compactMap { item -> String? in
                if case .flow(let id, _, _) = item { return id }
                return nil
            }
        XCTAssertTrue(flowIDs.contains("pos-checkout"))
    }
}
