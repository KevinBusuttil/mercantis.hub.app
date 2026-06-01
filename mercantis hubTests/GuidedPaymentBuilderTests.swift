import XCTest
import MercantisCore
@testable import Mercantis_Hub

final class GuidedPaymentBuilderTests: XCTestCase {

    private func day(_ d: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(d) * 86_400)
    }

    private func invoice(
        id: String,
        docType: String = "SalesInvoice",
        grand: Double,
        outstanding: Double?,
        docStatus: Int = 1,
        date: Int = 1,
        currency: String = "EUR"
    ) -> Document {
        var fields: [String: FieldValue] = [
            "grand_total": .double(grand),
            "currency": .string(currency),
            "transaction_date": .date(day(date)),
        ]
        if let outstanding { fields["outstanding_amount"] = .double(outstanding) }
        return Document(
            id: id, docType: docType, company: "Acme", status: "Submitted",
            createdAt: Date(), updatedAt: Date(), syncVersion: 0, syncState: .local,
            docStatus: docStatus, fields: fields, children: [:]
        )
    }

    // MARK: - Outstanding selection

    func test_outstanding_excludes_drafts_and_settled_invoices() {
        let invoices = [
            invoice(id: "SINV-1", grand: 100, outstanding: 100, docStatus: 1, date: 3),
            invoice(id: "SINV-2", grand: 50,  outstanding: 0,   docStatus: 1, date: 2), // settled
            invoice(id: "SINV-3", grand: 80,  outstanding: 80,  docStatus: 0, date: 1), // draft
        ]
        let result = GuidedPaymentBuilder.outstanding(from: invoices, mode: .receive)
        XCTAssertEqual(result.map(\.id), ["SINV-1"])
    }

    func test_outstanding_falls_back_to_grand_total_when_unstamped() {
        let invoices = [invoice(id: "SINV-9", grand: 120, outstanding: nil, docStatus: 1)]
        let result = GuidedPaymentBuilder.outstanding(from: invoices, mode: .receive)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].outstanding, 120, accuracy: 0.0001)
    }

    func test_outstanding_sorted_oldest_first() {
        let invoices = [
            invoice(id: "B", grand: 10, outstanding: 10, date: 5),
            invoice(id: "A", grand: 10, outstanding: 10, date: 2),
            invoice(id: "C", grand: 10, outstanding: 10, date: 9),
        ]
        let result = GuidedPaymentBuilder.outstanding(from: invoices, mode: .receive)
        XCTAssertEqual(result.map(\.id), ["A", "B", "C"])
    }

    // MARK: - Payment Entry construction

    func test_receive_payment_posts_to_bank_and_receivable() {
        let allocations = [
            GuidedPaymentBuilder.Allocation(invoiceId: "SINV-1", invoiceDocType: "SalesInvoice",
                                            total: 100, outstanding: 100, allocated: 60),
            GuidedPaymentBuilder.Allocation(invoiceId: "SINV-2", invoiceDocType: "SalesInvoice",
                                            total: 40, outstanding: 40, allocated: 40),
        ]
        let payment = GuidedPaymentBuilder.buildPaymentEntry(
            mode: .receive, party: "CUST-1", postingDate: day(10), currency: "EUR",
            bankAccount: "Cash - HUB", partyAccount: "Debtors - HUB",
            allocations: allocations
        )

        XCTAssertEqual(payment.docType, "PaymentEntry")
        XCTAssertEqual(stringValue(payment.fields["payment_type"]), "Receive")
        XCTAssertEqual(stringValue(payment.fields["party_type"]), "Customer")
        XCTAssertEqual(stringValue(payment.fields["party"]), "CUST-1")
        // Receive: receivable is credited (paid_from), bank is debited (paid_to).
        XCTAssertEqual(stringValue(payment.fields["paid_from"]), "Debtors - HUB")
        XCTAssertEqual(stringValue(payment.fields["paid_to"]), "Cash - HUB")
        XCTAssertEqual(doubleValue(payment.fields["paid_amount"]), 100, accuracy: 0.0001)
        XCTAssertEqual(doubleValue(payment.fields["received_amount"]), 100, accuracy: 0.0001)

        let refs = payment.children["references"] ?? []
        XCTAssertEqual(refs.count, 2)
        XCTAssertEqual(stringValue(refs[0].fields["reference_doctype"]), "SalesInvoice")
        XCTAssertEqual(stringValue(refs[0].fields["reference_name"]), "SINV-1")
        XCTAssertEqual(doubleValue(refs[0].fields["allocated_amount"]), 60, accuracy: 0.0001)
    }

    func test_pay_supplier_posts_from_bank_to_payable() {
        let payment = GuidedPaymentBuilder.buildPaymentEntry(
            mode: .pay, party: "SUPP-1", postingDate: day(10), currency: "EUR",
            bankAccount: "Cash - HUB", partyAccount: "Creditors - HUB",
            allocations: [
                GuidedPaymentBuilder.Allocation(invoiceId: "PINV-1", invoiceDocType: "PurchaseInvoice",
                                                total: 200, outstanding: 200, allocated: 200),
            ]
        )
        XCTAssertEqual(stringValue(payment.fields["payment_type"]), "Pay")
        XCTAssertEqual(stringValue(payment.fields["party_type"]), "Supplier")
        // Pay: bank is credited (paid_from), payable is debited (paid_to).
        XCTAssertEqual(stringValue(payment.fields["paid_from"]), "Cash - HUB")
        XCTAssertEqual(stringValue(payment.fields["paid_to"]), "Creditors - HUB")
        XCTAssertEqual(doubleValue(payment.fields["paid_amount"]), 200, accuracy: 0.0001)
    }

    func test_total_allocated_rounds_to_currency() {
        let allocations = [
            GuidedPaymentBuilder.Allocation(invoiceId: "A", invoiceDocType: "SalesInvoice",
                                            total: 0, outstanding: 0, allocated: 33.333),
            GuidedPaymentBuilder.Allocation(invoiceId: "B", invoiceDocType: "SalesInvoice",
                                            total: 0, outstanding: 0, allocated: 33.333),
        ]
        XCTAssertEqual(GuidedPaymentBuilder.totalAllocated(allocations), 66.67, accuracy: 0.0001)
    }

    func test_payment_entry_starts_as_draft_for_normal_submit_flow() {
        let payment = GuidedPaymentBuilder.buildPaymentEntry(
            mode: .receive, party: "CUST-1", postingDate: day(1), currency: nil,
            bankAccount: "Cash", partyAccount: "Debtors",
            allocations: [GuidedPaymentBuilder.Allocation(invoiceId: "SINV-1",
                          invoiceDocType: "SalesInvoice", total: 10, outstanding: 10, allocated: 10)]
        )
        XCTAssertTrue(payment.id.isEmpty, "New payment must be unsaved so the engine names it")
        XCTAssertEqual(payment.status, "Draft")
        XCTAssertNil(payment.fields["currency"], "Currency omitted when unknown")
    }

    // MARK: - Navigation wiring

    func test_guided_payment_flows_are_in_navigation() {
        let flowIDs = HubNavigation.allModules
            .flatMap { $0.groups }
            .flatMap { $0.items }
            .compactMap { item -> String? in
                if case .flow(let id, _, _) = item { return id }
                return nil
            }
        XCTAssertTrue(flowIDs.contains("guided-receive-payment"))
        XCTAssertTrue(flowIDs.contains("guided-pay-supplier"))
    }

    // MARK: - Helpers

    private func stringValue(_ v: FieldValue?) -> String? {
        if case .string(let s) = v { return s }
        return nil
    }

    private func doubleValue(_ v: FieldValue?) -> Double {
        switch v {
        case .double(let d): return d
        case .int(let i):    return Double(i)
        default:             return .nan
        }
    }
}
