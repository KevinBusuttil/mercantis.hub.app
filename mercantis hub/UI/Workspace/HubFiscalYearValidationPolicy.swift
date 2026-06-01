import Foundation
import MercantisCore

enum HubFiscalYearValidationPolicy {

    static func validate(_ document: Document, existingDocuments: [Document]) throws {
        guard document.docType == "FiscalYear" else { return }

        guard let startDate = dateValue(document.fields["year_start_date"]) else {
            throw HubFiscalYearValidationError.missingStartDate
        }
        guard let endDate = dateValue(document.fields["year_end_date"]) else {
            throw HubFiscalYearValidationError.missingEndDate
        }
        guard startDate <= endDate else {
            throw HubFiscalYearValidationError.endDateBeforeStartDate
        }

        let isActive = boolValue(document.fields["is_active"])
        let isClosed = boolValue(document.fields["is_closed"])
        if isActive && isClosed {
            throw HubFiscalYearValidationError.activeYearCannotBeClosed
        }

        for existing in existingDocuments where existing.id != document.id {
            if isActive && boolValue(existing.fields["is_active"]) {
                throw HubFiscalYearValidationError.multipleActiveYears(existingYearName: yearName(for: existing))
            }

            guard let existingStart = dateValue(existing.fields["year_start_date"]),
                  let existingEnd = dateValue(existing.fields["year_end_date"]) else {
                continue
            }

            if startDate <= existingEnd && existingStart <= endDate {
                throw HubFiscalYearValidationError.overlappingPeriods(existingYearName: yearName(for: existing))
            }
        }
    }

    private static func dateValue(_ raw: FieldValue?) -> Date? {
        switch raw {
        case .date(let value), .dateTime(let value):
            return value
        default:
            return nil
        }
    }

    private static func boolValue(_ raw: FieldValue?) -> Bool {
        guard case .bool(let value) = raw else { return false }
        return value
    }

    private static func yearName(for document: Document) -> String {
        guard case .string(let value)? = document.fields["year_name"] else {
            return document.id.isEmpty ? "another fiscal year" : document.id
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "another fiscal year" : trimmed
    }
}

enum HubFiscalYearValidationError: LocalizedError {
    case missingStartDate
    case missingEndDate
    case endDateBeforeStartDate
    case activeYearCannotBeClosed
    case multipleActiveYears(existingYearName: String)
    case overlappingPeriods(existingYearName: String)

    var errorDescription: String? {
        switch self {
        case .missingStartDate:
            return "Fiscal Year requires a start date."
        case .missingEndDate:
            return "Fiscal Year requires an end date."
        case .endDateBeforeStartDate:
            return "Fiscal Year end date must be on or after the start date."
        case .activeYearCannotBeClosed:
            return "An active fiscal year cannot also be marked closed."
        case .multipleActiveYears(let existingYearName):
            return "Only one fiscal year can be active at a time. '\(existingYearName)' is already active."
        case .overlappingPeriods(let existingYearName):
            return "Fiscal Year dates cannot overlap with '\(existingYearName)'."
        }
    }
}
