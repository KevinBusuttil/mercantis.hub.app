import Foundation
import XCTest
import MercantisCore
@testable import Mercantis_Hub

@MainActor
final class HubBusinessProfileDefaultsPolicyTests: XCTestCase {

    func test_draft_defaults_prefill_sales_and_purchase_documents() {
        let businessProfile = makeBusinessProfile()

        let salesOrder = HubBusinessProfileDefaultsPolicy.applyDraftDefaults(
            to: makeDocument(docType: "SalesOrder"),
            docType: Selling.salesOrder,
            businessProfile: businessProfile
        )
        XCTAssertEqual(stringValue(salesOrder.fields["currency"]), "EUR")

        let salesInvoice = HubBusinessProfileDefaultsPolicy.applyDraftDefaults(
            to: makeDocument(docType: "SalesInvoice"),
            docType: Selling.salesInvoice,
            businessProfile: businessProfile
        )
        XCTAssertEqual(stringValue(salesInvoice.fields["currency"]), "EUR")
        XCTAssertEqual(stringValue(salesInvoice.fields["debit_to"]), "Debtors - HUB")
        XCTAssertEqual(stringValue(salesInvoice.fields["income_account"]), "Sales - HUB")

        let purchaseOrder = HubBusinessProfileDefaultsPolicy.applyDraftDefaults(
            to: makeDocument(docType: "PurchaseOrder"),
            docType: Buying.purchaseOrder,
            businessProfile: businessProfile
        )
        XCTAssertEqual(stringValue(purchaseOrder.fields["currency"]), "EUR")

        let purchaseInvoice = HubBusinessProfileDefaultsPolicy.applyDraftDefaults(
            to: makeDocument(docType: "PurchaseInvoice"),
            docType: Buying.purchaseInvoice,
            businessProfile: businessProfile
        )
        XCTAssertEqual(stringValue(purchaseInvoice.fields["currency"]), "EUR")
        XCTAssertEqual(stringValue(purchaseInvoice.fields["credit_to"]), "Creditors - HUB")
        XCTAssertEqual(stringValue(purchaseInvoice.fields["expense_account"]), "COGS - HUB")
    }

    func test_draft_defaults_fill_existing_item_rows_and_prefilled_payment_accounts() {
        let businessProfile = makeBusinessProfile()

        let salesOrder = HubBusinessProfileDefaultsPolicy.applyDraftDefaults(
            to: makeDocument(
                docType: "SalesOrder",
                children: [
                    "items": [
                        makeChild(docType: "SalesItem", fields: ["item": .string("ITEM-001")]),
                        makeChild(docType: "SalesItem", fields: ["item": .string("ITEM-002"), "warehouse": .string("Row Warehouse")])
                    ]
                ]
            ),
            docType: Selling.salesOrder,
            businessProfile: businessProfile
        )
        let salesItems = salesOrder.children["items"] ?? []
        XCTAssertEqual(stringValue(salesItems.first.flatMap { $0.fields["warehouse"] }), "Main Warehouse")
        XCTAssertEqual(stringValue(salesItems.last.flatMap { $0.fields["warehouse"] }), "Row Warehouse")

        let receivePayment = HubBusinessProfileDefaultsPolicy.applyDraftDefaults(
            to: makeDocument(docType: "PaymentEntry", fields: ["payment_type": .string("Receive")]),
            docType: Accounting.paymentEntry,
            businessProfile: businessProfile
        )
        XCTAssertEqual(stringValue(receivePayment.fields["paid_from"]), "Debtors - HUB")
        XCTAssertEqual(stringValue(receivePayment.fields["paid_to"]), "Bank - HUB")

        let payPayment = HubBusinessProfileDefaultsPolicy.applyDraftDefaults(
            to: makeDocument(docType: "PaymentEntry", fields: ["payment_type": .string("Pay")]),
            docType: Accounting.paymentEntry,
            businessProfile: businessProfile
        )
        XCTAssertEqual(stringValue(payPayment.fields["paid_from"]), "Bank - HUB")
        XCTAssertEqual(stringValue(payPayment.fields["paid_to"]), "Creditors - HUB")

        let internalTransfer = HubBusinessProfileDefaultsPolicy.applyDraftDefaults(
            to: makeDocument(docType: "PaymentEntry", fields: ["payment_type": .string("Internal Transfer")]),
            docType: Accounting.paymentEntry,
            businessProfile: businessProfile
        )
        XCTAssertNil(internalTransfer.fields["paid_from"])
        XCTAssertNil(internalTransfer.fields["paid_to"])
    }

