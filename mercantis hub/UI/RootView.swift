import SwiftUI
import MercantisCore
import MercantisCoreUI

struct RootView: View {
    let engine: DocumentEngine
    let workflowEngine: WorkflowEngine

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
            ForEach(HubNavigation.allModules) { module in
                Section {
                    ForEach(module.groups.indices, id: \.self) { gIdx in
                        let group = module.groups[gIdx]
                        let key = "\(module.id)::\(gIdx)"
                        if let label = group.label {
                            groupHeader(label: label, key: key)
                        }
                        if group.label == nil || !collapsedGroups.contains(key) {
                            ForEach(group.items, id: \.self) { item in
                                Label(item.label, systemImage: item.systemImage)
                            }
                        }
                    }
                } header: {
                    Label(module.label, systemImage: module.systemImage)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Mercantis Hub")
        .frame(minWidth: 220)
    }

    private func groupHeader(label: String, key: String) -> some View {
        let isCollapsed = collapsedGroups.contains(key)
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                if isCollapsed {
                    collapsedGroups.remove(key)
                } else {
                    collapsedGroups.insert(key)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var detail: some View {
        Group {
            switch selection {
            case .docType(let docType):
                HubDocTypeView(
                    docType: docType,
                    engine: engine,
                    workflowEngine: workflowEngine
                )
            case .report(_, let label):
                reportPlaceholder(label: label)
            case .dashboard(_, let label):
                dashboardPlaceholder(label: label)
            case .none:
                HubHomeView(engine: engine) { item in
                    selection = item
                }
            }
        }
        .navigationTitle(selection?.label ?? "Mercantis Hub")
    }

    private func reportPlaceholder(label: String) -> some View {
        ContentUnavailableView(
            label,
            systemImage: "chart.bar.doc.horizontal",
            description: Text("Hub-side report declarations are next on the Wall 9 list. The engine ships GenericReportView in MercantisCoreUI; only the Hub-side ReportDefinition wiring is left.")
        )
    }

    private func dashboardPlaceholder(label: String) -> some View {
        ContentUnavailableView(
            label,
            systemImage: "rectangle.grid.2x2",
            description: Text("DashboardEngine resolves widget tiles into typed data; a SwiftUI consumer of DashboardResult lands with the upcoming MercantisCoreUI work.")
        )
    }
}

private struct HubDocTypeView: View {
    let docType: DocType
    let engine: DocumentEngine
    let workflowEngine: WorkflowEngine

    @State private var document: Document
    @State private var lastSavedID: String?
    @State private var errorMessage: String?

    private let workflow: WorkflowDefinition?
    private let evaluator = ExpressionEvaluator()

    init(docType: DocType, engine: DocumentEngine, workflowEngine: WorkflowEngine) {
        self.docType = docType
        self.engine = engine
        self.workflowEngine = workflowEngine
        self.workflow = HubWorkflows.workflow(forDocTypeId: docType.id)

        let now = Date()
        let initialStatus = workflow?.states.first(where: { $0.isDefault })?.name ?? ""
        self._document = State(initialValue: Document(
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
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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
                if let id = lastSavedID {
                    Text("Saved as \(id)").font(.callout).foregroundStyle(.secondary)
                }
                if let error = errorMessage {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
            }
            .padding()
        }
        .frame(minWidth: 480, minHeight: 400)
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
            }

            // Submit appears when the DocType is submittable and the
            // document is Draft.
            if docType.isSubmittable, document.docStatus == 0, !document.id.isEmpty {
                Button("Submit") { submit() }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .buttonStyle(.borderedProminent)
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
            document = saved
            lastSavedID = saved.id
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func submit() {
        do {
            // 1. Persist any pending edits and refresh updatedAt to satisfy
            //    optimistic concurrency.
            document = try engine.save(document)
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
                document = try engine.save(document)
            }
            lastSavedID = document.id
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
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
                document = try engine.save(document)
            }
            lastSavedID = document.id
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func amend() {
        do {
            let amended = try engine.amend(document)
            document = amended
            lastSavedID = amended.id
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
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
            document = try engine.save(document)
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }
}
