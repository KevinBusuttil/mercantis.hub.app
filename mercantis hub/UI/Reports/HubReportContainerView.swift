import SwiftUI
import MercantisCore
import MercantisCoreUI

/// Loads a Hub report's `ReportResult` and hands it to
/// `MercantisCoreUI.GenericReportView`. The view re-runs the report
/// when the user taps Refresh and surfaces any computation errors
/// inline rather than crashing the whole detail pane.
struct HubReportContainerView: View {

    let reportId: String
    let reportLabel: String
    let engine: DocumentEngine

    @State private var result: ReportResult?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let result {
                GenericReportView(
                    title: reportLabel,
                    result: result,
                    onRefresh: { load() }
                )
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("\(reportLabel) has nothing to show yet", systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text("This report needs some data before it can run. Create the relevant records first, then refresh.\n\nDetails: \(errorMessage)")
                }
            } else {
                ProgressView("Running \(reportLabel)…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear(perform: load)
        .onChange(of: reportId) { _, _ in load() }
    }

    private func load() {
        do {
            if let r = try HubReports.runResult(reportId: reportId, engine: engine) {
                result = r
                errorMessage = nil
            } else {
                result = nil
                errorMessage = "Unknown report id '\(reportId)'."
            }
        } catch {
            result = nil
            errorMessage = String(describing: error)
        }
    }
}