    func test_first_save_defaults_fill_item_warehouses_and_payment_accounts() {
        let businessProfile = makeBusinessProfile()

        let salesInvoice = HubBusinessProfileDefaultsPolicy.prepareForFirstSave(
            makeDocument(
                docType: "SalesInvoice",
                children: [
                    "items": [
                        makeChild(docType: "SalesItem", fields: ["item": .string("ITEM-001")]),
                        makeChild(docType: "SalesItem", fields: ["item": .string("ITEM-002"), "warehouse": .string("Row Warehouse")])
                    ]
                ]
            ),
            docType: Selling.salesInvoice,
            businessProfile: businessProfile
        )

        let salesItems = salesInvoice.children["items"] ?? []
        XCTAssertEqual(stringValue(salesItems.first.flatMap { $0.fields["warehouse"] }), "Main Warehouse")
        XCTAssertEqual(stringValue(salesItems.last.flatMap { $0.fields["warehouse"] }), "Row Warehouse")

        let receivePayment = HubBusinessProfileDefaultsPolicy.prepareForFirstSave(
            makeDocument(docType: "PaymentEntry", fields: ["payment_type": .string("Receive")]),
            docType: Accounting.paymentEntry,
            businessProfile: businessProfile
        )
        XCTAssertEqual(stringValue(receivePayment.fields["paid_from"]), "Debtors - HUB")
        XCTAssertEqual(stringValue(receivePayment.fields["paid_to"]), "Bank - HUB")

        let payPayment = HubBusinessProfileDefaultsPolicy.prepareForFirstSave(
            makeDocument(docType: "PaymentEntry", fields: ["payment_type": .string("Pay")]),
            docType: Accounting.paymentEntry,
            businessProfile: businessProfile
        )
        XCTAssertEqual(stringValue(payPayment.fields["paid_from"]), "Bank - HUB")
        XCTAssertEqual(stringValue(payPayment.fields["paid_to"]), "Creditors - HUB")
    }

    func test_existing_values_are_not_overwritten() {
        let businessProfile = makeBusinessProfile()

        let draft = makeDocument(
            docType: "SalesInvoice",
            fields: [
                "currency": .string("USD"),
                "debit_to": .string("Custom Receivable"),
                "income_account": .string("Custom Income")
            ]
        )

        let prepared = HubBusinessProfileDefaultsPolicy.prepareForFirstSave(
            draft,
            docType: Selling.salesInvoice,
            businessProfile: businessProfile
        )

        XCTAssertEqual(stringValue(prepared.fields["currency"]), "USD")
        XCTAssertEqual(stringValue(prepared.fields["debit_to"]), "Custom Receivable")
        XCTAssertEqual(stringValue(prepared.fields["income_account"]), "Custom Income")
    }

    private func makeBusinessProfile() -> Document {
        makeDocument(
            id: "COMPANY-001",
            docType: "Company",
            fields: [
                "default_currency": .string("EUR"),
                "default_warehouse": .string("Main Warehouse"),
                "default_receivable_account": .string("Debtors - HUB"),
                "default_payable_account": .string("Creditors - HUB"),
                "default_income_account": .string("Sales - HUB"),
                "default_expense_account": .string("COGS - HUB"),
                "default_cash_bank_account": .string("Bank - HUB")
            ]
        )
    }

    private func makeDocument(
        id: String = "",
        docType: String,
        fields: [String: FieldValue] = [:],
        children: [String: [Document]] = [:]
    ) -> Document {
        let now = Date()
        return Document(
            id: id,
            docType: docType,
            company: "",
            status: "",
            createdAt: now,
            updatedAt: now,
            syncVersion: 0,
            syncState: .local,
            fields: fields,
            children: children
        )
    }

    private func makeChild(docType: String, fields: [String: FieldValue]) -> Document {
        makeDocument(id: UUID().uuidString, docType: docType, fields: fields)
    }

    private func stringValue(_ value: FieldValue?) -> String? {
        guard case .string(let text)? = value else { return nil }
        return text
    }
}
