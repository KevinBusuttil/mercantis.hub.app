import SwiftUI
import UniformTypeIdentifiers
import MercantisCore

/// A friendly, visual builder for from-scratch reports: a field palette you add
/// columns from, drag-to-reorder selected columns, group-by with subtotals and
/// a grand total, an optional chart, and a live preview that updates as you
/// edit. Saves a `SavedReportDefinition` (the same model the runner executes),
/// so nothing here is throw-away.
struct HubReportStudioView: View {

    @ObservedObject var store: HubSavedReportStore
    let engine: DocumentEngine
    let savedReportEngine: SavedReportEngine

    @Environment(\.dismiss) private var dismiss

    @State private var draft: SavedReportDefinition
    @State private var table: HubReportProjection.Table?
    @State private var chartPoints: [HubReportProjection.ChartPoint] = []
    @State private var previewError: String?

    init(report: SavedReportDefinition, store: HubSavedReportStore, engine: DocumentEngine, savedReportEngine: SavedReportEngine) {
        self.store = store
        self.engine = engine
        self.savedReportEngine = savedReportEngine
        _draft = State(initialValue: report)
    }

    private var sourceDocType: DocType? { HubManifest.docType(for: draft.sourceDocType) }
    private var userId: String { HubIdentity.userId() }

    /// Field keys already chosen as columns, for palette filtering.
    private var chosenKeys: Set<String> { Set(draft.columns.map(\.fieldKey)) }

    /// Fields the user can add: the DocType's scalar fields plus a few system
    /// columns, minus the ones already added.
    private var paletteFields: [FieldOption] {
        var options: [FieldOption] = []
        if let docType = sourceDocType {
            for field in docType.fields where isScalar(field) {
                options.append(FieldOption(key: field.key, label: field.label))
            }
        }
        for (key, label) in systemColumns {
            options.append(FieldOption(key: key, label: label))
        }
        return options.filter { !chosenKeys.contains($0.key) }
    }

    var body: some View {
        NavigationStack {
            HSplitView {
                configPane
                    .frame(minWidth: 320, idealWidth: 360, maxWidth: 460)
                previewPane
                    .frame(minWidth: 420)
            }
            .navigationTitle("Report Builder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveAndClose() }
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty || draft.columns.isEmpty)
                }
            }
            .onAppear(perform: refresh)
            .onChange(of: draft) { _, _ in refresh() }
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    // MARK: - Config pane

