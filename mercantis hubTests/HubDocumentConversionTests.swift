import XCTest
import MercantisCore
@testable import Mercantis_Hub

/// Unit tests for the pure document-conversion builders. They are pure
/// functions of the source document, so no engine / database is needed.
final class HubDocumentConversionTests: XCTestCase {

    private func quotation() -> Document {
        Document(
            id: "SQTN-1", docType: "Quotation", company: "Acme", status: "Submitted",
            createdAt: Date(), updatedAt: Date(), syncVersion: 0, syncState: .local,
            docStatus: 1,
            fields: [
                "customer": .string("CUST-1"),
                "currency": .string("EUR"),
                "tax_code": .string("STD"),
            ],
            children: ["items": [
                ChildRow(id: "r0", rowIndex: 0, fields: [
                    "item": .string("ITEM-1"), "description": .string("Sunflower Oil Tanks"),
                    "qty": .double(2), "rate": .double(3.5), "uom": .string("Litres"),
                ]),
            ]]
        )
    }

    func test_quotationToSalesOrder_carriesHeaderItemsAndLineage() {
        let order = HubDocumentConversion.quotationToSalesOrder(quotation())

        XCTAssertEqual(order.docType, "SalesOrder")
        XCTAssertEqual(order.docStatus, 0)               // a fresh draft
        XCTAssertEqual(order.status, "Draft")            // workflow initial state, so Submit works
        XCTAssertTrue(order.id.isEmpty)                  // unsaved; engine names it
        XCTAssertEqual(order.company, "Acme")
        // Lineage + header carried over.
        XCTAssertEqual(order.fields["quotation"], .string("SQTN-1"))
        XCTAssertEqual(order.fields["customer"], .string("CUST-1"))
        XCTAssertEqual(order.fields["currency"], .string("EUR"))
        XCTAssertEqual(order.fields["tax_code"], .string("STD"))

        // Item line carried over with its details.
        let items = order.children["items"] ?? []
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].fields["item"], .string("ITEM-1"))
        XCTAssertEqual(items[0].fields["description"], .string("Sunflower Oil Tanks"))
        XCTAssertEqual(items[0].fields["qty"], .double(2))
        XCTAssertEqual(items[0].fields["rate"], .double(3.5))
    }
}
