import XCTest
import MercantisCore
@testable import Mercantis_Hub

/// Auto Paid / Overdue status policy for Sales & Purchase Invoices.
final class HubInvoiceStatusTests: XCTestCase {

    private let day: TimeInterval = 86_400
    private func date(_ offsetDays: Double, from base: Date) -> Date {
        base.addingTimeInterval(offsetDays * day)
    }

    func test_fullyPaid_becomesPaid() {
        let today = Date()
        XCTAssertEqual(
            InvoiceStatusPolicy.resolved(currentStatus: "Submitted", outstanding: 0,
                                         dueDate: date(5, from: today), today: today),
            "Paid")
    }

    func test_pastDue_andOwing_becomesOverdue() {
        let today = Date()
        XCTAssertEqual(
            InvoiceStatusPolicy.resolved(currentStatus: "Submitted", outstanding: 100,
                                         dueDate: date(-1, from: today), today: today),
            "Overdue")
    }

    func test_notDue_andOwing_staysSubmitted_returnsNil() {
        let today = Date()
        XCTAssertNil(
            InvoiceStatusPolicy.resolved(currentStatus: "Submitted", outstanding: 100,
                                         dueDate: date(5, from: today), today: today))
    }

    func test_overdue_thatGetsPaid_becomesPaid() {
        let today = Date()
        XCTAssertEqual(
            InvoiceStatusPolicy.resolved(currentStatus: "Overdue", outstanding: 0,
                                         dueDate: date(-10, from: today), today: today),
            "Paid")
    }

    func test_paid_thatGetsReopened_movesBack() {
        let today = Date()
        // Payment cancelled → balance owing again, not yet due → back to Submitted.
        XCTAssertEqual(
            InvoiceStatusPolicy.resolved(currentStatus: "Paid", outstanding: 50,
                                         dueDate: date(5, from: today), today: today),
            "Submitted")
        // ...or Overdue if it's already past due.
        XCTAssertEqual(
            InvoiceStatusPolicy.resolved(currentStatus: "Paid", outstanding: 50,
                                         dueDate: date(-5, from: today), today: today),
            "Overdue")
    }

    func test_noDueDate_owing_staysSubmitted() {
        XCTAssertNil(
            InvoiceStatusPolicy.resolved(currentStatus: "Submitted", outstanding: 100,
                                         dueDate: nil, today: Date()))
    }

    func test_unmanagedStates_areLeftAlone() {
        let today = Date()
        for state in ["Draft", "Cancelled", "Submitted-ish"] {
            XCTAssertNil(
                InvoiceStatusPolicy.resolved(currentStatus: state, outstanding: 0,
                                             dueDate: date(-1, from: today), today: today),
                "\(state) must not be auto-managed")
        }
    }

    func test_alreadyCorrect_returnsNil() {
        let today = Date()
        XCTAssertNil(
            InvoiceStatusPolicy.resolved(currentStatus: "Overdue", outstanding: 100,
                                         dueDate: date(-3, from: today), today: today),
            "Already Overdue and still past-due → no change")
    }
}
