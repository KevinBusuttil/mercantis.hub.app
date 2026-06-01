import XCTest
import MercantisCore
@testable import Mercantis_Hub

@MainActor
final class HubSingleRecordPolicyTests: XCTestCase {

    func test_company_is_single_record() {
        XCTAssertTrue(HubSingleRecordPolicy.isSingleRecord("Company"))
    }

    func test_numbering_series_is_single_record() {
        XCTAssertTrue(HubSingleRecordPolicy.isSingleRecord("NumberingSeries"))
    }

    func test_fiscal_year_is_not_single_record() {
        // Fiscal years allow multiple records (one per period).
        XCTAssertFalse(HubSingleRecordPolicy.isSingleRecord("FiscalYear"))
    }

    func test_normal_doctypes_are_not_single_record() {
        XCTAssertFalse(HubSingleRecordPolicy.isSingleRecord("Customer"))
        XCTAssertFalse(HubSingleRecordPolicy.isSingleRecord("Supplier"))
        XCTAssertFalse(HubSingleRecordPolicy.isSingleRecord("Item"))
        XCTAssertFalse(HubSingleRecordPolicy.isSingleRecord("SalesInvoice"))
        XCTAssertFalse(HubSingleRecordPolicy.isSingleRecord("PurchaseOrder"))
    }

    func test_single_record_copy_uses_setup_action_labels() {
        let companyCopy = HubWorkspaceCopyPolicy.copy(for: Setup.company)
        XCTAssertTrue(companyCopy.primaryActionTitle.hasPrefix("Set Up"),
                      "Single-record DocTypes should use 'Set Up' action label")

        let numberingCopy = HubWorkspaceCopyPolicy.copy(for: Setup.numberingSeries)
        XCTAssertTrue(numberingCopy.primaryActionTitle.hasPrefix("Set Up"),
                      "Single-record DocTypes should use 'Set Up' action label")
    }

    func test_multi_record_copy_uses_new_action_labels() {
        let customerCopy = HubWorkspaceCopyPolicy.copy(for: CRM.customer)
        XCTAssertTrue(customerCopy.primaryActionTitle.hasPrefix("New"),
                      "Multi-record DocTypes should use 'New' action label")

        let supplierCopy = HubWorkspaceCopyPolicy.copy(for: Buying.supplier)
        XCTAssertTrue(supplierCopy.primaryActionTitle.hasPrefix("New"),
                      "Multi-record DocTypes should use 'New' action label")
    }
}
