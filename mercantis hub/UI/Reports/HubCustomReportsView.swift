import SwiftUI
import MercantisCore
import MercantisCoreUI

/// The Custom Reports home: lists the user's saved reports and lets them
/// start a new one — either by customising a built-in report or by building a
/// brand-new report from scratch on a chosen record type.
struct HubCustomReportsView: View {

    @ObservedObject var store: HubSavedReportStore
    let engine: DocumentEngine
    let savedReportEngine: SavedReportEngine
    @ObservedObject var visibility: HubVisibilitySettings

    @State private var editing: SavedReportDefinition?

    private var userId: String { HubIdentity.userId() }

    private var myReports: [SavedReportDefinition] {
        store.accessibleReports(forUserId: userId)
    }

    private var templates: [HubCustomReportCatalog.Template] {
        HubCustomReportCatalog.availableTemplates(visibility)
    }

    private var reportableTypes: [HubReportableDocTypes.Entry] {
        HubReportableDocTypes.available(visibility)
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
                HubSavedReportRunnerView(
                    reportId: id,
                    store: store,
                    engine: engine,
                    savedReportEngine: savedReportEngine
                )
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
            Text(subtitle(for: report))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func subtitle(for report: SavedReportDefinition) -> String {
        let visibleCount = report.visibleColumnsInOrder.count
        let columns = "\(visibleCount) column\(visibleCount == 1 ? "" : "s")"
        if let baseId = report.baseReportId {
            let base = HubCustomReportCatalog.template(forBaseReportId: baseId)?.name ?? baseId
            return "Based on \(base) · \(columns)"
        }
        // From-scratch report — describe its source record type.
        let typeLabel = HubReportableDocTypes.entry(for: report.sourceDocType)?.label
            ?? report.sourceDocType
        return "\(typeLabel) · \(columns)"
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No custom reports yet", systemImage: "slider.horizontal.3")
        } description: {
            Text("Customise a built-in report, or build your own from any record type. Your reports live here and never change the originals.")
        } actions: {
            newReportMenu
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Create

    private var newReportMenu: some View {
        Menu {
            Section("Customise a built-in report") {
                if templates.isEmpty {
                    Text("None available")
                } else {
                    ForEach(templates) { template in
                        Button(template.name) { startCustomising(template) }
                    }
                }
            }
            Section("Build a new report from") {
                if reportableTypes.isEmpty {
                    Text("None available")
                } else {
                    ForEach(reportableTypes) { entry in
                        Button(entry.label) { startBuilding(entry) }
                    }
                }
            }
        } label: {
            Label("New Report", systemImage: "plus")
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

    private func startBuilding(_ entry: HubReportableDocTypes.Entry) {
        guard let docType = HubManifest.docType(for: entry.docType) else { return }
        let report = HubReportBuilder.makeBlankReport(
            docType: docType,
            ownerUserId: userId,
            name: "\(entry.label) Report"
        )
        store.save(report)
        editing = report
    }
}
