import XCTest
import MercantisCore
@testable import Mercantis_Hub

/// Sales↔Deliveries fulfilment: the fulfilment maths, the remaining-qty
/// conversion defaulting, deliver-then-invoice, and the DocType wiring that
/// backs the over-delivery guard and the fulfilment report. Pure where it can
/// be (no engine), so the arithmetic is fast and deterministic.
final class HubSalesOrderFulfilmentTests: XCTestCase {

    // MARK: - Fixtures

    private func order(lines: [(item: String, qty: Double)]) -> Document {
        Document(
            id: "SO-1", docType: "SalesOrder", company: "Acme", status: "Submitted",
            createdAt: Date(), updatedAt: Date(), syncVersion: 0, syncState: .local,
            docStatus: 1,
            fields: [
                "customer": .string("CUST-1"),
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

    private func fulfilment(docType: String, id: String, docStatus: Int,
                            lines: [(item: String, qty: Double)]) -> Document {
        Document(
            id: id, docType: docType, company: "Acme", status: "",
            createdAt: Date(), updatedAt: Date(), syncVersion: 0, syncState: .local,
            docStatus: docStatus,
            fields: ["sales_order": .string("SO-1")],
            children: ["items": lines.enumerated().map { i, l in
                ChildRow(id: "\(id)-r\(i)", rowIndex: i, fields: [
                    "item": .string(l.item), "qty": .double(l.qty),
                ])
            }]
        )
    }

    // MARK: - Calculator

    func test_fulfilledByItem_countsOnlySubmitted_andSumsPerItem() {
        let docs = [
            fulfilment(docType: "SalesDelivery", id: "DN-1", docStatus: 1,
                       lines: [("A", 3), ("B", 1)]),
            fulfilment(docType: "SalesDelivery", id: "DN-2", docStatus: 1, lines: [("A", 2)]),
            fulfilment(docType: "SalesDelivery", id: "DN-D", docStatus: 0, lines: [("A", 5)]), // draft — ignored
            fulfilment(docType: "SalesDelivery", id: "DN-C", docStatus: 2, lines: [("A", 9)]), // cancelled — ignored
        ]
        let byItem = SalesOrderFulfilmentCalculator.fulfilledByItem(docs)
        XCTAssertEqual(byItem["A"], 5)
        XCTAssertEqual(byItem["B"], 1)
        XCTAssertEqual(SalesOrderFulfilmentCalculator.total(byItem), 6)
    }

    func test_deliveryStatus_thresholds() {
        XCTAssertEqual(SalesOrderFulfilmentCalculator.deliveryStatus(orderedQty: 10, deliveredQty: 0), "To Deliver")
        XCTAssertEqual(SalesOrderFulfilmentCalculator.deliveryStatus(orderedQty: 10, deliveredQty: 4), "Partially Delivered")
        XCTAssertEqual(SalesOrderFulfilmentCalculator.deliveryStatus(orderedQty: 10, deliveredQty: 10), "Fully Delivered")
        // Over-delivery still reads as fully delivered.
        XCTAssertEqual(SalesOrderFulfilmentCalculator.deliveryStatus(orderedQty: 10, deliveredQty: 12), "Fully Delivered")
    }

    func test_billingStatus_thresholds() {
        XCTAssertEqual(SalesOrderFulfilmentCalculator.billingStatus(orderedQty: 5, billedQty: 0), "To Bill")
        XCTAssertEqual(SalesOrderFulfilmentCalculator.billingStatus(orderedQty: 5, billedQty: 2.5), "Partially Billed")
        XCTAssertEqual(SalesOrderFulfilmentCalculator.billingStatus(orderedQty: 5, billedQty: 5), "Fully Billed")
    }

    func test_percent_capsAt100_andHandlesZeroOrder() {
        XCTAssertEqual(SalesOrderFulfilmentCalculator.percent(orderedQty: 10, fulfilledQty: 5), 50, accuracy: 0.0001)
        XCTAssertEqual(SalesOrderFulfilmentCalculator.percent(orderedQty: 10, fulfilledQty: 25), 100, accuracy: 0.0001)
        XCTAssertEqual(SalesOrderFulfilmentCalculator.percent(orderedQty: 0, fulfilledQty: 3), 0, accuracy: 0.0001)
    }

    func test_orderedQty_sumsLines() {
        XCTAssertEqual(SalesOrderFulfilmentCalculator.orderedQty(order(lines: [("A", 3), ("B", 7)])), 10)
    }

    // MARK: - Remaining-qty conversion defaulting

    func test_salesOrderToDelivery_defaultsToRemaining_andDropsFulfilledLines() {
        let src = order(lines: [("A", 10), ("B", 4)])
        // 6 of A already delivered, all 4 of B delivered.
        let delivery = HubDocumentConversion.salesOrderToDelivery(src, deliveredByItem: ["A": 6, "B": 4])

        XCTAssertEqual(delivery.docType, "SalesDelivery")
        XCTAssertEqual(delivery.status, "Draft")          // so "Submit" works on the converted draft
        let items = delivery.children["items"] ?? []
        XCTAssertEqual(items.count, 1, "Fully-delivered line B should be dropped")
        XCTAssertEqual(items[0].fields["item"], .string("A"))
        XCTAssertEqual(items[0].fields["qty"], .double(4), "Remaining A = 10 − 6")
        XCTAssertEqual(items[0].fields["sales_order"], .string("SO-1"))
        XCTAssertEqual(items[0].rowIndex, 0, "Rows reindex after dropping")
    }

    func test_salesOrderToDelivery_noPriorDelivery_carriesFullQty() {
        let delivery = HubDocumentConversion.salesOrderToDelivery(order(lines: [("A", 10)]))
        let items = delivery.children["items"] ?? []
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].fields["qty"], .double(10))
    }

    func test_salesOrderToInvoice_defaultsToRemaining_andCarriesTaxLink() {
        var src = order(lines: [("A", 10)])
        src.children["items"]![0].fields["tax_code"] = .string("STD")
        let invoice = HubDocumentConversion.salesOrderToInvoice(src, billedByItem: ["A": 3])
        let items = invoice.children["items"] ?? []
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].fields["qty"], .double(7))
        XCTAssertEqual(items[0].fields["tax_code"], .string("STD"))
        XCTAssertEqual(invoice.fields["sales_order"], .string("SO-1"))
    }

    // MARK: - Deliver-then-invoice

    func test_deliveryToInvoice_carriesLinesAndLineage() {
        var delivery = fulfilment(docType: "SalesDelivery", id: "DN-9", docStatus: 1,
                                  lines: [("A", 3), ("B", 2)])
        delivery.fields["customer"] = .string("CUST-1")
        delivery.fields["currency"] = .string("EUR")

        let invoice = HubDocumentConversion.deliveryToInvoice(delivery)
        XCTAssertEqual(invoice.docType, "SalesInvoice")
        XCTAssertEqual(invoice.docStatus, 0)
        XCTAssertEqual(invoice.fields["sales_delivery"], .string("DN-9"))
        XCTAssertEqual(invoice.fields["sales_order"], .string("SO-1"), "Order link threads through")
        XCTAssertEqual(invoice.fields["customer"], .string("CUST-1"))
        let items = invoice.children["items"] ?? []
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].fields["qty"], .double(3))
    }

    // MARK: - DocType wiring

    func test_salesOrder_hasFulfilmentFields_allAllowOnSubmit() {
        guard let so = HubManifest.docType(for: "SalesOrder") else { return XCTFail("SalesOrder missing") }
        let fulfilment = ["delivery_status", "delivered_qty", "per_delivered",
                          "billing_status", "billed_qty", "per_billed"]
        for key in fulfilment {
            guard let field = so.fields.first(where: { $0.key == key }) else {
                return XCTFail("SalesOrder missing fulfilment field \(key)")
            }
            XCTAssertTrue(field.allowOnSubmit, "\(key) must be editable on the submitted order")
        }
    }

    func test_salesInvoice_linksToDelivery() {
        let keys = Set(HubManifest.docType(for: "SalesInvoice")?.fields.map(\.key) ?? [])
        XCTAssertTrue(keys.contains("sales_delivery"))
    }

    func test_company_hasOverDeliveryFlag() {
        let keys = Set(HubManifest.docType(for: "Company")?.fields.map(\.key) ?? [])
        XCTAssertTrue(keys.contains("allow_over_delivery"))
    }

    func test_salesOrdersToDeliver_reportRegistered() {
        XCTAssertNotNil(HubReports.report(forId: "sales-orders-to-deliver"))
    }
}
