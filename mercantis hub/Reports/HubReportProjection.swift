import Foundation
import MercantisCore

/// Turns a from-scratch report's raw typed rows (`SavedReportEngine.TypedReportResult`)
/// into a friendly, display-ready table — resolving link ids to names and
/// numbers/dates to readable strings, then applying the saved report's grouping
/// (group header + per-group subtotals) and a grand total. Also derives the
/// chart series. Grouping / chart fields are constrained by the builder to the
/// report's own visible columns, so every value needed is already in the rows.
enum HubReportProjection {

    struct Table {
        let columnLabels: [String]
        let rows: [DisplayRow]
    }

    struct DisplayRow: Identifiable {
        enum Kind { case data, groupHeader, subtotal, grandTotal }
        let id: String
        let kind: Kind
        /// One entry per column (nil = blank). For `groupHeader`, the first
        /// non-nil cell carries the group title.
        let cells: [String?]
    }

    struct ChartPoint: Identifiable {
        let id: String
        let category: String
        let value: Double
    }

    // MARK: - Table

    static func build(
        definition: SavedReportDefinition,
        typed: SavedReportEngine.TypedReportResult,
        engine: DocumentEngine
    ) -> Table {
        let columns = definition.visibleColumnsInOrder
        let transforms = transforms(for: columns, docType: definition.sourceDocType, engine: engine)
        let aggregates = columns.map(\.aggregate)

        func format(_ row: [FieldValue?]) -> [String?] {
            row.enumerated().map { index, value in
                index < transforms.count ? transforms[index].apply(value) : ReportValueFormatter.string(from: value)
            }
        }

        // Subtotal / grand-total cells: aggregate each column that asks for one.
        func totalsRow(_ rows: [[FieldValue?]], labelInFirstColumn label: String?) -> [String?] {
            var cells: [String?] = Array(repeating: nil, count: columns.count)
            for (index, kind) in aggregates.enumerated() where kind != .none {
                let columnValues = rows.map { $0.indices.contains(index) ? $0[index] : nil }
                if let total = aggregateValue(columnValues, kind) {
                    cells[index] = formatNumber(total)
                }
            }
            if let label, cells.first ?? nil == nil { cells[0] = label }
            return cells
        }

        let hasAnyAggregate = aggregates.contains { $0 != .none }
        var displayRows: [DisplayRow] = []

        if let groupKey = definition.groupByFieldKey,
           let groupIndex = typed.columnKeys.firstIndex(of: groupKey) {
            // Preserve first-seen group order.
            var order: [String] = []
            var buckets: [String: [[FieldValue?]]] = [:]
            let groupTransform = groupIndex < transforms.count ? transforms[groupIndex] : .plain
            for row in typed.rows {
                let raw = row.indices.contains(groupIndex) ? row[groupIndex] : nil
                let key = groupTransform.apply(raw) ?? "—"
                if buckets[key] == nil { order.append(key); buckets[key] = [] }
                buckets[key]?.append(row)
            }
            for key in order {
                let groupRows = buckets[key] ?? []
                var headerCells: [String?] = Array(repeating: nil, count: columns.count)
                headerCells[0] = key
                displayRows.append(DisplayRow(id: "g-\(key)", kind: .groupHeader, cells: headerCells))
                for (i, row) in groupRows.enumerated() {
                    displayRows.append(DisplayRow(id: "g-\(key)-\(i)", kind: .data, cells: format(row)))
                }
                if hasAnyAggregate {
                    displayRows.append(DisplayRow(id: "sub-\(key)", kind: .subtotal,
                                                  cells: totalsRow(groupRows, labelInFirstColumn: "\(key) total")))
                }
            }
        } else {
            for (i, row) in typed.rows.enumerated() {
                displayRows.append(DisplayRow(id: "r-\(i)", kind: .data, cells: format(row)))
            }
        }

        if hasAnyAggregate {
            displayRows.append(DisplayRow(id: "grand-total", kind: .grandTotal,
                                          cells: totalsRow(typed.rows, labelInFirstColumn: "Grand Total")))
        }

        return Table(columnLabels: typed.columnLabels, rows: displayRows)
    }

    // MARK: - Chart

