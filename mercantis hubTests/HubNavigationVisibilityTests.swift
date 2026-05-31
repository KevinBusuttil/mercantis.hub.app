//
//  HubNavigationVisibilityTests.swift
//  mercantis hubTests
//
//  The everyday navigation surface must hide the internal AX-style audit /
//  accounting spine and the optional Manufacturing module; enabling advanced /
//  accountant mode must reveal them. Mirrors the filtering `RootView` applies.
//

import XCTest
import MercantisCore
@testable import Mercantis_Hub

@MainActor
final class HubNavigationVisibilityTests: XCTestCase {

    private var originalAdvanced: Bool!

    override func setUp() {
        super.setUp()
        originalAdvanced = UserDefaults.standard.bool(forKey: HubVisibilitySettings.defaultsKey)
    }

    override func tearDown() {
        UserDefaults.standard.set(originalAdvanced, forKey: HubVisibilitySettings.defaultsKey)
        super.tearDown()
    }

    /// Collects visible menu identifiers and labels under a given mode,
    /// applying the same module- and group-level filtering `RootView` uses.
    private func visibleIdentifiers(showAdvanced: Bool) -> (docTypes: Set<String>, reports: Set<String>, labels: Set<String>, modules: Set<String>) {
        let settings = HubVisibilitySettings()
        settings.showAdvanced = showAdvanced

        var docTypes = Set<String>()
        var reports = Set<String>()
        var labels = Set<String>()
        var modules = Set<String>()
        for module in HubNavigation.allModules where settings.isVisible(module.visibility) {
            modules.insert(module.label)
            for group in module.visibleGroups(settings) {
                for item in group.items {
                    labels.insert(item.label)
                    switch item {
                    case .docType(let d, _): docTypes.insert(d.id)
                    case .report(let id, _): reports.insert(id)
                    case .dashboard:         break
                    }
                }
            }
        }
        return (docTypes, reports, labels, modules)
    }

    func test_normal_mode_hides_internal_audit_and_manufacturing() {
        let (docTypes, reports, _, modules) = visibleIdentifiers(showAdvanced: false)

        for hidden in ["GLEntry", "CustTrans", "VendTrans", "Settlement", "TaxTrans",
                       "StockLedgerEntry", "JournalEntry"] {
            XCTAssertFalse(docTypes.contains(hidden), "\(hidden) must be hidden in normal mode")
        }
        // Manufacturing is a whole hidden module.
        for hidden in ["BOM", "WorkOrder", "JobCard", "ProductionPlan", "Workstation", "Operation"] {
            XCTAssertFalse(docTypes.contains(hidden), "Manufacturing DocType \(hidden) must be hidden in normal mode")
        }
        XCTAssertFalse(modules.contains("Manufacturing"), "Manufacturing module must be hidden in normal mode")
        XCTAssertFalse(reports.contains(HubReports.trialBalance.id), "Trial Balance must be hidden in normal mode")
    }

    func test_normal_mode_keeps_everyday_surface() {
        let (docTypes, reports, labels, _) = visibleIdentifiers(showAdvanced: false)

        for visible in ["Customer", "Supplier", "Item", "Quotation", "SalesOrder",
                        "SalesInvoice", "PurchaseOrder", "PurchaseInvoice",
                        "StockEntry", "PaymentEntry", "Account"] {
            XCTAssertTrue(docTypes.contains(visible), "\(visible) must stay visible in normal mode")
        }
        for visibleLabel in ["Customers", "Suppliers", "Items", "Warehouses",
                             "Stock Movements", "Payments"] {
            XCTAssertTrue(labels.contains(visibleLabel), "\(visibleLabel) must stay visible in normal mode")
        }
        for hidden in ["GL Entry", "CustTrans", "VendTrans", "Settlement", "TaxTrans",
                       "StockLedgerEntry", "JournalEntry", "Manufacturing"] {
            XCTAssertFalse(labels.contains(hidden), "\(hidden) should not be shown in normal mode")
        }
        // User-facing reports remain available.
        XCTAssertTrue(reports.contains(HubReports.customerStatement.id))
        XCTAssertTrue(reports.contains(HubReports.supplierLedger.id))
    }

    func test_menu_uses_friendly_labels_when_configured() {
        let (_, _, labels, _) = visibleIdentifiers(showAdvanced: false)

        XCTAssertTrue(labels.contains("Quotes"))
        XCTAssertTrue(labels.contains("Stock Movements"))
        XCTAssertTrue(labels.contains("Payments"))

        XCTAssertFalse(labels.contains("Quotation"))
        XCTAssertFalse(labels.contains("Stock Entry"))
        XCTAssertFalse(labels.contains("Payment Entry"))
    }

    func test_advanced_mode_reveals_internal_audit_and_manufacturing() {
        let (docTypes, reports, _, _) = visibleIdentifiers(showAdvanced: true)

        for revealed in ["GLEntry", "CustTrans", "VendTrans", "Settlement", "TaxTrans",
                         "StockLedgerEntry", "JournalEntry",
                         "BOM", "WorkOrder", "JobCard", "ProductionPlan"] {
            XCTAssertTrue(docTypes.contains(revealed), "\(revealed) must be visible in advanced mode")
        }
        XCTAssertTrue(reports.contains(HubReports.trialBalance.id), "Trial Balance must be visible in advanced mode")
    }

    func test_pos_shell_stays_out_of_navigation_in_all_modes() {
        for showAdvanced in [false, true] {
            let settings = HubVisibilitySettings()
            settings.showAdvanced = showAdvanced

            let labels = HubNavigation.allModules
                .filter { settings.isVisible($0.visibility) }
                .flatMap { $0.visibleGroups(settings) }
                .flatMap(\.items)
                .map(\.label)

            XCTAssertFalse(labels.contains("Point of Sale"), "POS should remain preview-only, not in navigation")
            XCTAssertFalse(labels.contains("POS"), "POS should remain preview-only, not in navigation")
        }
    }
}
