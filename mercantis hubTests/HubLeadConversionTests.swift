import XCTest
import MercantisCore
@testable import Mercantis_Hub

/// One-click Lead → Quotation: the pure Customer / Quotation draft builders.
final class HubLeadConversionTests: XCTestCase {

    private func lead(fields: [String: FieldValue]) -> Document {
        Document(
            id: "CRM-LEAD-1", docType: "Lead", company: "Acme", status: "Open",
            createdAt: Date(), updatedAt: Date(), syncVersion: 0, syncState: .local,
            docStatus: 0, fields: fields, children: [:]
        )
    }

    func test_leadToCustomer_companyLead_becomesCompany() {
        let customer = HubDocumentConversion.leadToCustomer(lead(fields: [
            "lead_name": .string("Jane Doe"),
            "company_name": .string("Globex Ltd"),
            "email_id": .string("jane@globex.com"),
            "mobile_no": .string("+356 9900 0000"),
            "territory": .string("Malta"),
        ]))
        XCTAssertEqual(customer.docType, "Customer")
        XCTAssertTrue(customer.id.isEmpty)            // engine names it on save
        XCTAssertEqual(customer.company, "Acme")
        XCTAssertEqual(customer.fields["customer_type"], .string("Company"))
        XCTAssertEqual(customer.fields["customer_name"], .string("Globex Ltd"))
        XCTAssertEqual(customer.fields["email"], .string("jane@globex.com"))
        XCTAssertEqual(customer.fields["mobile"], .string("+356 9900 0000"))
        XCTAssertEqual(customer.fields["territory"], .string("Malta"))
    }

    func test_leadToCustomer_individualLead_becomesIndividualNamedAfterLead() {
        let customer = HubDocumentConversion.leadToCustomer(lead(fields: [
            "lead_name": .string("John Smith"),
            "phone": .string("21234567"),
        ]))
        XCTAssertEqual(customer.fields["customer_type"], .string("Individual"))
        XCTAssertEqual(customer.fields["customer_name"], .string("John Smith"))
        XCTAssertEqual(customer.fields["phone"], .string("21234567"))
        XCTAssertNil(customer.fields["email"])
    }

    func test_quotationForCustomer_setsHeaderAndOpportunity() {
        let quote = HubDocumentConversion.quotationForCustomer(
            customerId: "CUST-1", opportunityId: "CRM-OPP-7", company: "Acme")
        XCTAssertEqual(quote.docType, "Quotation")
        XCTAssertEqual(quote.docStatus, 0)
        XCTAssertEqual(quote.fields["customer"], .string("CUST-1"))
        XCTAssertEqual(quote.fields["opportunity"], .string("CRM-OPP-7"))
        XCTAssertNotNil(quote.fields["transaction_date"])
        XCTAssertTrue((quote.children["items"] ?? []).isEmpty)
    }

    func test_quotationForCustomer_omitsOpportunityWhenNil() {
        let quote = HubDocumentConversion.quotationForCustomer(
            customerId: "CUST-1", opportunityId: nil, company: "Acme")
        XCTAssertNil(quote.fields["opportunity"])
    }
}
