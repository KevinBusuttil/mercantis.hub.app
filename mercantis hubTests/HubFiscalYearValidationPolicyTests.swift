import XCTest
import MercantisCore
@testable import Mercantis_Hub

@MainActor
final class HubFiscalYearValidationPolicyTests: XCTestCase {

    func test_fiscal_year_doctype_exposes_active_flag() {
        let fieldKeys = Set(Setup.fiscalYear.fields.map(\.key))

        XCTAssertTrue(fieldKeys.contains("is_active"))
        XCTAssertTrue(Setup.fiscalYear.formLayout?.sections.first?.fieldKeys.contains("is_active") == true)
    }

    func test_validation_rejects_end_date_before_start_date() {
        let document = fiscalYear(
            id: "FY26",
            name: "FY 2026",
            start: date(year: 2026, month: 12, day: 31),
            end: date(year: 2026, month: 1, day: 1)
        )

        XCTAssertThrowsError(try HubFiscalYearValidationPolicy.validate(document, existingDocuments: [])) { error in
            XCTAssertEqual(error.localizedDescription, "Fiscal Year end date must be on or after the start date.")
        }
    }

    func test_validation_rejects_multiple_active_years() {
        let existing = fiscalYear(
            id: "FY25",
            name: "FY 2025",
            start: date(year: 2025, month: 1, day: 1),
            end: date(year: 2025, month: 12, day: 31),
            isActive: true
        )
        let candidate = fiscalYear(
            id: "FY26",
            name: "FY 2026",
            start: date(year: 2026, month: 1, day: 1),
            end: date(year: 2026, month: 12, day: 31),
            isActive: true
        )

        XCTAssertThrowsError(try HubFiscalYearValidationPolicy.validate(candidate, existingDocuments: [existing])) { error in
            XCTAssertEqual(error.localizedDescription, "Only one fiscal year can be active at a time. 'FY 2025' is already active.")
        }
    }

    func test_validation_rejects_overlapping_periods() {
        let existing = fiscalYear(
            id: "FY25",
            name: "FY 2025",
            start: date(year: 2025, month: 1, day: 1),
            end: date(year: 2025, month: 12, day: 31)
        )
        let candidate = fiscalYear(
            id: "FY25-Overlap",
            name: "FY 2025 Extended",
            start: date(year: 2025, month: 6, day: 1),
            end: date(year: 2026, month: 5, day: 31)
        )

        XCTAssertThrowsError(try HubFiscalYearValidationPolicy.validate(candidate, existingDocuments: [existing])) { error in
            XCTAssertEqual(error.localizedDescription, "Fiscal Year dates cannot overlap with 'FY 2025'.")
        }
    }

    func test_validation_rejects_closed_active_year() {
        let document = fiscalYear(
            id: "FY26",
            name: "FY 2026",
            start: date(year: 2026, month: 1, day: 1),
            end: date(year: 2026, month: 12, day: 31),
            isActive: true,
            isClosed: true
        )

        XCTAssertThrowsError(try HubFiscalYearValidationPolicy.validate(document, existingDocuments: [])) { error in
            XCTAssertEqual(error.localizedDescription, "An active fiscal year cannot also be marked closed.")
        }
    }

    func test_validation_allows_non_overlapping_inactive_year() throws {
        let existing = fiscalYear(
            id: "FY25",
            name: "FY 2025",
            start: date(year: 2025, month: 1, day: 1),
            end: date(year: 2025, month: 12, day: 31),
            isActive: true
        )
        let candidate = fiscalYear(
            id: "FY26",
            name: "FY 2026",
            start: date(year: 2026, month: 1, day: 1),
            end: date(year: 2026, month: 12, day: 31),
            isActive: false
        )

        XCTAssertNoThrow(try HubFiscalYearValidationPolicy.validate(candidate, existingDocuments: [existing]))
    }

    private func fiscalYear(id: String, name: String, start: Date, end: Date,
                            isActive: Bool = false, isClosed: Bool = false) -> Document {
        Document(
            id: id,
            docType: "FiscalYear",
            company: "",
            status: "",
            createdAt: start,
            updatedAt: start,
            syncVersion: 0,
            syncState: .local,
            fields: [
                "year_name": .string(name),
                "year_start_date": .date(start),
                "year_end_date": .date(end),
                "is_active": .bool(isActive),
                "is_closed": .bool(isClosed)
            ],
            children: [:]
        )
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }
}
