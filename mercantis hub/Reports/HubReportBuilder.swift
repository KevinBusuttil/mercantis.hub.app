import Foundation
import MercantisCore

/// Builds a blank, from-scratch `SavedReportDefinition` for a chosen DocType,
/// seeding its columns from the DocType's metadata so the editor can offer
/// show/hide, reorder, relabel, filters and sorting over real fields.
///
/// A from-scratch report has `baseReportId == nil`; the runner executes it
/// through Core's `SavedReportEngine` (flat field output, field allow-listed
/// against metadata, no SQL/script), not the Hub report computer.
enum HubReportBuilder {

    /// System columns offered alongside a DocType's own fields. These are part
    /// of Core's `SavedReportEngine.systemFieldKeys` allow-list.
    static let systemColumns: [(key: String, label: String)] = [
        ("id", "ID"),
        ("status", "Status"),
        ("createdAt", "Created"),
        ("updatedAt", "Updated"),
    ]

    /// Field types that make sense as a flat report column. Child tables are
    /// excluded (they aren't a single cell value).
    static func isReportableColumnType(_ type: FieldType) -> Bool {
        type != .table
    }

    /// Field types that can be filtered on with the safe operator set.
    static func isFilterableType(_ type: FieldType) -> Bool {
        switch type {
        case .text, .longText, .richText, .email, .phone, .select, .multiselect,
             .status, .barcode, .formula, .link,
             .number, .decimal, .currency, .boolean:
            return true
        case .date, .datetime, .table, .attachment, .image:
            return false
        }
    }

    /// The ordered (key, label) columns a report on `docType` may show:
    /// `id`, then each non-table field in declared order, then the remaining
    /// system columns.
    static func availableColumns(of docType: DocType) -> [(key: String, label: String)] {
        var columns: [(key: String, label: String)] = [("id", "ID")]
        for field in docType.fields where isReportableColumnType(field.type) {
            columns.append((field.key, field.label))
        }
        for system in systemColumns where system.key != "id" {
            columns.append((system.key, system.label))
        }
        return columns
    }

    /// Build a blank saved report for `docType`: every available column present,
    /// the first few visible (so the report isn't empty or overwhelming), no
    /// filters or sorts yet.
    static func makeBlankReport(
        docType: DocType,
        ownerUserId: String,
        name: String? = nil,
        now: Date = Date(),
        defaultVisibleCount: Int = 6
    ) -> SavedReportDefinition {
        let available = availableColumns(of: docType)
        let columns = available.enumerated().map { index, column in
            SavedReportColumn(
                fieldKey: column.key,
                labelOverride: column.label,
                visible: index < defaultVisibleCount,
                order: index
            )
        }
        return SavedReportDefinition(
            name: name ?? "New \(docType.name) Report",
            baseReportId: nil,
            sourceDocType: docType.id,
            ownerUserId: ownerUserId,
            visibility: .private,
            columns: columns,
            filters: [],
            sorts: [],
            createdAt: now,
            updatedAt: now
        )
    }
}
