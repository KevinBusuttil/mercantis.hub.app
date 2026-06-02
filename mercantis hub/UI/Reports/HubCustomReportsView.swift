import SwiftUI
import MercantisCore
import MercantisCoreUI

/// The Custom Reports home: lists the user's saved reports and lets them
/// start a new one from any customisable built-in report.
struct HubCustomReportsView: View {

    @ObservedObject var store: HubSavedReportStore
    let engine: DocumentEngine
    @ObservedObject var visibility: HubVisibilitySettings

    @State private var editing: SavedReportDefinition?

    private var userId: String { HubIdentity.userId() }

    private var myReports: [SavedReportDefinition] {
        store.accessibleReports(forUserId: userId)
    }

    private var templates: [HubCustomReportCatalog.Template] {
        HubCustomReportCatalog.availableTemplates(visibility)
    }

    var body: some View {
        NavigationStack {
            Group {
                if myReports.isEmpty {
                    emptyState
                } else {
                    reportList
                }
            }
            .navigationTitle("Custom Reports")
            .toolbar {
                ToolbarItem {
                    newReportMenu
                }
            }
            .navigationDestination(for: String.self) { id in
                HubSavedReportRunnerView(reportId: id, store: store, engine: engine)
            }
            .sheet(item: $editing) { report in
                HubReportCustomiseView(report: report, store: store, engine: engine)
            }
        }
    }

    // MARK: - List

    private var reportList: some View {
        List {
            Section {
                ForEach(myReports) { report in
                    NavigationLink(value: report.id) {
                        reportRow(report)
                    }
                }
                .onDelete { offsets in
                    for index in offsets { store.delete(id: myReports[index].id) }
                }
            } footer: {
                Text("Custom reports are saved on this device. They never change the built-in reports they came from.")
            }
        }
    }

    private func reportRow(_ report: SavedReportDefinition) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(report.name)
                .font(.headline)
            Text(baseLabel(for: report))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func baseLabel(for report: SavedReportDefinition) -> String {
        let templateName = report.baseReportId.flatMap { id in
            HubCustomReportCatalog.template(forBaseReportId: id)?.name
        }
        let base = templateName ?? report.baseReportId ?? "—"
        let visibleCount = report.visibleColumnsInOrder.count
        return "Based on \(base) · \(visibleCount) column\(visibleCount == 1 ? "" : "s")"
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No custom reports yet", systemImage: "slider.horizontal.3")
        } description: {
            Text("Customise a built-in report to choose its columns and save the filters you use most. Your version lives here, alongside the original.")
        } actions: {
            newReportMenu
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Create

    private var newReportMenu: some View {
        Menu {
            if templates.isEmpty {
                Text("No reports available to customise")
            } else {
                ForEach(templates) { template in
                    Button(template.name) { startCustomising(template) }
                }
            }
        } label: {
            Label("Customise a Report", systemImage: "plus")
        }
    }

    private func startCustomising(_ template: HubCustomReportCatalog.Template) {
        let report = HubCustomReportCatalog.makeSavedReport(
            from: template,
            ownerUserId: userId,
            name: "\(template.name) (Custom)"
        )
        store.save(report)
        editing = report
    }
}
