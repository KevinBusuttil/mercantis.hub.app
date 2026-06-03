import SwiftUI
import MercantisCore

/// Editor for a single saved report.
///
/// Two shapes share this editor:
/// - **Customised built-in** (`baseReportId != nil`): the column set and filter
///   list come from the Hub catalogue; the user toggles/reorders columns and
///   stores filter defaults.
/// - **From-scratch** (`baseReportId == nil`): the column set comes from the
///   source DocType's metadata; the user picks columns, adds filters over the
///   safe operator set, and chooses a sort order.
///
/// In both cases the user can only reference fields that exist in metadata —
/// never invent arbitrary ones.
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

    private enum FilterKind: Equatable {
        case text
        case number
        case boolean
        case link(String)
    }

    /// A field the user may add a filter on (avoids tuple key paths in `ForEach`).
    private struct FilterableField: Identifiable {
        let key: String
        let label: String
        var id: String { key }
    }

    private var isFromScratch: Bool { draft.baseReportId == nil }

    private var template: HubCustomReportCatalog.Template? {
        guard let baseId = draft.baseReportId else { return nil }
        return HubCustomReportCatalog.template(forBaseReportId: baseId)
    }

    private var sourceDocType: DocType? {
        HubManifest.docType(for: draft.sourceDocType)
    }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                columnsSection
                if isFromScratch {
                    scratchFiltersSection
                    sortSection
                } else if !draft.filters.isEmpty {
                    defaultFiltersSection
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isFromScratch ? "New Report" : "Customise Report")
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
        .frame(minWidth: 480, minHeight: 560)
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

    // MARK: - Filters (customised built-in — defaults only)

    private var defaultFiltersSection: some View {
        Section {
            ForEach(Array(draft.filters.enumerated()), id: \.element.fieldKey) { index, filter in
                defaultFilterRow(index: index, filter: filter)
            }
        } header: {
            Text("Default Filters")
        } footer: {
            Text("Saved defaults pre-fill this report each time you open it. Leave a filter on “Any” to show everything.")
        }
    }

    @ViewBuilder
    private func defaultFilterRow(index: Int, filter: SavedReportFilter) -> some View {
        let label = filterLabel(for: filter.fieldKey)
        if let docType = targetDocType(for: filter.fieldKey) {
            Picker(label, selection: defaultLinkBinding(index: index)) {
                Text("Any").tag(String?.none)
                ForEach(partyOptions[docType] ?? [], id: \.id) { doc in
                    Text(displayName(of: doc, docType: docType)).tag(Optional(doc.id))
                }
            }
        } else {
            TextField(label, text: defaultTextBinding(index: index), prompt: Text("Any"))
        }
    }

    /// Free-text default binding (stored in `defaultValue`).
    private func defaultTextBinding(index: Int) -> Binding<String> {
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

    /// Link-id default binding (stored in `defaultValue`).
    private func defaultLinkBinding(index: Int) -> Binding<String?> {
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

    // MARK: - Filters (from-scratch — full filter builder)

    private var scratchFiltersSection: some View {
        Section {
            ForEach(Array(draft.filters.enumerated()), id: \.element.fieldKey) { index, filter in
                scratchFilterRow(index: index, filter: filter)
            }
            addFilterMenu
        } header: {
            Text("Filters")
        } footer: {
            Text("Add filters to narrow what the report shows. Fields already filtered don't appear again.")
        }
    }

    @ViewBuilder
    private func scratchFilterRow(index: Int, filter: SavedReportFilter) -> some View {
        let kind = filterKind(for: filter.fieldKey)
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(filterLabel(for: filter.fieldKey))
                operatorMenu(index: index, kind: kind)
            }
            Spacer()
            scratchValueEditor(index: index, kind: kind)
            Button(role: .destructive) {
                removeFilter(at: index)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
        }
    }

    private func operatorMenu(index: Int, kind: FilterKind) -> some View {
        let current = draft.filters.indices.contains(index) ? draft.filters[index].op : .equals
        return Menu {
            ForEach(operators(for: kind), id: \.self) { op in
                Button(operatorLabel(op)) { setOperator(op, at: index) }
            }
        } label: {
            Text(operatorLabel(current))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func scratchValueEditor(index: Int, kind: FilterKind) -> some View {
        let op = draft.filters.indices.contains(index) ? draft.filters[index].op : .equals
        if !op.requiresValue {
            EmptyView()
        } else {
            switch kind {
            case .text:
                TextField("Value", text: scratchTextBinding(index: index))
                    .frame(maxWidth: 170)
                    .multilineTextAlignment(.trailing)
            case .number:
                TextField("Value", text: scratchNumberBinding(index: index))
                    .frame(maxWidth: 120)
                    .multilineTextAlignment(.trailing)
            case .boolean:
                Picker("", selection: scratchBoolBinding(index: index)) {
                    Text("Yes").tag(true)
                    Text("No").tag(false)
                }
                .labelsHidden()
                .frame(maxWidth: 110)
            case .link(let docType):
                Menu {
                    Button("Any") { setScratchValue(nil, at: index) }
                    ForEach(partyOptions[docType] ?? [], id: \.id) { doc in
                        Button(displayName(of: doc, docType: docType)) {
                            setScratchValue(.string(doc.id), at: index)
                        }
                    }
                } label: {
                    Text(scratchLinkLabel(index: index, docType: docType))
                }
            }
        }
    }

    private var addFilterMenu: some View {
        let used = Set(draft.filters.map(\.fieldKey))
        let available = filterableFields().filter { !used.contains($0.key) }
        return Menu {
            if available.isEmpty {
                Text("No more fields to filter")
            } else {
                ForEach(available) { field in
                    Button(field.label) { addFilter(fieldKey: field.key) }
                }
            }
        } label: {
            Label("Add Filter", systemImage: "plus.circle")
        }
        .disabled(available.isEmpty)
    }

    // From-scratch value bindings (stored in `value`).

    private func scratchTextBinding(index: Int) -> Binding<String> {
        Binding(
            get: {
                if case .string(let s)? = draft.filters[index].value { return s }
                return ""
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                draft.filters[index].value = trimmed.isEmpty ? nil : .string(trimmed)
            }
        )
    }

    private func scratchNumberBinding(index: Int) -> Binding<String> {
        Binding(
            get: {
                switch draft.filters[index].value {
                case .double(let d): return String(d)
                case .int(let i):    return String(i)
                default:             return ""
                }
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                draft.filters[index].value = Double(trimmed).map { .double($0) }
            }
        )
    }

    private func scratchBoolBinding(index: Int) -> Binding<Bool> {
        Binding(
            get: {
                if case .bool(let b)? = draft.filters[index].value { return b }
                return false
            },
            set: { draft.filters[index].value = .bool($0) }
        )
    }

    private func scratchLinkLabel(index: Int, docType: String) -> String {
        guard case .string(let id)? = draft.filters[index].value else { return "Any" }
        if let doc = (partyOptions[docType] ?? []).first(where: { $0.id == id }) {
            return displayName(of: doc, docType: docType)
        }
        return id
    }

    private func setScratchValue(_ value: FieldValue?, at index: Int) {
        guard draft.filters.indices.contains(index) else { return }
        draft.filters[index].value = value
    }

    private func setOperator(_ op: SavedReportFilterOperator, at index: Int) {
        guard draft.filters.indices.contains(index) else { return }
        draft.filters[index].op = op
        if !op.requiresValue {
            draft.filters[index].value = nil
        }
    }

    private func addFilter(fieldKey: String) {
        let kind = filterKind(for: fieldKey)
        draft.filters.append(
            SavedReportFilter(fieldKey: fieldKey, op: defaultOperator(for: kind))
        )
        if case .link(let target) = kind { ensureOptions(target) }
    }

    private func removeFilter(at index: Int) {
        guard draft.filters.indices.contains(index) else { return }
        draft.filters.remove(at: index)
    }

    // MARK: - Sort (from-scratch)

    private var sortSection: some View {
        Section {
            Picker("Sort by", selection: sortFieldBinding) {
                Text("None").tag(String?.none)
                ForEach(draft.columns) { column in
                    Text(column.resolvedLabel).tag(Optional(column.fieldKey))
                }
            }
            if draft.sorts.first != nil {
                Picker("Direction", selection: sortDirectionBinding) {
                    Text("Ascending").tag(SavedReportSortDirection.ascending)
                    Text("Descending").tag(SavedReportSortDirection.descending)
                }
            }
        } header: {
            Text("Sort")
        }
    }

    private var sortFieldBinding: Binding<String?> {
        Binding(
            get: { draft.sorts.first?.fieldKey },
            set: { newValue in
                if let key = newValue {
                    let direction = draft.sorts.first?.direction ?? .ascending
                    draft.sorts = [SavedReportSort(fieldKey: key, direction: direction)]
                } else {
                    draft.sorts = []
                }
            }
        )
    }

    private var sortDirectionBinding: Binding<SavedReportSortDirection> {
        Binding(
            get: { draft.sorts.first?.direction ?? .ascending },
            set: { newValue in
                guard let key = draft.sorts.first?.fieldKey else { return }
                draft.sorts = [SavedReportSort(fieldKey: key, direction: newValue)]
            }
        )
    }

    // MARK: - Metadata helpers

    private func filterLabel(for fieldKey: String) -> String {
        if let label = template?.filters.first(where: { $0.fieldKey == fieldKey })?.label {
            return label
        }
        if fieldKey == "id" { return "ID" }
        if fieldKey == "status" { return "Status" }
        if let field = sourceDocType?.fields.first(where: { $0.key == fieldKey }) {
            return field.label
        }
        return fieldKey.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func targetDocType(for fieldKey: String) -> String? {
        if let target = template?.filters.first(where: { $0.fieldKey == fieldKey })?.targetDocType {
            return target
        }
        if let field = sourceDocType?.fields.first(where: { $0.key == fieldKey }), field.type == .link {
            return field.linkedDocType
        }
        return nil
    }

    private func filterKind(for fieldKey: String) -> FilterKind {
        if let target = targetDocType(for: fieldKey) { return .link(target) }
        if fieldKey == "id" || fieldKey == "status" { return .text }
        guard let field = sourceDocType?.fields.first(where: { $0.key == fieldKey }) else { return .text }
        switch field.type {
        case .number, .decimal, .currency: return .number
        case .boolean:                     return .boolean
        default:                           return .text
        }
    }

    /// Fields a from-scratch report may filter on: `id`, `status`, and every
    /// filterable DocType field.
    private func filterableFields() -> [FilterableField] {
        var fields: [FilterableField] = [
            FilterableField(key: "id", label: "ID"),
            FilterableField(key: "status", label: "Status"),
        ]
        if let docType = sourceDocType {
            for field in docType.fields where HubReportBuilder.isFilterableType(field.type) {
                fields.append(FilterableField(key: field.key, label: field.label))
            }
        }
        return fields
    }

    private func operators(for kind: FilterKind) -> [SavedReportFilterOperator] {
        switch kind {
        case .text:    return [.equals, .notEquals, .contains, .isNull, .isNotNull]
        case .number:  return [.greaterThanOrEqual, .greaterThan, .lessThanOrEqual, .lessThan, .isNull, .isNotNull]
        case .boolean: return [.equals]
        case .link:    return [.equals, .notEquals, .isNull, .isNotNull]
        }
    }

    private func defaultOperator(for kind: FilterKind) -> SavedReportFilterOperator {
        if case .number = kind { return .greaterThanOrEqual }
        return .equals
    }

    private func operatorLabel(_ op: SavedReportFilterOperator) -> String {
        switch op {
        case .equals:             return "equals"
        case .notEquals:          return "is not"
        case .greaterThan:        return "greater than"
        case .greaterThanOrEqual: return "at least"
        case .lessThan:           return "less than"
        case .lessThanOrEqual:    return "at most"
        case .contains:           return "contains"
        case .isNull:             return "is empty"
        case .isNotNull:          return "is not empty"
        }
    }

    private func loadPartyOptions() {
        if let template {
            for filter in template.filters {
                if let docType = filter.targetDocType { ensureOptions(docType) }
            }
        }
        if isFromScratch, let docType = sourceDocType {
            for field in docType.fields where field.type == .link {
                if let target = field.linkedDocType { ensureOptions(target) }
            }
        }
    }

    private func ensureOptions(_ docType: String) {
        guard partyOptions[docType] == nil else { return }
        partyOptions[docType] = (try? engine.list(docType: docType)) ?? []
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
        var ordered = draft

        // Reindex `order` to the current on-screen arrangement so the runner
        // renders columns exactly as shown.
        ordered.columns = draft.columns.enumerated().map { index, column in
            var c = column
            c.order = index
            return c
        }

        // For from-scratch reports, drop filters that need a value but have
        // none — a blank filter does nothing, so don't persist clutter.
        // Customised built-ins keep their (possibly blank) template filter
        // slots so the user can set a default later.
        if isFromScratch {
            ordered.filters = ordered.filters.filter { filter in
                guard filter.op.requiresValue else { return true }
                let resolved = filter.value ?? filter.defaultValue
                if case .some(.null) = resolved { return false }
                return resolved != nil
            }
        }

        // Guard against hiding every column — keep the first visible.
        if ordered.visibleColumnsInOrder.isEmpty, !ordered.columns.isEmpty {
            ordered.columns[0].visible = true
        }

        store.save(ordered)
        dismiss()
    }
}
