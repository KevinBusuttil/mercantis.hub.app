import XCTest
import MercantisCore
@testable import Mercantis_Hub

/// Buy-side fulfilment: the remaining-qty conversion defaulting, receive-then-
/// bill, the receipt-status maths, and the DocType wiring behind the
/// over-receipt guard and the "Purchase Orders to Receive" report.
final class HubPurchaseOrderFulfilmentTests: XCTestCase {

    private func order(lines: [(item: String, qty: Double)]) -> Document {
        Document(
            id: "PO-1", docType: "PurchaseOrder", company: "Acme", status: "Submitted",
            createdAt: Date(), updatedAt: Date(), syncVersion: 0, syncState: .local,
            docStatus: 1,
            fields: [
                "supplier": .string("SUPP-1"),
                "currency": .string("EUR"),
                "set_warehouse": .string("WH-Main"),
            ],
            children: ["items": lines.enumerated().map { i, l in
                ChildRow(id: "r\(i)", rowIndex: i, fields: [
                    "item": .string(l.item), "qty": .double(l.qty),
                    "rate": .double(10), "uom": .string("Nos"),
                ])
            }]
        )
    }

    // MARK: - Conversion defaulting

    func test_purchaseOrderToReceipt_defaultsToRemaining_andDropsReceivedLines() {
        let src = order(lines: [("A", 10), ("B", 4)])
        let receipt = HubDocumentConversion.purchaseOrderToReceipt(src, receivedByItem: ["A": 6, "B": 4])

        XCTAssertEqual(receipt.docType, "PurchaseReceipt")
        XCTAssertEqual(receipt.status, "Draft")           // so "Submit" works on the converted draft
        let items = receipt.children["items"] ?? []
        XCTAssertEqual(items.count, 1, "Fully-received line B should be dropped")
        XCTAssertEqual(items[0].fields["item"], .string("A"))
        XCTAssertEqual(items[0].fields["qty"], .double(4), "Remaining A = 10 − 6")
        XCTAssertEqual(items[0].fields["purchase_order"], .string("PO-1"))
    }

    func test_purchaseOrderToInvoice_defaultsToRemaining_andCarriesLink() {
        var src = order(lines: [("A", 10)])
        src.children["items"]![0].fields["tax_code"] = .string("STD")
        let invoice = HubDocumentConversion.purchaseOrderToInvoice(src, billedByItem: ["A": 3])
        let items = invoice.children["items"] ?? []
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].fields["qty"], .double(7))
        XCTAssertEqual(items[0].fields["tax_code"], .string("STD"))
        XCTAssertEqual(invoice.fields["purchase_order"], .string("PO-1"))
    }

    func test_receiptToInvoice_carriesLinesAndLineage() {
        let receipt = Document(
            id: "PREC-9", docType: "PurchaseReceipt", company: "Acme", status: "",
            createdAt: Date(), updatedAt: Date(), syncVersion: 0, syncState: .local,
            docStatus: 1,
            fields: ["supplier": .string("SUPP-1"), "currency": .string("EUR"),
                     "purchase_order": .string("PO-1")],
            children: ["items": [
                ChildRow(id: "x0", rowIndex: 0, fields: ["item": .string("A"), "qty": .double(3)]),
                ChildRow(id: "x1", rowIndex: 1, fields: ["item": .string("B"), "qty": .double(2)]),
            ]]
        )
        let invoice = HubDocumentConversion.receiptToInvoice(receipt)
        XCTAssertEqual(invoice.docType, "PurchaseInvoice")
        XCTAssertEqual(invoice.fields["purchase_receipt"], .string("PREC-9"))
        XCTAssertEqual(invoice.fields["purchase_order"], .string("PO-1"), "Order link threads through")
        XCTAssertEqual(invoice.fields["supplier"], .string("SUPP-1"))
        XCTAssertEqual((invoice.children["items"] ?? []).count, 2)
    }

    // MARK: - Calculator

    func test_receiptStatus_thresholds() {
        XCTAssertEqual(SalesOrderFulfilmentCalculator.receiptStatus(orderedQty: 10, receivedQty: 0), "To Receive")
        XCTAssertEqual(SalesOrderFulfilmentCalculator.receiptStatus(orderedQty: 10, receivedQty: 4), "Partially Received")
        XCTAssertEqual(SalesOrderFulfilmentCalculator.receiptStatus(orderedQty: 10, receivedQty: 10), "Fully Received")
    }

    // MARK: - DocType wiring

    func test_purchaseOrder_hasFulfilmentFields_allAllowOnSubmit() {
        guard let po = HubManifest.docType(for: "PurchaseOrder") else { return XCTFail("PurchaseOrder missing") }
        for key in ["receipt_status", "received_qty", "per_received",
                    "billing_status", "billed_qty", "per_billed"] {
            guard let field = po.fields.first(where: { $0.key == key }) else {
                return XCTFail("PurchaseOrder missing fulfilment field \(key)")
            }
            XCTAssertTrue(field.allowOnSubmit, "\(key) must be editable on the submitted order")
        }
    }

    func test_purchaseInvoice_linksToOrderAndReceipt() {
        let keys = Set(HubManifest.docType(for: "PurchaseInvoice")?.fields.map(\.key) ?? [])
        XCTAssertTrue(keys.contains("purchase_order"))
        XCTAssertTrue(keys.contains("purchase_receipt"))
    }

    func test_company_hasOverReceiptFlag() {
        let keys = Set(HubManifest.docType(for: "Company")?.fields.map(\.key) ?? [])
        XCTAssertTrue(keys.contains("allow_over_receipt"))
    }

    func test_purchaseOrdersToReceive_reportRegistered() {
        XCTAssertNotNil(HubReports.report(forId: "purchase-orders-to-receive"))
    }
}
