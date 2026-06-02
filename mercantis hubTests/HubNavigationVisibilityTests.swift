//
//  HubNavigationVisibilityTests.swift
//  mercantis hubTests
//
//  The everyday navigation surface must hide the internal AX-style audit /
//  accounting spine (via the advanced toggle) and the optional POS /
//  Deliveries / Manufacturing modules (via preset capability flags);
//  enabling each must reveal the matching surface. Mirrors the filtering
//  `RootView` applies through `isModuleVisible`.
//

import XCTest
import MercantisCore
@testable import Mercantis_Hub

@MainActor
final class HubNavigationVisibilityTests: XCTestCase {

    private var snapshot: [String: Any?] = [:]
    private let keys = [
        HubVisibilitySettings.defaultsKey,
        HubVisibilitySettings.posEnabledKey,
        HubVisibilitySettings.deliveriesEnabledKey,
        HubVisibilitySettings.manufacturingEnabledKey,
        HubVisibilitySettings.onboardingDoneKey,
        HubVisibilitySettings.presetKey,
    ]

    override func setUp() {
        super.setUp()
        for key in keys { snapshot[key] = UserDefaults.standard.object(forKey: key) }
    }

    override func tearDown() {
        for key in keys { UserDefaults.standard.set(snapshot[key] ?? nil, forKey: key) }
        super.tearDown()
    }

    // MARK: - Surface collection (mirrors RootView)

    private struct Surface {
        var docTypes = Set<String>()
        var reports = Set<String>()
        var flows = Set<String>()
        var labels = Set<String>()
        var modules = Set<String>()
    }

    private func surface(
        advanced: Bool = false,
        pos: Bool = false,
        deliveries: Bool = false,
        manufacturing: Bool = false
    ) -> Surface {
        let settings = HubVisibilitySettings()
        settings.showAdvanced = advanced
        settings.posEnabled = pos
        settings.deliveriesEnabled = deliveries
        settings.manufacturingEnabled = manufacturing

        var s = Surface()
        for module in HubNavigation.allModules where settings.isModuleVisible(module) {
            s.modules.insert(module.label)
            for group in module.visibleGroups(settings) {
                for item in group.items {
                    s.labels.insert(item.label)
                    switch item {
                    case .docType(let d, _): s.docTypes.insert(d.id)
                    case .report(let id, _): s.reports.insert(id)
                    case .flow(let id, _, _): s.flows.insert(id)
                    case .dashboard:         break
                    case .customReports:     break
                    }
                }
            }
        }
        return s
    }

    // MARK: - Defaults: optional modules + audit hidden

    func test_default_surface_hides_optional_modules() {
        let s = surface()
        XCTAssertFalse(s.modules.contains("Manufacturing"))
        XCTAssertFalse(s.modules.contains("POS"))
        XCTAssertFalse(s.modules.contains("Deliveries"))
        XCTAssertFalse(s.flows.contains("pos-checkout"))
        XCTAssertFalse(s.docTypes.contains("BOM"))
        XCTAssertFalse(s.docTypes.contains("DeliveryRoute"))
    }

    func test_default_surface_hides_internal_audit_spine() {
        let s = surface()
        for hidden in ["GLEntry", "CustTrans", "VendTrans", "Settlement", "TaxTrans",
                       "StockLedgerEntry", "JournalEntry"] {
            XCTAssertFalse(s.docTypes.contains(hidden), "\(hidden) must be hidden by default")
        }
        XCTAssertFalse(s.reports.contains(HubReports.trialBalance.id))
    }

    func test_default_surface_keeps_everyday_modules() {
        let s = surface()
        for visible in ["Customer", "Supplier", "Item", "SalesOrder", "SalesInvoice",
                        "PurchaseInvoice", "StockEntry", "PaymentEntry", "Account", "Company"] {
            XCTAssertTrue(s.docTypes.contains(visible), "\(visible) must stay visible")
        }
        // Guided payment flows live on the everyday Money/Sell surface.
        XCTAssertTrue(s.flows.contains("guided-receive-payment"))
    }

    // MARK: - Advanced reveals the audit spine (but not optional modules)

    func test_advanced_reveals_audit_spine_only() {
        let s = surface(advanced: true)
        for revealed in ["GLEntry", "CustTrans", "VendTrans", "Settlement", "TaxTrans",
                         "StockLedgerEntry", "JournalEntry"] {
            XCTAssertTrue(s.docTypes.contains(revealed), "\(revealed) must show in advanced mode")
        }
        XCTAssertTrue(s.reports.contains(HubReports.trialBalance.id))
        // Manufacturing is gated by its capability, not the advanced toggle.
        XCTAssertFalse(s.modules.contains("Manufacturing"))
    }

    // MARK: - Capability flags reveal optional modules

    func test_pos_capability_reveals_pos_module() {
        let s = surface(pos: true)
        XCTAssertTrue(s.modules.contains("POS"))
        XCTAssertTrue(s.flows.contains("pos-checkout"))
        XCTAssertTrue(s.docTypes.contains("POSInvoice"))
    }

    func test_deliveries_capability_reveals_routes() {
        let s = surface(deliveries: true)
        XCTAssertTrue(s.modules.contains("Deliveries"))
        XCTAssertTrue(s.docTypes.contains("DeliveryRoute"))
        XCTAssertTrue(s.docTypes.contains("SalesDelivery"))
    }

    func test_manufacturing_capability_reveals_production() {
        let s = surface(manufacturing: true)
        XCTAssertTrue(s.modules.contains("Manufacturing"))
        for revealed in ["BOM", "WorkOrder", "JobCard", "ProductionPlan"] {
            XCTAssertTrue(s.docTypes.contains(revealed), "\(revealed) must show when manufacturing is on")
        }
    }

    // MARK: - Friendly labels

    func test_menu_uses_friendly_labels() {
        let s = surface()
        XCTAssertTrue(s.labels.contains("Quotes"))
        XCTAssertTrue(s.labels.contains("Stock Movements"))
        XCTAssertFalse(s.labels.contains("Quotation"))
        XCTAssertFalse(s.labels.contains("Stock Entry"))
    }

    func test_module_badges_are_not_menu_counts() {
        for module in HubNavigation.allModules {
            XCTAssertNil(module.businessBadge, "\(module.label) should not show menu-count badges")
        }
    }
}
