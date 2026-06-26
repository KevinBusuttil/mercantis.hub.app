import SwiftUI
import MercantisCore
import MercantisCoreUI

/// Loads a Hub report's `ReportResult` and hands it to
/// `MercantisCoreUI.GenericReportView`. The view re-runs the report
/// when the user taps Refresh and surfaces any computation errors
/// inline rather than crashing the whole detail pane.
///
/// Party-scoped reports (Customer Statement, Supplier Ledger) are unbounded
/// without a party, so this view requires the user to pick one first — using
/// the same `engine.list(docType:)` provider pattern the link fields use —
/// and passes it through as the report filter.
struct HubReportContainerView: View {

    let reportId: String
    let reportLabel: String
    let engine: DocumentEngine
    /// Optional saved-report plumbing. When supplied (and the report is
    /// customisable), the view offers a "Customise Report" action that clones
    /// the built-in report into an editable custom one.
    var savedReportStore: HubSavedReportStore? = nil
    var visibility: HubVisibilitySettings? = nil

    /// Injected at app scope; backs the Posting Audit report. Nil in previews.
    @Environment(\.postingBatchStore) private var postingBatchStore

    @State private var result: ReportResult?
    @State private var errorMessage: String?
    @State private var exportErrorMessage: String?
    @State private var partyId: String?
    @State private var parties: [Document] = []
    @State private var editing: SavedReportDefinition?

    /// Describes the party a report must be scoped to before it can run.
    private struct PartyRequirement {
        let docType: String
        let partyField: String
        let nameField: String
        let noun: String
    }

    private var partyRequirement: PartyRequirement? {
        switch reportId {
        case "customer-statement":
            return .init(docType: "Customer", partyField: "customer",
                         nameField: "customer_name", noun: "customer")
        case "supplier-ledger":
            return .init(docType: "Supplier", partyField: "supplier",
                         nameField: "supplier_name", noun: "supplier")
        default:
            return nil
        }
    }

    private var canCustomise: Bool {
        guard savedReportStore != nil, let visibility else { return false }
        return HubCustomReportCatalog.isCustomisable(reportId: reportId, settings: visibility)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if canCustomise {
                customiseBar
                Divider()
            }
            if let requirement = partyRequirement {
                partyPicker(requirement)
                Divider()
            }
            content
        }
        .onAppear {
            loadPartiesIfNeeded()
            load()
        }
        .onChange(of: reportId) { _, _ in
            partyId = nil
            loadPartiesIfNeeded()
            load()
        }
        .sheet(item: $editing) { report in
            if let savedReportStore {
                HubReportCustomiseView(report: report, store: savedReportStore, engine: engine)
            }
        }
        .alert(
            "Couldn’t export CSV",
            isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { if !$0 { exportErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { exportErrorMessage = nil }
        } message: {
            Text(exportErrorMessage ?? "")
        }
    }

    /// A slim bar offering "Save as Custom Report" for customisable built-ins.
    private var customiseBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "slider.horizontal.3")
                .foregroundStyle(.secondary)
            Text("Make this report your own — pick the columns and save your filters.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                startCustomising()
            } label: {
                Label("Save as Custom Report", systemImage: "plus")
            }
            .controlSize(.small)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func startCustomising() {
        guard let savedReportStore,
              let template = HubCustomReportCatalog.template(forBaseReportId: reportId) else { return }
        var report = HubCustomReportCatalog.makeSavedReport(
            from: template,
            ownerUserId: HubIdentity.userId(),
            name: "\(template.name) (Custom)"
        )
        // Seed any currently-applied party filter as the new report's default
        // so "customise what I'm looking at" keeps the user's context.
        if let requirement = partyRequirement, let partyId,
           let index = report.filters.firstIndex(where: { $0.fieldKey == requirement.partyField }) {
            report.filters[index].defaultValue = .string(partyId)
        }
        savedReportStore.save(report)
        editing = report
    }

    @ViewBuilder
    private var content: some View {
        if let requirement = partyRequirement, partyId == nil {
            ContentUnavailableView {
                Label("Choose a \(requirement.noun)", systemImage: "person.crop.circle.badge.questionmark")
            } description: {
                Text("Select a \(requirement.noun) above to view their \(reportLabel.lowercased()).")
            }
        } else if let result {
            GenericReportView(
                title: reportLabel,
                result: result,
                onRefresh: { load() },
                onExportCSV: { exportCSV(result: result) }
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

    // MARK: - CSV export

    private func exportCSV(result: ReportResult) {
        #if os(macOS)
        do {
            // Cancelling the save panel returns `.cancelled` and shows nothing;
            // only a real write failure surfaces an error to the user.
            _ = try HubReportCSV.export(result, named: reportLabel)
        } catch {
            exportErrorMessage = String(describing: error)
        }
        #endif
    }

    // MARK: - Party picker

    private func partyPicker(_ requirement: PartyRequirement) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(.secondary)
            Menu {
                ForEach(parties, id: \.id) { party in
                    Button(displayName(of: party, requirement)) {
                        partyId = party.id
                        load()
                    }
                }
            } label: {
                Label(selectedPartyName(requirement) ?? "Select \(requirement.noun.capitalized)",
                      systemImage: "person.crop.circle")
            }
            .disabled(parties.isEmpty)
            if parties.isEmpty {
                Text("No \(requirement.noun)s yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func selectedPartyName(_ requirement: PartyRequirement) -> String? {
        guard let partyId,
              let party = parties.first(where: { $0.id == partyId }) else { return nil }
        return displayName(of: party, requirement)
    }

    private func displayName(of party: Document, _ requirement: PartyRequirement) -> String {
        if case .string(let name)? = party.fields[requirement.nameField], !name.isEmpty {
            return name
        }
        return party.id
    }

    // MARK: - Loading

    private func loadPartiesIfNeeded() {
        guard let requirement = partyRequirement else {
            parties = []
            return
        }
        parties = (try? engine.list(docType: requirement.docType)) ?? []
    }

    private func load() {
        // Party reports stay empty until a party is chosen.
        if partyRequirement != nil, partyId == nil {
            result = nil
            errorMessage = nil
            return
        }

        var filters: [String: FieldValue] = [:]
        if let requirement = partyRequirement, let partyId {
            filters[requirement.partyField] = .string(partyId)
        }

        do {
            // Posting Audit reads the posting-batch ledger (a Core posting
            // primitive, not a DocType), so it routes through the injected
            // PostingBatchStore rather than the DocumentEngine dispatch.
            if reportId == HubReports.postingAudit.id {
                result = try HubReports.runPostingAudit(store: postingBatchStore)
                errorMessage = nil
            } else if let r = try HubReports.runResult(reportId: reportId, engine: engine, filters: filters) {
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
