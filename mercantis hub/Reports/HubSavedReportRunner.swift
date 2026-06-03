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
            let raw = try savedReportEngine.execute(
                savedReport: savedReport,
                requestingUserId: requestingUserId,
                userRoles: userRoles
            )
            // The generic engine emits raw field values (link ids, plain
            // numbers, ISO dates). Resolve those to friendly, ERP-aware
            // display strings before showing them.
            return humanize(raw, savedReport: savedReport, engine: engine)
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

    // MARK: - Display humanizing (from-scratch reports)

    private enum CellTransform {
        case none
        case link([String: String])   // id → display name
        case number
        case date
    }

    /// Turn a from-scratch report's raw cell values into friendly display
    /// strings: link ids → record names, numbers → grouped, ISO dates →
    /// medium style. Each column's treatment is decided from DocType metadata,
    /// so only the right columns are reformatted (e.g. a phone-number text
    /// field is never grouped like a quantity).
    static func humanize(
        _ result: ReportResult,
        savedReport: SavedReportDefinition,
        engine: DocumentEngine
    ) -> ReportResult {
        guard let docType = HubManifest.docType(for: savedReport.sourceDocType) else {
            return result
        }
        let visible = savedReport.visibleColumnsInOrder
        // The generic engine outputs exactly the visible columns, in order.
        guard visible.count == result.columns.count else { return result }

        var transforms: [CellTransform] = []
        var linkMaps: [String: [String: String]] = [:]

        for column in visible {
            switch column.fieldKey {
            case "createdAt", "updatedAt":
                transforms.append(.date)
            case "id", "status", "company", "doctype":
                transforms.append(.none)
            default:
                guard let field = docType.fields.first(where: { $0.key == column.fieldKey }) else {
                    transforms.append(.none)
                    continue
                }
                switch field.type {
                case .link:
                    if let target = field.linkedDocType {
                        if linkMaps[target] == nil {
                            linkMaps[target] = displayNameMap(forDocType: target, engine: engine)
                        }
                        transforms.append(.link(linkMaps[target] ?? [:]))
                    } else {
                        transforms.append(.none)
                    }
                case .number, .decimal, .currency:
                    transforms.append(.number)
                case .date, .datetime:
                    transforms.append(.date)
                default:
                    transforms.append(.none)
                }
            }
        }

        let rows: [[String?]] = result.rows.map { row in
            row.enumerated().map { index, cell -> String? in
                guard let cell, index < transforms.count else { return cell }
                switch transforms[index] {
                case .none:            return cell
                case .link(let map):   return map[cell] ?? cell
                case .number:          return formatNumber(cell)
                case .date:            return formatDate(cell)
                }
            }
        }
        return ReportResult(columns: result.columns, rows: rows)
    }

    /// id → title-field display value for every document of `docType`.
    private static func displayNameMap(forDocType docType: String, engine: DocumentEngine) -> [String: String] {
        guard let meta = HubManifest.docType(for: docType),
              let documents = try? engine.list(docType: docType) else {
            return [:]
        }
        var map: [String: String] = [:]
        for doc in documents {
            if case .string(let name)? = doc.fields[meta.titleField],
               !name.trimmingCharacters(in: .whitespaces).isEmpty {
                map[doc.id] = name
            } else {
                map[doc.id] = doc.id
            }
        }
        return map
    }

    private static func formatNumber(_ raw: String) -> String {
        guard let value = Double(raw) else { return raw }
        return numberFormatter.string(from: NSNumber(value: value)) ?? raw
    }

    private static func formatDate(_ raw: String) -> String {
        if let date = isoDate.date(from: raw) ?? isoDateTime.date(from: raw) {
            return mediumDate.string(from: date)
        }
        return raw
    }

    private static let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return f
    }()

    private static let isoDate: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()

    private static let isoDateTime: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let mediumDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}