    private var configPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section("Name") {
                    TextField("Report name", text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                }
                section("Add Columns") { palette }
                section("Columns") { columnsList }
                section("Group By") { groupByPicker }
                section("Chart") { chartConfig }
            }
            .padding(16)
        }
        .background(MercantisTheme.surfaceMuted.opacity(0.4))
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(MercantisTheme.textMuted)
            content()
        }
    }

    private var palette: some View {
        Group {
            if paletteFields.isEmpty {
                Text("All available fields have been added.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                FlowChips(items: paletteFields) { field in
                    Button {
                        addColumn(field.key)
                    } label: {
                        Label(field.label, systemImage: "plus.circle.fill")
                            .font(.system(size: 12))
                            .lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var columnsList: some View {
        Group {
            if draft.columns.isEmpty {
                Text("Add fields above to build your report.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(draft.columns.enumerated()), id: \.element.id) { index, column in
                        columnRow(index: index, column: column)
                        if index < draft.columns.count - 1 { Divider() }
                    }
                }
                .background(MercantisTheme.surface, in: RoundedRectangle(cornerRadius: 8))
                Text("Drag the handle to reorder. Set an aggregate to total a column.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func columnRow(index: Int, column: SavedReportColumn) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(MercantisTheme.textMuted)
                .onDrag { NSItemProvider(object: column.fieldKey as NSString) }
            Text(label(for: column.fieldKey))
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer(minLength: 6)
            Menu {
                Picker("Total", selection: aggregateBinding(index)) {
                    ForEach(SavedReportAggregate.allCases, id: \.self) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
            } label: {
                Text(column.aggregate == .none ? "Σ" : column.aggregate.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(column.aggregate == .none ? MercantisTheme.textMuted : MercantisTheme.brandPrimary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Button {
                removeColumn(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(MercantisTheme.textMuted)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .onDrop(of: [.text], delegate: ColumnDropDelegate(targetIndex: index, draft: $draft, reindex: reindex))
    }

    private var groupByPicker: some View {
        Picker("Group by", selection: groupBinding) {
            Text("No grouping").tag(String?.none)
            ForEach(draft.columns, id: \.fieldKey) { column in
                Text(label(for: column.fieldKey)).tag(Optional(column.fieldKey))
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
    }

    @ViewBuilder
    private var chartConfig: some View {
        Toggle("Show a chart", isOn: chartEnabledBinding)
            .toggleStyle(.switch)
            .controlSize(.small)

        if draft.chart != nil {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Type", selection: chartKindBinding) {
                    ForEach(SavedReportChartKind.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                labelledPicker("Category", selection: chartCategoryBinding, options: draft.columns.map(\.fieldKey))
                labelledPicker("Value", selection: chartValueBinding, options: draft.columns.map(\.fieldKey))

                Picker("Combine", selection: chartAggregateBinding) {
                    ForEach([SavedReportAggregate.sum, .average, .count, .min, .max], id: \.self) {
                        Text($0.label).tag($0)
                    }
                }
                .pickerStyle(.menu)
            }
            .padding(.top, 4)
        }
    }

    private func labelledPicker(_ title: String, selection: Binding<String>, options: [String]) -> some View {
        HStack {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { Text(label(for: $0)).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    // MARK: - Preview pane

    private var previewPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if table == nil && previewError == nil {
                    Text("Add a column to see a preview.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                } else {
                    HubReportOutputView(
                        table: table,
                        chartPoints: chartPoints,
                        chartKind: draft.chart?.kind,
                        errorMessage: previewError
                    )
                }
            }
            .padding(16)
        }
    }

    // MARK: - Mutations

    private func addColumn(_ key: String) {
        guard !chosenKeys.contains(key) else { return }
        draft.columns.append(SavedReportColumn(fieldKey: key, visible: true, order: draft.columns.count))
        reindex()
    }

    private func removeColumn(at index: Int) {
        guard draft.columns.indices.contains(index) else { return }
        let removed = draft.columns.remove(at: index).fieldKey
        if draft.groupByFieldKey == removed { draft.groupByFieldKey = nil }
        if draft.chart?.categoryFieldKey == removed || draft.chart?.valueFieldKey == removed { draft.chart = nil }
        reindex()
    }

    private func reindex() {
        for i in draft.columns.indices { draft.columns[i].order = i }
    }

    private func aggregateBinding(_ index: Int) -> Binding<SavedReportAggregate> {
        Binding(
            get: { draft.columns.indices.contains(index) ? draft.columns[index].aggregate : .none },
            set: { if draft.columns.indices.contains(index) { draft.columns[index].aggregate = $0 } }
        )
    }

    private var groupBinding: Binding<String?> {
        Binding(get: { draft.groupByFieldKey }, set: { draft.groupByFieldKey = $0 })
    }

    private var chartEnabledBinding: Binding<Bool> {
        Binding(
            get: { draft.chart != nil },
            set: { on in
                if on {
                    let keys = draft.columns.map(\.fieldKey)
                    let category = draft.groupByFieldKey ?? keys.first ?? ""
                    let value = keys.first(where: { isNumericColumn($0) }) ?? keys.first ?? ""
                    draft.chart = SavedReportChart(kind: .bar, categoryFieldKey: category, valueFieldKey: value, valueAggregate: .sum)
                } else {
                    draft.chart = nil
                }
            }
        )
    }

    private var chartKindBinding: Binding<SavedReportChartKind> {
        Binding(get: { draft.chart?.kind ?? .bar }, set: { draft.chart?.kind = $0 })
    }
    private var chartCategoryBinding: Binding<String> {
        Binding(get: { draft.chart?.categoryFieldKey ?? "" }, set: { draft.chart?.categoryFieldKey = $0 })
    }
    private var chartValueBinding: Binding<String> {
        Binding(get: { draft.chart?.valueFieldKey ?? "" }, set: { draft.chart?.valueFieldKey = $0 })
    }
    private var chartAggregateBinding: Binding<SavedReportAggregate> {
        Binding(get: { draft.chart?.valueAggregate ?? .sum }, set: { draft.chart?.valueAggregate = $0 })
    }

    // MARK: - Run / save

    private func refresh() {
        guard !draft.columns.isEmpty else { table = nil; chartPoints = []; previewError = nil; return }
        do {
            let typed = try savedReportEngine.executeTyped(savedReport: draft, requestingUserId: userId)
            table = HubReportProjection.build(definition: draft, typed: typed, engine: engine)
            chartPoints = HubReportProjection.chartPoints(definition: draft, typed: typed, engine: engine)
            previewError = nil
        } catch {
            table = nil
            chartPoints = []
            previewError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func saveAndClose() {
        var toSave = draft
        toSave.updatedAt = Date()
        store.save(toSave)
        savedReportEngine.register(toSave)
        dismiss()
    }

    // MARK: - Helpers

    private struct FieldOption: Identifiable { let key: String; let label: String; var id: String { key } }

    private let systemColumns: [(String, String)] = [
        ("id", "Document ID"), ("status", "Status"), ("createdAt", "Created"), ("updatedAt", "Updated"),
    ]

    private func isScalar(_ field: FieldDefinition) -> Bool {
        switch field.type {
        case .table, .image, .attachment: return false
        default: return true
        }
    }

    private func isNumericColumn(_ key: String) -> Bool {
        guard let field = sourceDocType?.fields.first(where: { $0.key == key }) else { return false }
        switch field.type {
        case .number, .decimal, .currency: return true
        default: return false
        }
    }

    private func label(for key: String) -> String {
        if let field = sourceDocType?.fields.first(where: { $0.key == key }) { return field.label }
        if let system = systemColumns.first(where: { $0.0 == key }) { return system.1 }
        return key
    }
}

// MARK: - Drag-to-reorder drop delegate

private struct ColumnDropDelegate: DropDelegate {
    let targetIndex: Int
    @Binding var draft: SavedReportDefinition
    let reindex: () -> Void

    func performDrop(info: DropInfo) -> Bool {
        guard let item = info.itemProviders(for: [.text]).first else { return false }
        item.loadObject(ofClass: NSString.self) { value, _ in
            guard let key = value as? String else { return }
            DispatchQueue.main.async {
                guard let from = draft.columns.firstIndex(where: { $0.fieldKey == key }), from != targetIndex else { return }
                let column = draft.columns.remove(at: from)
                let dest = min(targetIndex, draft.columns.count)
                draft.columns.insert(column, at: dest)
                reindex()
            }
        }
        return true
    }
}

// MARK: - Simple wrapping chip layout

private struct FlowChips<Item: Identifiable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        // A lightweight wrapping layout: rows filled left-to-right.
        FlowLayout(spacing: 6) {
            ForEach(items) { content($0) }
        }
    }
}

/// Minimal flow layout (wrap chips to the next line when they overflow).
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
