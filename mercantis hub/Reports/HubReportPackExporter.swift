import Foundation
import MercantisCore

/// Phase 3 (Accounting Autopilot) — assembles several reports into one
/// **accountant pack**: a folder of CSVs (Trial Balance, Profit & Loss, Balance
/// Sheet, General Ledger, Tax Summary) the owner hands to their accountant. The
/// CSV serialisation is Core's (`ReportResult.csvString()`); this adds only the
/// folder write and the macOS save panel, reusing `HubReportCSV` for the
/// filename and single-file write so the two exporters stay consistent.
enum HubReportPackExporter {

    /// A report paired with the name it should carry in the pack.
    struct NamedReport {
        let name: String
        let result: ReportResult
    }

    /// Write each report as a CSV inside `directory` (created if needed). Kept
    /// free of any UI so the filesystem part is testable. Returns the URLs
    /// written. Throws if the directory or any file cannot be written.
    @discardableResult
    static func write(_ reports: [NamedReport], toDirectory directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var written: [URL] = []
        for report in reports {
            let url = directory.appendingPathComponent(HubReportCSV.fileName(for: report.name))
            try HubReportCSV.write(report.result, to: url)
            written.append(url)
        }
        return written
    }
}

#if os(macOS)
import AppKit

extension HubReportPackExporter {
    /// The outcome of presenting the save panel.
    enum ExportOutcome: Equatable {
        case saved(URL, count: Int)
        case cancelled
    }

    /// Present a save panel for a new folder, then write every report into it as
    /// a CSV. Returns `.cancelled` if the user dismisses the panel; throws if the
    /// chosen location cannot be written.
    static func export(_ reports: [NamedReport], suggestedName: String) throws -> ExportOutcome {
        let panel = NSSavePanel()
        panel.title = "Save Accountant Pack"
        panel.message = "Choose where to save the folder of statements for your accountant."
        panel.nameFieldStringValue = folderName(suggestedName)
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }
        let written = try write(reports, toDirectory: url)
        return .saved(url, count: written.count)
    }

    /// A filesystem-safe folder name (no extension).
    static func folderName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Accountant Pack" : trimmed
    }
}
#endif
