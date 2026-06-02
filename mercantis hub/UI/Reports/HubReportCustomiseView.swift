import SwiftUI
import MercantisCore

/// Editor for a single custom report: rename it, choose which columns are
/// visible, reorder them, and store default values for its filters.
///
/// The column set and filter list come from the Hub catalogue, so the user
/// can only adjust safe, known fields — never invent arbitrary ones.
struct HubReportCustomiseView: View {

    @ObservedObject var store: HubSavedReportStore
    let engine: DocumentEngine

    @Environment(\.dismiss) private var dismiss

    @State private var draft: SavedReportDefinition
    /// Cached link-filter option documents, keyed by DocType.
    @State private var partyOptions: [String: [Document]] = [:]

    init(report: SavedReportDefinition, store: HubSavedReportStore, engine: DocumentEngine) {
        self.store = store
        self.engine = engine
        _draft = State(initialValue: report)
    }

    private var template: HubCustomReportCatalog.Template? {
        draft.baseReportId.flatMap(HubCustomReportCatalog.template(forBaseReportId:))
    }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                columnsSection
                if !draft.filters.isEmpty {
                    filtersSection
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Customise Report")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveAndClose() }
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: loadPartyOptions)
        }
        .frame(minWidth: 460, minHeight: 520)
    }

    // MARK: - Name

    private var nameSection: some View {
        Section("Report Name") {
            TextField("Report name", text: $draft.name)
        }
    }

    // MARK: - Columns

    private var columnsSection: some View {
        Section {
            ForEach(Array(draft.columns.enumerated()), id: \.element.id) { index, column in
                HStack {
                    Toggle(isOn: visibleBinding(index)) {
                        Text(column.resolvedLabel)
                    }
                    Spacer()
                    Button {
                        move(index, by: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == 0)
                    Button {
                        move(index, by: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == draft.columns.count - 1)
                }
            }
            .onMove { offsets, destination in
                draft.columns.move(fromOffsets: offsets, toOffset: destination)
            }
        } header: {
            Text("Columns")
        } footer: {
            Text("Turn columns on or off, and use the arrows to reorder them. At least one column stays visible.")
        }
    }

    private func visibleBinding(_ index: Int) -> Binding<Bool> {
        Binding(
            get: { draft.columns.indices.contains(index) ? draft.columns[index].visible : false },
            set: { if draft.columns.indices.contains(index) { draft.columns[index].visible = $0 } }
        )
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard draft.columns.indices.contains(index), draft.columns.indices.contains(target) else { return }
        draft.columns.swapAt(index, target)
    }

    // MARK: - Filters

    private var filtersSection: some View {
        Section {
            ForEach(Array(draft.filters.enumerated()), id: \.element.fieldKey) { index, filter in
                filterRow(index: index, filter: filter)
            }
        } header: {
            Text("Default Filters")
        } footer: {
            Text("Saved defaults pre-fill this report each time you open it. Leave a filter on “Any” to show everything.")
        }
    }

    @ViewBuilder
    private func filterRow(index: Int, filter: SavedReportFilter) -> some View {
        let label = filterLabel(for: filter.fieldKey)
        if let docType = targetDocType(for: filter.fieldKey) {
            Picker(label, selection: partySelectionBinding(index: index)) {
                Text("Any").tag(String?.none)
                ForEach(partyOptions[docType] ?? [], id: \.id) { doc in
                    Text(displayName(of: doc, docType: docType)).tag(Optional(doc.id))
                }
            }
        } else {
            TextField(label, text: textBinding(index: index), prompt: Text("Any"))
        }
    }

    // MARK: - Bindings

    /// String binding for free-text filter defaults (e.g. Status).
    private func textBinding(index: Int) -> Binding<String> {
        Binding(
            get: {
                if case .string(let s)? = draft.filters[index].defaultValue { return s }
                return ""
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                draft.filters[index].defaultValue = trimmed.isEmpty ? nil : .string(trimmed)
            }
        )
    }

    /// Optional-id binding for link-backed filter defaults (e.g. Customer).
    private func partySelectionBinding(index: Int) -> Binding<String?> {
        Binding(
            get: {
                if case .string(let id)? = draft.filters[index].defaultValue { return id }
                return nil
            },
            set: { newValue in
                draft.filters[index].defaultValue = newValue.map { .string($0) }
            }
        )
    }

    // MARK: - Catalogue helpers

    private func filterLabel(for fieldKey: String) -> String {
        template?.filters.first { $0.fieldKey == fieldKey }?.label
            ?? fieldKey.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func targetDocType(for fieldKey: String) -> String? {
        template?.filters.first { $0.fieldKey == fieldKey }?.targetDocType
    }

    private func loadPartyOptions() {
        guard let template else { return }
        for filter in template.filters {
            guard let docType = filter.targetDocType, partyOptions[docType] == nil else { continue }
            partyOptions[docType] = (try? engine.list(docType: docType)) ?? []
        }
    }

    private func displayName(of doc: Document, docType: String) -> String {
        if let meta = HubManifest.docType(for: docType),
           case .string(let name)? = doc.fields[meta.titleField],
           !name.trimmingCharacters(in: .whitespaces).isEmpty {
            return name
        }
        return doc.id
    }

    // MARK: - Persist

    private func saveAndClose() {
        // Reindex `order` to the current on-screen arrangement so the runner
        // renders columns exactly as shown.
        var ordered = draft
        ordered.columns = draft.columns.enumerated().map { index, column in
            var c = column
            c.order = index
            return c
        }
        // Guard against hiding every column — keep the first visible.
        if ordered.visibleColumnsInOrder.isEmpty, !ordered.columns.isEmpty {
            ordered.columns[0].visible = true
        }
        store.save(ordered)
        dismiss()
    }
}
