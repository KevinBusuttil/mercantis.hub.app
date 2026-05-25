import SwiftUI
import MercantisCore
import MercantisCoreUI

struct RootView: View {
    let engine: DocumentEngine
    let workflowEngine: WorkflowEngine
    let reportEngine: ReportEngine
    let dashboardEngine: DashboardEngine

    @State private var selection: HubMenuItem?
    @State private var collapsedGroups: Set<String> = []

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                MercantisSidebarBrandHeader(
                    title: "Mercantis Hub",
                    subtitle: "Business workspace",
                    systemImage: "shippingbox"
                )
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 8, trailing: 8))
                .listRowSeparator(.hidden)
            }

            ForEach(HubNavigation.allModules) { module in
                Section {
                    ForEach(module.groups.indices, id: \.self) { gIdx in
                        let group = module.groups[gIdx]
                        let key = "\(module.id)::\(gIdx)"
                        if let label = group.label {
                            MercantisSidebarGroupHeader(
                                title: label,
                                isCollapsed: collapsedGroups.contains(key)
                            ) {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    if collapsedGroups.contains(key) {
                                        collapsedGroups.remove(key)
                                    } else {
                                        collapsedGroups.insert(key)
                                    }
                                }
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                        if group.label == nil || !collapsedGroups.contains(key) {
                            ForEach(group.items, id: \.self) { item in
                                MercantisSidebarRow(
                                    title: item.label,
                                    systemImage: item.systemImage,
                                    tone: module.tone,
                                    isSelected: selection == item,
                                    indentation: group.label == nil ? 0 : 6
                                )
                                .tag(item)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        }
                    }
                } header: {
                    MercantisSidebarModuleHeader(
                        title: module.label,
                        systemImage: module.systemImage,
                        tone: module.tone,
                        badge: module.itemCount > 0 ? "\(module.itemCount)" : nil
                    )
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Mercantis Hub")
        .frame(minWidth: 240)
    }

    @ViewBuilder
    private var detail: some View {
        Group {
            switch selection {
            case .docType(let docType):
                HubRecordWorkspaceView(
                    docType: docType,
                    engine: engine,
                    workflowEngine: workflowEngine
                )
            case .report(let id, let label):
                HubReportContainerView(
                    reportId: id,
                    reportLabel: label,
                    engine: engine
                )
            case .dashboard(let id, let label):
                HubDashboardView(
                    dashboardId: id,
                    dashboardTitle: label,
                    dashboardEngine: dashboardEngine
                ) { selected in
                    selection = selected
                }
            case .none:
                HubHomeView(engine: engine) { item in
                    selection = item
                }
            }
        }
        .navigationTitle(selection?.label ?? "Mercantis Hub")
    }
}

/// Wraps Core's `RecordCollectionHostView` so a sidebar DocType click opens
/// a list/browse/detail workspace rather than a blank create form. Selecting
/// an existing row delegates to `HubDocumentEditor`, which carries the full
/// Hub lifecycle (Save/Submit/Cancel/Amend + workflow transitions).
private struct HubRecordWorkspaceView: View {
    let docType: DocType
    let engine: DocumentEngine
    let workflowEngine: WorkflowEngine

    @State private var documents: [Document] = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }
            RecordCollectionHostView(
                preferenceKey: "hub.\(docType.id)",
                docType: docType,
                workspaceTitle: pluralizedTitle(for: docType),
                workspaceSubtitle: "Manage \(docType.name) records",
                workspaceSymbol: symbol(for: docType),
                documents: documents,
                configuration: RecordCollectionViewConfiguration(
                    supportedViewModes: [.list, .browse, .detail],
                    // Default to browse so the editor is visible the moment
                    // a row is selected; otherwise users in .list mode have
                    // no clear path from "row clicked" to "fields visible".
                    defaultViewMode: .browse
                ),
                primaryCreateActionTitle: "New \(docType.name)",
                onCreateDocument: { makeDraftDocument() },
                onSaveDocument: { document in
                    _ = try engine.save(document)
                    reloadDocumentsSafely()
                },
                linkSearchProvider: { targetDocType, _ in
                    (try? engine.list(docType: targetDocType)) ?? []
                },
                childDocTypeProvider: { HubManifest.docType(for: $0) },
                detailEditor: { binding in
                    AnyView(
                        HubDocumentEditor(
                            docType: docType,
                            engine: engine,
                            workflowEngine: workflowEngine,
                            document: binding,
                            onPersist: { reloadDocumentsSafely() },
                            onDelete: { documentId in
                                try engine.delete(docType: docType.id, id: documentId)
                                reloadDocumentsSafely()
                            }
                        )
                    )
                }
            )
        }
        .onAppear { reloadDocumentsSafely() }
    }

    private func reloadDocumentsSafely() {
        do {
            documents = try engine.list(docType: docType.id)
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func makeDraftDocument() -> Document {
        let now = Date()
        let initialStatus = HubWorkflows
            .workflow(forDocTypeId: docType.id)?
            .states
            .first(where: { $0.isDefault })?
            .name ?? ""

        return Document(
            id: "",
            docType: docType.id,
            company: "",
            status: initialStatus,
            createdAt: now,
            updatedAt: now,
            syncVersion: 0,
            syncState: .local,
            fields: [:],
            children: [:]
        )
    }

    private func pluralizedTitle(for docType: DocType) -> String {
        let name = docType.name
        let lower = name.lowercased()
        if lower.hasSuffix("s") || lower.hasSuffix("ch") || lower.hasSuffix("sh") || lower.hasSuffix("x") {
            return "\(name)es"
        }
        if lower.hasSuffix("y"),
           let last = name.dropLast().last,
           !"aeiou".contains(last.lowercased()) {
            return "\(name.dropLast())ies"
        }
        return "\(name)s"
    }

    private func symbol(for docType: DocType) -> String {
        switch docType.id {
        case "Customer":        return "person.2"
        case "Contact":         return "person.crop.circle"
        case "Address":         return "mappin.and.ellipse"
        case "Lead":            return "person.fill.questionmark"
        case "Supplier":        return "shippingbox"
        case "Item":            return "cube.box"
        case "Quotation":       return "doc.text.below.ecg"
        case "SalesOrder":      return "cart"
        case "SalesInvoice":    return "doc.text"
        case "PurchaseOrder":   return "bag"
        case "PurchaseInvoice": return "bag.badge.plus"
        case "JournalEntry":    return "book.pages"
        case "PaymentEntry":    return "creditcard"
        case "StockEntry":      return "tray.full"
        case "Warehouse":       return "building.2"
        case "Account":         return "list.bullet.rectangle"
        case "Currency":        return "dollarsign.circle"
        case "PriceList":       return "tag"
        default:                return "rectangle.stack"
        }
    }
}

/// Focused per-record editor that preserves the full Hub lifecycle:
/// Save / Submit / Cancel / Amend + workflow transitions. Used as the
/// workspace detail editor and bound to the host's selected document.
private struct HubDocumentEditor: View {
    let docType: DocType
    let engine: DocumentEngine
    let workflowEngine: WorkflowEngine
    @Binding var document: Document
    let onPersist: () -> Void
    /// Deletes the record with the supplied id. Throws are surfaced in the
    /// editor's error row.
    let onDelete: (String) throws -> Void

    @State private var lastSavedID: String?
    @State private var lastSavedAt: Date?
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false

    private var workflow: WorkflowDefinition? {
        HubWorkflows.workflow(forDocTypeId: docType.id)
    }
    private let evaluator = ExpressionEvaluator()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                lifecycleHeader
                GenericFormView(
                    docType: docType,
                    document: $document,
                    linkSearchProvider: { targetDocType, _ in
                        (try? engine.list(docType: targetDocType)) ?? []
                    },
                    childDocTypeProvider: { HubManifest.docType(for: $0) }
                )
                actionRow
                statusRow
            }
            .padding()
        }
        .frame(minWidth: 480, minHeight: 400)
        .confirmationDialog(
            "Delete this \(docType.name)?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete \(docType.name)", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently remove \(document.id.isEmpty ? "this draft" : document.id). This action cannot be undone.")
        }
    }

    /// Saved/error indicator. Sits beneath the action row so users get
    /// explicit, visible feedback after every save — the previous
    /// inline "Saved as X" line was easy to miss.
    @ViewBuilder
    private var statusRow: some View {
        HStack(spacing: 8) {
            if let error = errorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(error)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else if let lastSavedAt {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Saved \(relativeSaved(lastSavedAt))")
                    .foregroundStyle(.secondary)
                if let lastSavedID, !lastSavedID.isEmpty {
                    Text("· \(lastSavedID)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .font(.callout)
    }

    private func relativeSaved(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let interval = Date().timeIntervalSince(date)
        if interval < 2 { return "just now" }
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Lifecycle header

    private var lifecycleHeader: some View {
        HStack(spacing: 12) {
            statusBadge
            if let workflow {
                Text(workflow.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !document.id.isEmpty {
                Text("ID  \(document.id)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusBadge: some View {
        let docStatusLabel: String
        let tint: Color
        switch document.docStatus {
        case 1:
            docStatusLabel = "Submitted"
            tint = .blue
        case 2:
            docStatusLabel = "Cancelled"
            tint = .red
        default:
            docStatusLabel = "Draft"
            tint = .gray
        }

        let workflowLabel: String? = {
            guard !document.status.isEmpty,
                  document.status.lowercased() != docStatusLabel.lowercased() else { return nil }
            return document.status
        }()

        return HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text(docStatusLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            if let workflowLabel {
                Text("· \(workflowLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.12), in: Capsule())
    }

    // MARK: - Action row

    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: 8) {
            // Save is always offered while the document is editable.
            if document.docStatus == 0 {
                Button("Save") { save() }
                    .keyboardShortcut("s", modifiers: [.command])
                    .buttonStyle(.borderedProminent)
            }

            // Submit appears when the DocType is submittable and the
            // document is Draft.
            if docType.isSubmittable, document.docStatus == 0, !document.id.isEmpty {
                Button("Submit") { submit() }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .buttonStyle(.bordered)
            }

            // Cancel appears when the document is Submitted.
            if docType.isSubmittable, document.docStatus == 1 {
                Button("Cancel", role: .destructive) { cancel() }
            }

            // Amend appears when the document has been Cancelled.
            if docType.isSubmittable, document.docStatus == 2 {
                Button("Amend") { amend() }
                    .buttonStyle(.borderedProminent)
            }

            // Workflow transition buttons surface every status transition
            // available from the current state for the System Manager role.
            ForEach(availableWorkflowTransitions, id: \.action) { transition in
                if shouldOfferWorkflowButton(transition) {
                    Button(transition.action) { runWorkflow(transition) }
                        .buttonStyle(.bordered)
                }
            }

            Spacer()

            // Delete is allowed for persisted Draft (0) and Cancelled (2)
            // documents. Submitted (1) documents must be cancelled first;
            // the engine enforces this and would throw `cannotDeleteSubmitted`.
            if !document.id.isEmpty, document.docStatus != 1 {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .keyboardShortcut(.delete, modifiers: [.command])
            }
        }
    }

    /// Submit / Cancel / Amend already run through `DocumentEngine`; the
    /// workflow transition buttons cover everything else (e.g. "Mark as
    /// Paid", "Mark as Lost").
    private func shouldOfferWorkflowButton(_ transition: WorkflowTransition) -> Bool {
        let lifecycleActions: Set<String> = ["Submit", "Cancel"]
        return !lifecycleActions.contains(transition.action)
    }

    private var availableWorkflowTransitions: [WorkflowTransition] {
        guard let workflow else { return [] }
        return (try? workflowEngine.availableTransitions(
            workflow: workflow,
            currentState: document.status,
            userRoles: ["System Manager"],
            document: document,
            expressionEvaluator: evaluator
        )) ?? []
    }

    // MARK: - Engine actions

    private func save() {
        do {
            let saved = try engine.save(document)
            // `DocumentEngine.save` returns the input with its ORIGINAL
            // `updatedAt` (optimistic-concurrency contract: callers must
            // refetch to see the persisted timestamp). Without this refetch
            // the binding still holds the stale value and the very next
            // save throws `concurrencyConflict` — which surfaces to the
            // user as "Save doesn't seem to do anything".
            refreshBinding(toID: saved.id)
            markSaved(id: saved.id)
            onPersist()
        } catch {
            errorMessage = humanReadable(error)
        }
    }

    private func submit() {
        do {
            // 1. Persist any pending edits.
            _ = try engine.save(document)
            if let refreshed = try engine.fetch(docType: docType.id, id: document.id) {
                document = refreshed
            }
            // 2. Flip docStatus 0 → 1 through Core's submit pipeline so
            //    immutability + audit + workflow-history rows fire.
            try engine.submit(&document)
            // 3. Run the workflow's Submit transition so Document.status
            //    moves Draft → Submitted (or whichever first transition the
            //    workflow declares from the initial state).
            if let workflow,
               let transition = (try? workflowEngine.availableTransitions(
                    workflow: workflow,
                    currentState: "Draft",
                    userRoles: ["System Manager"],
                    document: document,
                    expressionEvaluator: evaluator
                ))?.first(where: { $0.action == "Submit" }) {
                _ = try workflowEngine.transition(
                    document: &document,
                    workflow: workflow,
                    action: transition.action,
                    userRoles: ["System Manager"],
                    expressionEvaluator: evaluator,
                    userId: "kevin"
                )
                _ = try engine.save(document)
            }
            refreshBinding(toID: document.id)
            markSaved(id: document.id)
            onPersist()
        } catch {
            errorMessage = humanReadable(error)
        }
    }

    private func cancel() {
        do {
            try engine.cancel(&document)
            // Mirror the lifecycle change in the workflow status string
            // when a "Cancel" workflow transition exists.
            if let workflow,
               (try? workflowEngine.availableTransitions(
                    workflow: workflow,
                    currentState: document.status,
                    userRoles: ["System Manager"],
                    document: document,
                    expressionEvaluator: evaluator
                ))?.contains(where: { $0.action == "Cancel" }) ?? false {
                _ = try workflowEngine.transition(
                    document: &document,
                    workflow: workflow,
                    action: "Cancel",
                    userRoles: ["System Manager"],
                    expressionEvaluator: evaluator,
                    userId: "kevin"
                )
                _ = try engine.save(document)
            }
            refreshBinding(toID: document.id)
            markSaved(id: document.id)
            onPersist()
        } catch {
            errorMessage = humanReadable(error)
        }
    }

    private func amend() {
        do {
            let amended = try engine.amend(document)
            refreshBinding(toID: amended.id, fallback: amended)
            markSaved(id: amended.id)
            onPersist()
        } catch {
            errorMessage = humanReadable(error)
        }
    }

    private func runWorkflow(_ transition: WorkflowTransition) {
        guard let workflow else { return }
        do {
            _ = try workflowEngine.transition(
                document: &document,
                workflow: workflow,
                action: transition.action,
                userRoles: ["System Manager"],
                expressionEvaluator: evaluator,
                userId: "kevin"
            )
            _ = try engine.save(document)
            refreshBinding(toID: document.id)
            markSaved(id: document.id)
            onPersist()
        } catch {
            errorMessage = humanReadable(error)
        }
    }

    private func performDelete() {
        guard !document.id.isEmpty else { return }
        do {
            try onDelete(document.id)
            // The host's reload drops this row; once it's no longer in the
            // documents array, RecordCollectionHostView clears its own
            // selection. Until then keep the editor on a tidy state.
            errorMessage = nil
            lastSavedAt = nil
            lastSavedID = nil
        } catch {
            errorMessage = humanReadable(error)
        }
    }

    // MARK: - Helpers

    /// Re-reads the persisted document so the in-memory binding carries
    /// the latest `updatedAt` and any engine-applied side-effects (naming
    /// series, computed fields, etc.).
    private func refreshBinding(toID id: String, fallback: Document? = nil) {
        if !id.isEmpty,
           let refreshed = try? engine.fetch(docType: docType.id, id: id) {
            document = refreshed
        } else if let fallback {
            document = fallback
        }
    }

    private func markSaved(id: String) {
        lastSavedID = id
        lastSavedAt = Date()
        errorMessage = nil
    }

    private func humanReadable(_ error: Error) -> String {
        let description = (error as NSError).localizedDescription
        if description.isEmpty || description == "The operation couldn’t be completed." {
            return String(describing: error)
        }
        return description
    }
}
