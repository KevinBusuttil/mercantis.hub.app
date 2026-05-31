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

    @State private var result: ReportResult?
    @State private var errorMessage: String?
    @State private var partyId: String?
    @State private var parties: [Document] = []

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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
            if let r = try HubReports.runResult(reportId: reportId, engine: engine, filters: filters) {
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
