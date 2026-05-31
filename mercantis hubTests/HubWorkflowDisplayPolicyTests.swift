//
//  HubWorkflowDisplayPolicyTests.swift
//  mercantis hubTests
//
//  Verifies the real Hub wording table maps each transactional DocType's
//  internal lifecycle / workflow states and actions onto the business labels,
//  tones and confirmation copy the product promises.
//

import XCTest
import MercantisCore
@testable import Mercantis_Hub

@MainActor
final class HubWorkflowDisplayPolicyTests: XCTestCase {

    private let policy = HubWorkflowDisplayPolicy.policy

    private func status(_ docType: String, _ state: String) -> DocumentStatusDisplay {
        policy.statusDisplay(docTypeId: docType, state: state)
    }
    private func action(_ docType: String, _ name: String) -> DocumentActionDisplay {
        policy.actionDisplay(docTypeId: docType, action: name)
    }

    // MARK: - Status wording

    func test_status_labels_per_doctype() {
        XCTAssertEqual(status("Quotation", "Submitted").label, "Sent")
        XCTAssertEqual(status("Quotation", "Ordered").label, "Accepted")
        XCTAssertEqual(status("SalesOrder", "Submitted").label, "Confirmed")
        XCTAssertEqual(status("SalesInvoice", "Submitted").label, "Posted")
        XCTAssertEqual(status("SupplierQuotation", "Submitted").label, "Received")
        XCTAssertEqual(status("PurchaseOrder", "Submitted").label, "Confirmed")
        XCTAssertEqual(status("PurchaseInvoice", "Submitted").label, "Posted")
        XCTAssertEqual(status("StockEntry", "Submitted").label, "Posted")
        XCTAssertEqual(status("StockEntry", "Cancelled").label, "Reversed")
        XCTAssertEqual(status("JournalEntry", "Submitted").label, "Posted")
        XCTAssertEqual(status("PaymentEntry", "Submitted").label, "Posted")
        XCTAssertEqual(status("PaymentEntry", "Reconciled").label, "Reconciled")
        XCTAssertEqual(status("BOM", "Submitted").label, "Active")
        XCTAssertEqual(status("WorkOrder", "Submitted").label, "Released")
        XCTAssertEqual(status("WorkOrder", "InProgress").label, "In Progress")
        XCTAssertEqual(status("WorkOrder", "Completed").label, "Completed")
        XCTAssertEqual(status("JobCard", "Submitted").label, "Completed")
        XCTAssertEqual(status("JobCard", "InProgress").label, "In Progress")
        XCTAssertEqual(status("ProductionPlan", "Submitted").label, "Planned")
    }

    func test_status_tones() {
        XCTAssertEqual(status("SalesInvoice", "Submitted").tone, .brand)
        XCTAssertEqual(status("SalesInvoice", "Paid").tone, .success)
        XCTAssertEqual(status("SalesInvoice", "Overdue").tone, .warning)
        XCTAssertEqual(status("StockEntry", "Cancelled").tone, .danger)
        XCTAssertEqual(status("BOM", "Submitted").tone, .success)
        XCTAssertEqual(status("Quotation", "Lost").tone, .danger)
    }

    func test_lifecycle_maps_docStatus_to_business_wording() {
        XCTAssertEqual(policy.lifecycleDisplay(docTypeId: "SalesInvoice", docStatus: 1).label, "Posted")
        XCTAssertEqual(policy.lifecycleDisplay(docTypeId: "SalesOrder", docStatus: 1).label, "Confirmed")
        XCTAssertEqual(policy.lifecycleDisplay(docTypeId: "StockEntry", docStatus: 2).label, "Reversed")
        XCTAssertEqual(policy.lifecycleDisplay(docTypeId: "BOM", docStatus: 1).label, "Active")
        XCTAssertEqual(policy.lifecycleDisplay(docTypeId: "SalesInvoice", docStatus: 0).label, "Draft")
    }

    // MARK: - Action wording

    func test_submit_action_labels() {
        XCTAssertEqual(action("SalesInvoice", "Submit").label, "Post Invoice")
        XCTAssertEqual(action("PurchaseInvoice", "Submit").label, "Post Bill")
        XCTAssertEqual(action("PaymentEntry", "Submit").label, "Post Payment")
        XCTAssertEqual(action("StockEntry", "Submit").label, "Post Stock Movement")
        XCTAssertEqual(action("JournalEntry", "Submit").label, "Post Journal")
        XCTAssertEqual(action("SalesOrder", "Submit").label, "Confirm Order")
        XCTAssertEqual(action("PurchaseOrder", "Submit").label, "Confirm Order")
        XCTAssertEqual(action("Quotation", "Submit").label, "Send Quote")
        XCTAssertEqual(action("SupplierQuotation", "Submit").label, "Record Supplier Quote")
        XCTAssertEqual(action("BOM", "Submit").label, "Activate BOM")
        XCTAssertEqual(action("WorkOrder", "Submit").label, "Release Work Order")
        XCTAssertEqual(action("JobCard", "Submit").label, "Complete Job")
        XCTAssertEqual(action("ProductionPlan", "Submit").label, "Release Plan")
    }

    func test_amend_action_labels() {
        XCTAssertEqual(action("SalesInvoice", "Amend").label, "Create Corrected Invoice")
        XCTAssertEqual(action("PurchaseInvoice", "Amend").label, "Create Corrected Bill")
        XCTAssertEqual(action("StockEntry", "Amend").label, "Create Correction")
        XCTAssertEqual(action("JournalEntry", "Amend").label, "Create Reversal / Correction")
        XCTAssertEqual(action("SalesOrder", "Amend").label, "Create Revised Order")
        XCTAssertEqual(action("PurchaseOrder", "Amend").label, "Create Revised Order")
        // Unmapped DocType falls back to the raw action name.
        XCTAssertEqual(action("Customer", "Amend").label, "Amend")
    }

    func test_ledger_and_stock_actions_require_confirmation() {
        XCTAssertTrue(action("SalesInvoice", "Submit").requiresConfirmation)
        XCTAssertTrue(action("SalesInvoice", "Cancel").requiresConfirmation)
        XCTAssertTrue(action("StockEntry", "Submit").requiresConfirmation)
        XCTAssertTrue(action("StockEntry", "Cancel").requiresConfirmation)
        XCTAssertTrue(action("PaymentEntry", "Submit").requiresConfirmation)
        // Work Order completion posts a manufacturing stock movement → warn.
        XCTAssertTrue(action("WorkOrder", "Complete").requiresConfirmation)
        // A non-ledger transition needs no confirmation.
        XCTAssertFalse(action("SalesOrder", "Submit").requiresConfirmation)
        XCTAssertFalse(action("WorkOrder", "Start").requiresConfirmation)
    }

    // MARK: - Fallbacks

    func test_unknown_doctype_and_state_fall_back_safely() {
        XCTAssertEqual(status("NotADocType", "Whatever").label, "Whatever")
        XCTAssertEqual(action("NotADocType", "Frobnicate").label, "Frobnicate")
        XCTAssertFalse(policy.hasMapping(docTypeId: "Customer"))
        XCTAssertTrue(policy.hasMapping(docTypeId: "SalesInvoice"))
    }
}
