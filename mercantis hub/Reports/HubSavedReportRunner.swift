import Foundation
import MercantisCore

/// Runs a user's `SavedReportDefinition` against Hub's report computer.
///
/// Hub reports are not all flat field dumps — several (Customer Aging, VAT
/// Summary, Supplier Ledger) need Hub-side aggregation that Core's generic
/// `SavedReportEngine` can't reproduce. So rather than re-query the DocType,
/// the runner re-runs the *base* Hub report (`HubReports.runResult`) to get a
/// fully-computed `ReportResult`, then projects the saved report's column
/// selection / order / labels and filter defaults on top of it.
///
/// This keeps all ERP computation in Hub while reusing Core's generic
/// saved-report model — Hub does not reimplement the model or a second
/// execution engine.
enum HubSavedReportRunner {

    enum RunError: Error, LocalizedError, Equatable {
        case unknownBaseReport(String?)
        case noEngineForCustomReport

        var errorDescription: String? {
            switch self {
            case .unknownBaseReport(let id):
                return "This custom report points at a built-in report (\(id ?? "—")) that no longer exists."
            case .noEngineForCustomReport:
                return "This from-scratch report can't be run because the report engine is unavailable."
            }
        }
    }

    /// Execute the saved report and return its `ReportResult`.
    ///
    /// Two paths:
    /// - **Customised built-in** (`baseReportId != nil`): re-run the Hub report
    ///   computer and project the saved columns/filters onto its result.
    /// - **From-scratch** (`baseReportId == nil`): run directly through Core's
    ///   generic `SavedReportEngine`, which validates fields against DocType
    ///   metadata and enforces row permissions.
    static func run(
        savedReport: SavedReportDefinition,
        engine: DocumentEngine,
        savedReportEngine: SavedReportEngine? = nil,
        requestingUserId: String? = nil,
        userRoles: Set<String> = []
    ) throws -> ReportResult {
        if savedReport.baseReportId == nil {
            guard let savedReportEngine else { throw RunError.noEngineForCustomReport }
            return try savedReportEngine.execute(
                savedReport: savedReport,
                requestingUserId: requestingUserId,
                userRoles: userRoles
            )
        }

        guard let baseId = savedReport.baseReportId,
              HubReports.report(forId: baseId) != nil else {
            throw RunError.unknownBaseReport(savedReport.baseReportId)
        }

        let base = try HubReports.runResult(
            reportId: baseId,
            engine: engine,
            filters: filterValues(for: savedReport)
        ) ?? ReportResult(columns: [], rows: [])

        return project(base: base, savedReport: savedReport)
    }

    // MARK: - Filter defaults

    /// Collapse the saved report's stored filters into the `[fieldKey: value]`
    /// dictionary `HubReports.runResult` expects. A filter contributes its
    /// stored `value`, falling back to its `defaultValue`; filters with
    /// neither are omitted so the base report runs unfiltered on that field.
    static func filterValues(for savedReport: SavedReportDefinition) -> [String: FieldValue] {
        var values: [String: FieldValue] = [:]
        for filter in savedReport.filters {
            guard let value = filter.value ?? filter.defaultValue else { continue }
            if case .null = value { continue }
            values[filter.fieldKey] = value
        }
        return values
    }

    // MARK: - Column projection

    /// Re-shape a computed `ReportResult` to the saved report's visible
    /// columns, in order, using the saved labels as headers. Columns whose
    /// `fieldKey` isn't present in the base result render as empty cells so a
    /// stale saved report degrades gracefully rather than crashing.
    static func project(base: ReportResult, savedReport: SavedReportDefinition) -> ReportResult {
        let visible = savedReport.visibleColumnsInOrder
        // Fall back to the base result untouched if the saved report somehow
        // has no visible columns (shouldn't happen via the catalogue).
        guard !visible.isEmpty else { return base }

        let indexByName: [String: Int] = Dictionary(
            base.columns.enumerated().map { ($1, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let columns = visible.map(\.resolvedLabel)
        let rows: [[String?]] = base.rows.map { row in
            visible.map { column -> String? in
                guard let index = indexByName[column.fieldKey], index < row.count else {
                    return nil
                }
                return row[index]
            }
        }
        return ReportResult(columns: columns, rows: rows)
    }
}
