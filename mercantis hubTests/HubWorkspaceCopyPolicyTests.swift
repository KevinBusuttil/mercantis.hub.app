import XCTest
import MercantisCore
@testable import Mercantis_Hub

@MainActor
final class HubWorkspaceCopyPolicyTests: XCTestCase {

    func test_business_specific_copy_for_key_doctypes() {
        let company = HubWorkspaceCopyPolicy.copy(for: Setup.company)
        XCTAssertEqual(company.title, "Business Profile")
        XCTAssertEqual(company.subtitle, "Store your business identity and operational defaults in one place.")
        XCTAssertEqual(company.primaryActionTitle, "New Business Profile")
        XCTAssertEqual(company.emptyStateTitle, "No business profile yet")

        let supplier = HubWorkspaceCopyPolicy.copy(for: Buying.supplier)
        XCTAssertEqual(supplier.title, "Suppliers")
        XCTAssertEqual(supplier.subtitle, "Manage supplier profiles, purchasing defaults, and payment details.")
        XCTAssertEqual(supplier.primaryActionTitle, "New Supplier")
        XCTAssertEqual(supplier.emptyStateTitle, "No suppliers yet")
        XCTAssertEqual(supplier.emptyStateMessage, "Create your first supplier to start recording purchases and supplier bills.")

        let customer = HubWorkspaceCopyPolicy.copy(for: CRM.customer)
        XCTAssertEqual(customer.primaryActionTitle, "New Customer")

        let item = HubWorkspaceCopyPolicy.copy(for: Selling.item)
        XCTAssertEqual(item.subtitle, "Manage products, services, units, pricing, and stock behaviour.")

        let stockMovement = HubWorkspaceCopyPolicy.copy(for: Stock.stockEntry)
        XCTAssertEqual(stockMovement.primaryActionTitle, "New Stock Movement")
        XCTAssertEqual(stockMovement.subtitle, "Record stock receipts, issues, transfers, and adjustments.")
    }

    func test_friendly_new_labels_are_used_where_configured() {
        XCTAssertEqual(HubWorkspaceCopyPolicy.copy(for: Selling.quotation).primaryActionTitle, "New Quote")
        XCTAssertEqual(HubWorkspaceCopyPolicy.copy(for: Selling.salesOrder).primaryActionTitle, "New Sales Order")
        XCTAssertEqual(HubWorkspaceCopyPolicy.copy(for: Selling.salesInvoice).primaryActionTitle, "New Sales Invoice")
        XCTAssertEqual(HubWorkspaceCopyPolicy.copy(for: Buying.purchaseOrder).primaryActionTitle, "New Purchase Order")
        XCTAssertEqual(HubWorkspaceCopyPolicy.copy(for: Buying.purchaseInvoice).primaryActionTitle, "New Bill")
        XCTAssertEqual(HubWorkspaceCopyPolicy.copy(for: Accounting.paymentEntry).primaryActionTitle, "New Payment")
    }

    func test_setup_foundation_copy_for_fiscal_year_and_numbering() {
        let fiscalYear = HubWorkspaceCopyPolicy.copy(for: Setup.fiscalYear)
        XCTAssertEqual(fiscalYear.title, "Fiscal Years")
        XCTAssertEqual(fiscalYear.primaryActionTitle, "New Fiscal Year")
        XCTAssertEqual(fiscalYear.emptyStateTitle, "No fiscal year yet")

        let numbering = HubWorkspaceCopyPolicy.copy(for: Setup.numberingSeries)
        XCTAssertEqual(numbering.title, "Numbering Series")
        XCTAssertEqual(numbering.primaryActionTitle, "New Numbering Series")
        XCTAssertEqual(numbering.emptyStateTitle, "No numbering configured")
    }
}
