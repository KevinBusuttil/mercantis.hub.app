//
//  HubMasterDataLifecycleTests.swift
//  mercantis hubTests
//
//  Master data must never enter the Submit/Cancel lifecycle — only the
//  transactional DocTypes that create ledger / stock / tax effects are
//  submittable. Guards against accidentally flipping `isSubmittable` on a
//  master DocType in a future change.
//

import XCTest
import MercantisCore
@testable import Mercantis_Hub

@MainActor
final class HubMasterDataLifecycleTests: XCTestCase {

    private static let masterDataDocTypes = [
        "Customer", "Supplier", "Item", "Contact", "Address",
        "Currency", "UOM", "Brand", "Warehouse", "Account",
        "CostCenter", "PriceList", "Workstation", "Operation",
    ]

    private static let auditDocTypes = [
        "GLEntry", "CustTrans", "VendTrans", "Settlement", "TaxTrans", "StockLedgerEntry",
    ]

    private static let submittableDocTypes = [
        "Quotation", "SalesOrder", "SalesInvoice",
        "SupplierQuotation", "PurchaseOrder", "PurchaseInvoice",
        "StockEntry", "JournalEntry", "PaymentEntry",
        "BOM", "WorkOrder", "JobCard", "ProductionPlan",
    ]

    func test_master_data_is_not_submittable() {
        for id in Self.masterDataDocTypes {
            guard let docType = HubManifest.docType(for: id) else {
                XCTFail("Master DocType '\(id)' not found in HubManifest")
                continue
            }
            XCTAssertFalse(docType.isSubmittable, "Master DocType '\(id)' must not be submittable")
        }
    }

    func test_audit_tables_are_not_submittable() {
        for id in Self.auditDocTypes {
            guard let docType = HubManifest.docType(for: id) else {
                XCTFail("Audit DocType '\(id)' not found in HubManifest")
                continue
            }
            XCTAssertFalse(docType.isSubmittable, "Audit DocType '\(id)' must not be submittable")
        }
    }

    func test_transactional_doctypes_are_submittable() {
        for id in Self.submittableDocTypes {
            guard let docType = HubManifest.docType(for: id) else {
                XCTFail("Transactional DocType '\(id)' not found in HubManifest")
                continue
            }
            XCTAssertTrue(docType.isSubmittable, "Transactional DocType '\(id)' must be submittable")
        }
    }
}
