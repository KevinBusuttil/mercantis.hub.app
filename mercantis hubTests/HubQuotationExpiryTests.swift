import XCTest
import MercantisCore
@testable import Mercantis_Hub

/// Quotation auto-expiry policy + the DocType / workflow wiring behind it,
/// and the Opportunity link.
final class HubQuotationExpiryTests: XCTestCase {

    private let day: TimeInterval = 86_400

    func test_submitted_pastValidTill_isExpired() {
        let today = Date()
        XCTAssertTrue(QuotationExpiryPolicy.isExpired(
            currentStatus: "Submitted",
            validTill: today.addingTimeInterval(-day),
            today: today))
    }

    func test_submitted_beforeValidTill_isNotExpired() {
        let today = Date()
        XCTAssertFalse(QuotationExpiryPolicy.isExpired(
            currentStatus: "Submitted",
            validTill: today.addingTimeInterval(day),
            today: today))
    }

    func test_noValidTill_neverExpires() {
        XCTAssertFalse(QuotationExpiryPolicy.isExpired(
            currentStatus: "Submitted", validTill: nil, today: Date()))
    }

    func test_nonLiveStates_areNotExpired() {
        let today = Date()
        for state in ["Draft", "Ordered", "Lost", "Expired", "Cancelled"] {
            XCTAssertFalse(QuotationExpiryPolicy.isExpired(
                currentStatus: state,
                validTill: today.addingTimeInterval(-day),
                today: today),
                "\(state) must not auto-expire")
        }
    }

    // MARK: - Wiring

    func test_quotation_hasValidTillAndOpportunityFields() {
        guard let q = HubManifest.docType(for: "Quotation") else { return XCTFail("Quotation missing") }
        let keys = Set(q.fields.map(\.key))
        XCTAssertTrue(keys.contains("valid_till"))
        XCTAssertTrue(keys.contains("opportunity"))
        // valid_till must update on a submitted quote (the sweep / late edits).
        XCTAssertTrue(q.fields.first { $0.key == "valid_till" }?.allowOnSubmit ?? false)
    }

    func test_quotationWorkflow_hasExpiredState() {
        guard let wf = HubWorkflows.workflow(forDocTypeId: "Quotation") else {
            return XCTFail("wf-quotation missing")
        }
        XCTAssertTrue(wf.states.contains { $0.name == "Expired" })
        XCTAssertTrue(wf.transitions.contains { $0.from == "Submitted" && $0.to == "Expired" })
        // A late acceptance can still order an expired quote.
        XCTAssertTrue(wf.transitions.contains { $0.from == "Expired" && $0.to == "Ordered" })
    }
}
