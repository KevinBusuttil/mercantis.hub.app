import SwiftUI
import MercantisCore
import MercantisCoreUI

/// Runs and displays one saved report, reusing Core's `GenericReportView`.
/// Offers Customise (edit) and Delete from the toolbar.
struct HubSavedReportRunnerView: View {

    let reportId: String
    @ObservedObject var store: HubSavedReportStore
    let engine: DocumentEngine

    @State private var result: ReportResult?
    @State private var errorMessage: String?
    @State private var editing: SavedReportDefinition?
    @State private var showDeleteConfirm = false

    @Environment(\.dismiss) private var dismiss

    private var report: SavedReportDefinition? {
        store.get(id: reportId)
    }

    var body: some View {
        Group {
            if let report {
                content(for: report)
            } else {
                // The report was deleted out from under this view.
                ContentUnavailableView {
                    Label("Report not found", systemImage: "doc.questionmark")
                } description: {
                    Text("This custom report is no longer available.")
                }
            }
        }
        .navigationTitle(report?.name ?? "Custom Report")
        .toolbar {
            if let report {
                ToolbarItemGroup {
                    Button {
                        editing = report
                    } label: {
                        Label("Customise", systemImage: "slider.horizontal.3")
                    }
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .sheet(item: $editing, onDismiss: { load() }) { editingReport in
            HubReportCustomiseView(report: editingReport, store: store, engine: engine)
        }
        .confirmationDialog(
            "Delete this custom report?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                store.delete(id: reportId)
                dismiss()
            }
            Button("Keep", role: .cancel) { }
        } message: {
            Text("The built-in report it was based on is not affected.")
        }
        .onAppear(perform: load)
        .onChange(of: reportId) { _, _ in load() }
    }

    @ViewBuilder
    private func content(for report: SavedReportDefinition) -> some View {
        if let result {
            GenericReportView(
                title: report.name,
                result: result,
                onRefresh: { load() }
            )
        } else if let errorMessage {
            ContentUnavailableView {
                Label("\(report.name) has nothing to show yet", systemImage: "doc.text.magnifyingglass")
            } description: {
                Text("This report needs some data before it can run. Create the relevant records first, then refresh.\n\nDetails: \(errorMessage)")
            }
        } else {
            ProgressView("Running \(report.name)…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func load() {
        guard let report else {
            result = nil
            errorMessage = nil
            return
        }
        do {
            result = try HubSavedReportRunner.run(savedReport: report, engine: engine)
            errorMessage = nil
        } catch {
            result = nil
            errorMessage = String(describing: error)
        }
    }
}