    static func chartPoints(
        definition: SavedReportDefinition,
        typed: SavedReportEngine.TypedReportResult,
        engine: DocumentEngine
    ) -> [ChartPoint] {
        guard let chart = definition.chart,
              let categoryIndex = typed.columnKeys.firstIndex(of: chart.categoryFieldKey),
              let valueIndex = typed.columnKeys.firstIndex(of: chart.valueFieldKey) else {
            return []
        }
        let columns = definition.visibleColumnsInOrder
        let transforms = transforms(for: columns, docType: definition.sourceDocType, engine: engine)
        let categoryTransform = categoryIndex < transforms.count ? transforms[categoryIndex] : .plain

        var order: [String] = []
        var buckets: [String: [FieldValue?]] = [:]
        for row in typed.rows {
            let rawCategory = row.indices.contains(categoryIndex) ? row[categoryIndex] : nil
            let category = categoryTransform.apply(rawCategory) ?? "—"
            let value = row.indices.contains(valueIndex) ? row[valueIndex] : nil
            if buckets[category] == nil { order.append(category); buckets[category] = [] }
            buckets[category]?.append(value)
        }
        return order.map { category in
            let value = aggregateValue(buckets[category] ?? [], chart.valueAggregate) ?? 0
            return ChartPoint(id: category, category: category, value: value)
        }
    }

    // MARK: - Aggregation

    static func aggregateValue(_ values: [FieldValue?], _ kind: SavedReportAggregate) -> Double? {
        switch kind {
        case .none:
            return nil
        case .count:
            return Double(values.compactMap { $0 }.filter { if case .null = $0 { return false } else { return true } }.count)
        case .sum, .average, .min, .max:
            let numbers = values.compactMap { doubleValue($0) }
            guard !numbers.isEmpty else { return kind == .sum ? 0 : nil }
            switch kind {
            case .sum:     return numbers.reduce(0, +)
            case .average: return numbers.reduce(0, +) / Double(numbers.count)
            case .min:     return numbers.min()
            case .max:     return numbers.max()
            default:       return nil
            }
        }
    }

    // MARK: - Per-column formatting

    private enum CellTransform {
        case plain
        case link([String: String])
        case number
        case date

        func apply(_ value: FieldValue?) -> String? {
            guard let value else { return nil }
            switch self {
            case .plain:
                return ReportValueFormatter.string(from: value)
            case .link(let map):
                let raw = ReportValueFormatter.string(from: value)
                return raw.flatMap { map[$0] } ?? raw
            case .number:
                if let d = doubleValue(value) { return formatNumber(d) }
                return ReportValueFormatter.string(from: value)
            case .date:
                return formatDateString(ReportValueFormatter.string(from: value))
            }
        }
    }

    private static func transforms(
        for columns: [SavedReportColumn], docType docTypeId: String, engine: DocumentEngine
    ) -> [CellTransform] {
        guard let docType = HubManifest.docType(for: docTypeId) else {
            return columns.map { _ in .plain }
        }
        var linkMaps: [String: [String: String]] = [:]
        return columns.map { column in
            switch column.fieldKey {
            case "createdAt", "updatedAt":
                return .date
            case "id", "status", "company", "doctype":
                return .plain
            default:
                guard let field = docType.fields.first(where: { $0.key == column.fieldKey }) else { return .plain }
                switch field.type {
                case .link:
                    guard let target = field.linkedDocType else { return .plain }
                    if linkMaps[target] == nil { linkMaps[target] = displayNameMap(forDocType: target, engine: engine) }
                    return .link(linkMaps[target] ?? [:])
                case .number, .decimal, .currency:
                    return .number
                case .date, .datetime:
                    return .date
                default:
                    return .plain
                }
            }
        }
    }

    private static func displayNameMap(forDocType docType: String, engine: DocumentEngine) -> [String: String] {
        guard let meta = HubManifest.docType(for: docType),
              let documents = try? engine.list(docType: docType) else { return [:] }
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

    // MARK: - Value helpers

    static func doubleValue(_ value: FieldValue?) -> Double? {
        switch value {
        case .double(let d): return d
        case .int(let i):    return Double(i)
        case .string(let s): return Double(s)
        default:             return nil
        }
    }

    static func formatNumber(_ value: Double) -> String {
        numberFormatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private static func formatDateString(_ raw: String?) -> String? {
        guard let raw else { return nil }
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
        let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]; return f
    }()
    private static let isoDateTime: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    private static let mediumDate: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
    }()
}
