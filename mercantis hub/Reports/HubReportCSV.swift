import Foundation
import MercantisCore

/// Hub-side CSV delivery for reports. The serialisation itself lives in Core
/// (`ReportResult.csvString()`); this only adds the app-specific bits:
/// a filesystem-safe filename, the on-disk write, and the macOS save panel.
enum HubReportCSV {

    /// A filesystem-safe `.csv` filename derived from a report name.
    static func fileName(for reportName: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = reportName.components(separatedBy: invalid).joined(separator: "-")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.isEmpty ? "report" : trimmed) + ".csv"
    }

    /// Serialise `result` as CSV (Core's RFC-4180 serialiser) and write it to
    /// `url`. Kept free of any UI so the filesystem-write part can be tested
    /// without presenting a save panel. Throws if the write fails.
    static func write(_ result: ReportResult, to url: URL) throws {
        try Data(result.csvString().utf8).write(to: url)
    }
}

#if os(macOS)
import AppKit
import UniformTypeIdentifiers

extension HubReportCSV {
    /// The outcome of presenting the save panel.
    enum ExportOutcome: Equatable {
        case saved(URL)
        case cancelled
    }

    /// Present a save panel and write the report as CSV to the chosen file.
    /// Returns `.cancelled` if the user dismisses the panel (not an error);
    /// throws if the chosen location cannot be written.
    static func export(_ result: ReportResult, named reportName: String) throws -> ExportOutcome {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileName(for: reportName)
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }
        try write(result, to: url)
        return .saved(url)
    }
}
#endif
