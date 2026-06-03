import Foundation
import MercantisCore

/// Hub-side CSV delivery for reports. The serialisation itself lives in Core
/// (`ReportResult.csvString()`); this only adds the app-specific bits:
/// a filesystem-safe filename and the macOS save panel.
enum HubReportCSV {

    /// A filesystem-safe `.csv` filename derived from a report name.
    static func fileName(for reportName: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = reportName.components(separatedBy: invalid).joined(separator: "-")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.isEmpty ? "report" : trimmed) + ".csv"
    }
}

#if os(macOS)
import AppKit
import UniformTypeIdentifiers

extension HubReportCSV {
    /// Present a save panel and write the report as CSV (Core's RFC-4180
    /// serialiser) to the chosen file.
    static func export(_ result: ReportResult, named reportName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileName(for: reportName)
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? result.csvString().data(using: .utf8)?.write(to: url)
    }
}
#endif
