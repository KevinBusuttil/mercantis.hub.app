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

    /// Collects the DocType ids and report ids visible under a given mode,
    /// applying the same module- and group-level filtering `RootView` uses.
    private func visibleIdentifiers(showAdvanced: Bool) -> (docTypes: Set<String>, reports: Set<String>) {
        let settings = HubVisibilitySettings()
        settings.showAdvanced = showAdvanced

        var docTypes = Set<String>()
        var reports = Set<String>()
        for module in HubNavigation.allModules where settings.isVisible(module.visibility) {
            for group in module.visibleGroups(settings) {
                for item in group.items {
                    switch item {
                    case .docType(let d):    docTypes.insert(d.id)
                    case .report(let id, _): reports.insert(id)
                    case .dashboard:         break
                    }
                }
            }
        }
        return (docTypes, reports)
    }

    func test_normal_mode_hides_internal_audit_and_manufacturing() {
        let (docTypes, reports) = visibleIdentifiers(showAdvanced: false)

        for hidden in ["GLEntry", "CustTrans", "VendTrans", "Settlement", "TaxTrans",
                       "StockLedgerEntry", "JournalEntry"] {
            XCTAssertFalse(docTypes.contains(hidden), "\(hidden) must be hidden in normal mode")
        }
        // Manufacturing is a whole hidden module.
        for hidden in ["BOM", "WorkOrder", "JobCard", "ProductionPlan", "Workstation", "Operation"] {
            XCTAssertFalse(docTypes.contains(hidden), "Manufacturing DocType \(hidden) must be hidden in normal mode")
        }
        XCTAssertFalse(reports.contains(HubReports.trialBalance.id), "Trial Balance must be hidden in normal mode")
    }

    func test_normal_mode_keeps_everyday_surface() {
        let (docTypes, reports) = visibleIdentifiers(showAdvanced: false)

        for visible in ["Customer", "Supplier", "Item", "Quotation", "SalesOrder",
                        "SalesInvoice", "PurchaseOrder", "PurchaseInvoice",
                        "StockEntry", "PaymentEntry", "Account"] {
            XCTAssertTrue(docTypes.contains(visible), "\(visible) must stay visible in normal mode")
        }
        // User-facing reports remain available.
        XCTAssertTrue(reports.contains(HubReports.customerStatement.id))
        XCTAssertTrue(reports.contains(HubReports.supplierLedger.id))
    }

    func test_advanced_mode_reveals_internal_audit_and_manufacturing() {
        let (docTypes, reports) = visibleIdentifiers(showAdvanced: true)

        for revealed in ["GLEntry", "CustTrans", "VendTrans", "Settlement", "TaxTrans",
                         "StockLedgerEntry", "JournalEntry",
                         "BOM", "WorkOrder", "JobCard", "ProductionPlan"] {
            XCTAssertTrue(docTypes.contains(revealed), "\(revealed) must be visible in advanced mode")
        }
        XCTAssertTrue(reports.contains(HubReports.trialBalance.id), "Trial Balance must be visible in advanced mode")
    }
}
