import XCTest
import MercantisCore
@testable import Mercantis_Hub

/// Phase 2 — VAT / Tax Foundation metadata wiring guards. Ensures the tax
/// masters, invoice tax rows, party/item defaults, and the VAT Summary
/// report stay registered in the manifest.
final class HubTaxFoundationTests: XCTestCase {

    func test_tax_master_doctypes_are_registered() {
        for id in ["TaxCategory", "TaxCode", "TaxCharge"] {
            XCTAssertNotNil(HubManifest.docType(for: id), "Tax DocType '\(id)' must be registered")
        }
    }

    func test_tax_code_exposes_rate_type_and_account() {
        guard let taxCode = HubManifest.docType(for: "TaxCode") else {
            return XCTFail("TaxCode not registered")
        }
        let keys = Set(taxCode.fields.map(\.key))
        XCTAssertTrue(keys.isSuperset(of: ["tax_code_name", "tax_type", "rate", "tax_account"]))
        XCTAssertFalse(taxCode.isSubmittable, "Tax masters must not be submittable")
    }

    func test_tax_charge_is_a_child_table_with_amounts() {
        guard let charge = HubManifest.docType(for: "TaxCharge") else {
            return XCTFail("TaxCharge not registered")
        }
        XCTAssertTrue(charge.isChildTable)
        let keys = Set(charge.fields.map(\.key))
        XCTAssertTrue(keys.isSuperset(of: ["tax_code", "rate", "taxable_amount", "tax_amount", "tax_account"]))
    }

    func test_sales_and_purchase_invoices_carry_tax_rows_and_totals() {
        for id in ["SalesInvoice", "PurchaseInvoice"] {
            guard let docType = HubManifest.docType(for: id) else {
                return XCTFail("\(id) not registered")
            }
            let keys = Set(docType.fields.map(\.key))
            XCTAssertTrue(keys.contains("taxes"), "\(id) must have a taxes table")
            XCTAssertTrue(keys.contains("net_total"), "\(id) must have net_total")
            XCTAssertTrue(keys.contains("total_taxes"), "\(id) must have total_taxes")
            XCTAssertTrue(keys.contains("tax_code"), "\(id) must have a document-level tax_code")

            let taxesField = docType.fields.first { $0.key == "taxes" }
            XCTAssertEqual(taxesField?.childDocType, "TaxCharge")
        }
    }

    func test_party_and_item_masters_have_tax_defaults() {
        for id in ["Customer", "Supplier", "Item"] {
            guard let docType = HubManifest.docType(for: id) else {
                return XCTFail("\(id) not registered")
            }
            XCTAssertTrue(
                docType.fields.contains { $0.key == "tax_code" },
                "\(id) must expose a default tax_code"
            )
        }
    }

    func test_line_item_tables_support_per_line_tax_code() {
        for id in ["SalesItem", "PurchaseItem"] {
            guard let docType = HubManifest.docType(for: id) else {
                return XCTFail("\(id) not registered")
            }
            XCTAssertTrue(
                docType.fields.contains { $0.key == "tax_code" },
                "\(id) must support a per-line tax_code override"
            )
        }
    }

    func test_vat_summary_report_is_registered() {
        XCTAssertNotNil(HubReports.report(forId: "vat-summary"))
        XCTAssertTrue(HubReports.allReports.contains { $0.id == "vat-summary" })
    }
}
