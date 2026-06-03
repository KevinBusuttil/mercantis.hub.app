import Foundation
import MercantisCore

/// Serialises a `ReportResult` to CSV. Shared by the built-in report viewer
/// and the saved/custom report runner so both export identically.
enum HubReportCSV {

    /// RFC-4180-style CSV: a header row followed by one line per result row.
    /// Fields are quoted when they contain a comma, double-quote, or newline,
    /// and embedded quotes are doubled. `nil` cells become empty fields.
    static func string(from result: ReportResult) -> String {
        var lines: [String] = []
        lines.append(result.columns.map { escape($0) }.joined(separator: ","))
        for row in result.rows {
            lines.append(row.map { escape($0 ?? "") }.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    /// A filesystem-safe filename stem derived from a report name.
    static func fileName(for reportName: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = reportName.components(separatedBy: invalid).joined(separator: "-")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.isEmpty ? "report" : trimmed) + ".csv"
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else {
            return field
        }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

#if os(macOS)
import AppKit
import UniformTypeIdentifiers

extension HubReportCSV {
    /// Present a save panel and write the report as CSV to the chosen file.
    static func export(_ result: ReportResult, named reportName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileName(for: reportName)
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? string(from: result).data(using: .utf8)?.write(to: url)
    }
}
#endif
