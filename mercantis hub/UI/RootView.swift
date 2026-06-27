import SwiftUI
import MercantisCore
import MercantisCoreUI
#if os(macOS)
import AppKit
#endif

struct RootView: View {
    let engine: DocumentEngine
    let workflowEngine: WorkflowEngine
    let reportEngine: ReportEngine
    let dashboardEngine: DashboardEngine
    let customFieldStore: CustomFieldStore
    /// User-saved custom report variants (Hub user report customisation).
    @ObservedObject var savedReportStore: HubSavedReportStore
    /// Core engine used to run from-scratch custom reports.
    let savedReportEngine: SavedReportEngine
    /// Shared with the Settings (⌘,) window so toggling a preset / module
    /// there updates the sidebar live.
    @ObservedObject var visibility: HubVisibilitySettings
    /// Shared attachment manager for the Document Capture flow.
    let attachmentManager: AttachmentManager
    /// Serverless cross-device company sync engine.
    @ObservedObject var companySync: CompanySync

    @State private var selection: HubMenuItem?
    /// Record id to pre-select after a cross-DocType "open related" navigation
    /// (e.g. tapping a Sales Order from a Quotation's Related card). Consumed by
    /// the destination workspace, then cleared when it makes its selection.
    @State private var pendingOpenRecordID: String?
    @State private var collapsedGroups: Set<String> = []
    /// The capture currently being reviewed (drives the Capture flow's
    /// list ⇄ review sub-routing).
    @State private var reviewCaptureId: String?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .sheet(isPresented: Binding(
            get: { !visibility.onboardingComplete },
            set: { presented in if !presented { visibility.onboardingComplete = true } }
        )) {
            HubOnboardingView(engine: engine, settings: visibility)
        }
    }

    private var visibleModules: [HubModule] {
        HubNavigation.allModules.filter { visibility.isModuleVisible($0) }
    }

    private let customReportsItem: HubMenuItem = .customReports(label: "Custom Reports")

    private var activeModuleID: String? {
        HubNavigation.moduleID(for: selection, settings: visibility) ?? visibleModules.first?.id
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

            // Persistent way back to the overview from anywhere.
            Section {
                Button {
                    selection = nil
                } label: {
                    MercantisSidebarRow(
                        title: "Home",
                        systemImage: "house",
                        tone: .neutral,
                        isSelected: selection == nil,
                        indentation: 0
                    )
                }
                .buttonStyle(.plain)
                .listRowBackground(selection == nil ? MercantisTheme.tableRowSelection.opacity(0.82) : Color.clear)
                .listRowSeparator(.hidden)

                // Cross-module Custom Reports home. Saved report variants
                // span modules, so they get a single durable entry here
                // rather than living under any one module.
                Button {
                    selection = customReportsItem
                } label: {
                    MercantisSidebarRow(
                        title: "Custom Reports",
                        systemImage: "slider.horizontal.3",
                        tone: .neutral,
                        isSelected: selection == customReportsItem,
                        indentation: 0
                    )
                }
                .buttonStyle(.plain)
                .listRowBackground(selection == customReportsItem ? MercantisTheme.tableRowSelection.opacity(0.82) : Color.clear)
                .listRowSeparator(.hidden)
            }

            ForEach(visibleModules) { module in
                let groups = module.visibleGroups(visibility)
                Section {
                    Button {
                        if let first = module.firstVisibleItem(visibility) {
                            selection = first
                        }
                    } label: {
                        MercantisSidebarModuleHeader(
                            title: module.label,
                            systemImage: module.systemImage,
                            tone: module.tone,
                            badge: module.businessBadge
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    if activeModuleID == module.id {
                        ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                            // Key the collapse state by label so it stays stable
                            // when advanced groups appear / disappear.
                            let key = "\(module.id)::\(group.label ?? "ungrouped")"
                            if let label = group.label {
                                MercantisSidebarGroupHeader(
                                    title: label,
                                    isCollapsed: collapsedGroups.contains(key)
                                ) {
                                    if collapsedGroups.contains(key) {
                                        collapsedGroups.remove(key)
                                    } else {
                                        collapsedGroups.insert(key)
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
                                    .listRowBackground(selection == item ? MercantisTheme.tableRowSelection.opacity(0.82) : Color.clear)
                                    .listRowSeparator(.hidden)
                                }
                            }
                        }
                    }
                }
            }

            // Settings opens the standard macOS Settings window (⌘,);
            // business type, optional modules, and advanced view all live
            // there rather than cluttering the navigation surface.
            Section {
                SettingsLink {
                    MercantisSidebarRow(
                        title: "Settings",
                        systemImage: "gearshape",
                        tone: .neutral,
                        isSelected: false,
                        indentation: 0
                    )
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
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
            case .docType(let docType, _):
                HubRecordWorkspaceView(
                    docType: docType,
                    engine: engine,
                    workflowEngine: workflowEngine,
                    customFieldStore: customFieldStore,
                    initialRecordID: pendingOpenRecordID,
                    onOpenRelatedRecord: { docTypeId, recordId in
                        openRelatedRecord(docTypeId: docTypeId, recordId: recordId)
                    },
                    onConsumeInitialRecord: { pendingOpenRecordID = nil }
                )
                // Force a fresh view identity per DocType so SwiftUI doesn't
                // reuse the previous workspace's @State (`documents`,
                // `customFields`) when the user jumps Customer → Item.
                // Without this, the records of whichever DocType was loaded
                // first stick around in every workspace.
                .id("docType:\(docType.id)")
            case .report(let id, let label):
                HubReportContainerView(
                    reportId: id,
                    reportLabel: label,
                    engine: engine,
                    savedReportStore: savedReportStore,
                    visibility: visibility
                )
                .id("report:\(id)")
            case .customReports:
                HubCustomReportsView(
                    store: savedReportStore,
                    engine: engine,
                    savedReportEngine: savedReportEngine,
                    visibility: visibility
                )
                .id("custom-reports")
            case .dashboard(let id, let label):
                HubDashboardView(
                    dashboardId: id,
                    dashboardTitle: label,
                    dashboardEngine: dashboardEngine
                ) { selected in
                    selection = selected
                }
                .id("dashboard:\(id)")
            case .flow(let id, _, _):
                flowDetail(id: id)
            case .none:
                HubHomeView(engine: engine) { item in
                    selection = item
                }
            }
        }
        .navigationTitle(selection?.label ?? "Mercantis Hub")
    }

    /// Navigate to another DocType's record (lineage "Related" links). Stashes
    /// the target id for the destination workspace to pre-select, then switches
    /// the sidebar selection — the per-DocType view identity gives that
    /// workspace a fresh `RecordCollectionHostView` that consumes the id.
    private func openRelatedRecord(docTypeId: String, recordId: String) {
        guard let target = HubManifest.docType(for: docTypeId) else { return }
        pendingOpenRecordID = recordId
        selection = .docType(target)
    }

    /// Resolve a `.flow` nav id to its bespoke screen. Covers POS / guided
    /// payments, Document Capture, Company Sync, and the operational screens.
    @ViewBuilder
    private func flowDetail(id: String) -> some View {
        if id == "pos-checkout" {
            HubPOSCheckoutView(engine: engine, workflowEngine: workflowEngine)
                .id("flow:\(id)")
        } else if let mode = guidedPaymentMode(for: id) {
            GuidedPaymentFlowView(mode: mode, engine: engine, workflowEngine: workflowEngine)
                .id("flow:\(id)")

        // ── Document Capture (ADR-049) ──
        } else if id == Capture.Flow.captures {
            if let captureId = reviewCaptureId {
                CaptureReviewView(
                    engine: engine,
                    attachments: attachmentManager,
                    captureId: captureId,
                    onDraftCreated: { _ in
                        reviewCaptureId = nil
                        if let invoice = HubManifest.docType(for: "PurchaseInvoice") {
                            selection = .docType(invoice)
                        }
                    }
                )
                .id("flow:capture-review:\(captureId)")
            } else {
                CapturesView(
                    engine: engine,
                    userRoles: ["System Manager"],
                    onScan: {
                        selection = .flow(id: Capture.Flow.scan, label: "Scan Receipt",
                                          systemImage: "doc.text.viewfinder")
                    },
                    onOpenAISettings: {
                        selection = .flow(id: Capture.Flow.aiSettings, label: "Smart Capture (AI)",
                                          systemImage: "sparkles")
                    },
                    onReview: { capId in
                        reviewCaptureId = capId
                        selection = .flow(id: Capture.Flow.captures, label: "Captures",
                                          systemImage: "tray.full")
                    }
                )
                .id("flow:capture-list")
            }
        } else if id == Capture.Flow.scan {
            ScanReceiptView(
                engine: engine,
                attachments: attachmentManager,
                onCaptured: { capId in
                    reviewCaptureId = capId
                    selection = .flow(id: Capture.Flow.captures, label: "Captures",
                                      systemImage: "tray.full")
                }
            )
            .id("flow:capture-scan")
        } else if id == Capture.Flow.aiSettings {
            CaptureAISettingsView()
                .id("flow:capture-ai-settings")

        // ── Company Sync (ADR-047) ──
        } else if id == "company-sync" {
            CompanySyncView(sync: companySync)
                .id("flow:company-sync")

        // ── Operational screens ──
        } else if id == "work-order-complete" {
            WorkOrderCompleteView(engine: engine, workflowEngine: workflowEngine)
                .id("flow:\(id)")
        } else if id == "driver-today" {
            DriverTodayView(engine: engine).id("flow:\(id)")
        } else if id == "delivery-route" {
            DeliveryRouteView(engine: engine).id("flow:\(id)")
        } else if id == "customer-account" {
            CustomerAccountView(engine: engine).id("flow:\(id)")
        } else if id == "low-stock" {
            LowStockView(engine: engine).id("flow:\(id)")
        } else if id == "sales-orders" {
            SalesOrdersView(engine: engine).id("flow:\(id)")
        } else {
            HubHomeView(engine: engine) { item in selection = item }
        }
    }

    /// Map a guided-flow nav id to its concrete payment mode.
    private func guidedPaymentMode(for id: String) -> GuidedPaymentMode? {
        switch id {
        case "guided-receive-payment": return .receive
        case "guided-pay-supplier":    return .pay
        default:                       return nil
        }
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
    let customFieldStore: CustomFieldStore
    /// A record to pre-select when this workspace opens (cross-DocType "open
    /// related" navigation). Consumed once, then cleared via `onConsumeInitialRecord`.
    var initialRecordID: String? = nil
    /// Request navigation to another DocType's record (lineage links).
    var onOpenRelatedRecord: ((String, String) -> Void)? = nil
    /// Clears the parent's pending pre-selection once it has been applied.
    var onConsumeInitialRecord: (() -> Void)? = nil

    @State private var documents: [Document] = []
    @State private var customFields: [CustomField] = []
    @State private var errorMessage: String?
    /// Flipped by the File ▸ New (⌘N) menu command to open the create flow
    /// for this workspace's DocType.
    @State private var createTrigger = false
    @State private var showCollectionWorkspace = false

    /// Whether this DocType uses single-record / settings mode.
    private var isSingleRecord: Bool {
        HubSingleRecordPolicy.isSingleRecord(docType.id)
    }

    var body: some View {
        let copy = HubWorkspaceCopyPolicy.copy(for: docType)

        VStack(spacing: 0) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(MercantisTheme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(MercantisTheme.fillSoft(for: .danger), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal)
            }
            if isSingleRecord {
                singleRecordBody(copy: copy)
            } else if documents.isEmpty && !showCollectionWorkspace {
                zeroRecordWorkspaceEmptyState(copy: copy)
            } else {
                multiRecordCollectionView(copy: copy)
            }
        }
        // Publish a context-aware "New <DocType>" action so the File ▸ New
        // (⌘N) menu command targets this workspace while it's on screen.
        // For single-record DocTypes, suppress the action once a record exists.
        .focusedSceneValue(\.newRecordAction, newRecordActionValue(copy: copy))
        .onAppear {
            reloadDocumentsSafely()
            reloadCustomFieldsSafely()
            showCollectionWorkspace = !documents.isEmpty
        }
        .onChange(of: documents.count) { _, count in
            if count > 0 {
                showCollectionWorkspace = true
            } else if !createTrigger {
                showCollectionWorkspace = false
            }
        }
    }

    // MARK: - Single-record settings workspace

    @ViewBuilder
    private func singleRecordBody(copy: HubWorkspaceCopy) -> some View {
        if let existing = documents.first {
            // A record exists — show the editor directly.
            singleRecordEditor(document: existing, copy: copy)
        } else if createTrigger {
            // User initiated creation — show a fresh draft editor.
            singleRecordCreateFlow(copy: copy)
        } else {
            // No record yet — show a settings-style empty state.
            zeroRecordWorkspaceEmptyState(copy: copy)
        }
    }

    private func singleRecordEditor(document: Document, copy: HubWorkspaceCopy) -> some View {
        SingleRecordSettingsEditor(
            docType: docType,
            engine: engine,
            workflowEngine: workflowEngine,
            customFieldStore: customFieldStore,
            initialDocument: document,
            copy: copy,
            onReload: { reloadDocumentsSafely() }
        )
    }

    private func singleRecordCreateFlow(copy: HubWorkspaceCopy) -> some View {
        SingleRecordSettingsEditor(
            docType: docType,
            engine: engine,
            workflowEngine: workflowEngine,
            customFieldStore: customFieldStore,
            initialDocument: makeDraftDocument(),
            copy: copy,
            onReload: { reloadDocumentsSafely() }
        )
    }

    // MARK: - Multi-record collection workspace

    private func multiRecordCollectionView(copy: HubWorkspaceCopy) -> some View {
        RecordCollectionHostView(
            preferenceKey: "hub.\(docType.id)",
            docType: docType,
            workspaceTitle: copy.title,
            workspaceSubtitle: copy.subtitle,
            workspaceSymbol: symbol(for: docType),
            documents: documents,
            configuration: RecordCollectionViewConfiguration(
                supportedViewModes: [.list, .browse, .detail],
                // Default to browse so the editor is visible the moment
                // a row is selected; otherwise users in .list mode have
                // no clear path from "row clicked" to "fields visible".
                defaultViewMode: .browse
            ),
            primaryCreateActionTitle: copy.primaryActionTitle,
            onCreateDocument: { makeDraftDocument() },
            onSaveDocument: { document in
                let withDefaults = HubBusinessProfileDefaultsPolicy.prepareForFirstSave(
                    document,
                    docType: docType,
                    businessProfile: currentBusinessProfile()
                )
                // Phase 2 (VAT): recompute tax rows + tax-aware totals from
                // the line items and resolved tax codes on every save.
                let prepared = HubTaxCalculationPolicy.applied(
                    to: withDefaults,
                    docType: docType,
                    engine: engine
                )
                let existingDocuments = try engine.list(docType: docType.id)
                try HubFiscalYearValidationPolicy.validate(prepared, existingDocuments: existingDocuments)
                let saved = try engine.save(prepared)
                reloadDocumentsSafely()
                // Refetch so the host's binding picks up the persisted
                // `updatedAt`; without this the next save throws
                // `concurrencyConflict` (optimistic-concurrency contract).
                return (try? engine.fetch(docType: docType.id, id: saved.id)) ?? saved
            },
            onDeleteDocument: { document in
                try engine.delete(docType: docType.id, id: document.id)
                reloadDocumentsSafely()
            },
            customFields: customFields,
            onAddCustomField: { field in
                try customFieldStore.add(field)
                reloadCustomFieldsSafely()
            },
            onUpdateCustomField: { field in
                try customFieldStore.update(field)
                reloadCustomFieldsSafely()
            },
            onRemoveCustomField: { id in
                try customFieldStore.remove(id: id)
                reloadCustomFieldsSafely()
            },
            initialSelectedDocumentID: initialRecordID,
            onSelectionChange: { _ in
                // The pending pre-selection has been applied (or the user picked
                // another row); clear it so it can't re-fire on a later visit.
                if initialRecordID != nil { onConsumeInitialRecord?() }
            },
            externalCreateTrigger: $createTrigger,
            linkSearchProvider: { targetDocType, _ in
                (try? engine.list(docType: targetDocType)) ?? []
            },
            linkResolveProvider: { targetDocType, id in
                try? engine.fetch(docType: targetDocType, id: id)
            },
            childDocTypeProvider: { HubManifest.docType(for: $0) },
            linkCreateProvider: { targetDocType in
                let now = Date()
                return Document(
                    id: "", docType: targetDocType, company: "", status: "",
                    createdAt: now, updatedAt: now, syncVersion: 0, syncState: .local,
                    fields: [:], children: [:]
                )
            },
            linkCommitProvider: { document in
                let saved = try engine.save(document)
                return (try? engine.fetch(docType: document.docType, id: saved.id)) ?? saved
            },
            detailEditor: { composedDocType, binding in
                AnyView(
                    HubDocumentEditor(
                        // composedDocType already has any custom fields merged
                        // into `.fields`, so the form renders end-user
                        // additions alongside the manifest-declared fields.
                        docType: composedDocType,
                        engine: engine,
                        workflowEngine: workflowEngine,
                        document: binding,
                        onPersist: { reloadDocumentsSafely() },
                        onOpenRelatedRecord: onOpenRelatedRecord
                    )
                )
            },
            listViews: HubListViews.views(for: docType.id),
            displayPolicy: HubWorkflowDisplayPolicy.policy
        )
        .controlSize(.small)
    }

    // MARK: - New record action

    private func newRecordActionValue(copy: HubWorkspaceCopy) -> NewRecordAction {
        // For single-record DocTypes, suppress ⌘N once a record exists.
        if isSingleRecord && !documents.isEmpty {
            return NewRecordAction(label: primaryNewRecordLabel(from: copy)) { }
        }
        return NewRecordAction(label: primaryNewRecordLabel(from: copy)) {
            showCollectionWorkspace = true
            createTrigger = true
        }
    }

    private func zeroRecordWorkspaceEmptyState(copy: HubWorkspaceCopy) -> some View {
        VStack(spacing: 14) {
            Image(systemName: symbol(for: docType))
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(MercantisTheme.brandPrimary)
                .padding(10)
                .background(MercantisTheme.brandPrimarySoft, in: RoundedRectangle(cornerRadius: 12))

            Text(copy.emptyStateTitle)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(MercantisTheme.textPrimary)

            Text(copy.emptyStateMessage)
                .font(.callout)
                .foregroundStyle(MercantisTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)

            if let hint = copy.emptyStateHint {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(MercantisTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }

            Button(copy.primaryActionTitle) {
                showCollectionWorkspace = true
                createTrigger = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MercantisTheme.appBackground)
    }

    private func reloadCustomFieldsSafely() {
        do {
            customFields = try customFieldStore.list(forDocType: docType.id)
        } catch {
            errorMessage = String(describing: error)
        }
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

        let draft = Document(
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

        return HubBusinessProfileDefaultsPolicy.applyDraftDefaults(
            to: draft,
            docType: docType,
            businessProfile: currentBusinessProfile()
        )
    }

    private func currentBusinessProfile() -> Document? {
        (try? engine.list(docType: "Company"))?.first
    }

    private func primaryNewRecordLabel(from copy: HubWorkspaceCopy) -> String {
        if copy.primaryActionTitle.hasPrefix("New ") {
            return String(copy.primaryActionTitle.dropFirst(4))
        }
        return copy.primaryActionTitle
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

/// Phase 3 — read-only stock-on-hand summary shown on the Item workspace.
/// Reads materialised Stock Balance (Bin) rows via `StockBalanceService`
/// so the figures match the Stock on Hand report and POS/Delivery lookups.
private struct ItemStockSummaryView: View {
    let itemID: String
    let engine: DocumentEngine

    @State private var balances: [StockBalanceCalculator.Balance] = []
    @State private var loaded = false

    private var totalQty: Double { balances.reduce(0) { $0 + $1.actualQty } }

    var body: some View {
        MercantisInspectorCard("Stock on Hand", systemImage: "shippingbox") {
            if balances.isEmpty {
                Text(loaded ? "No stock recorded for this item yet." : "Loading…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(balances.enumerated()), id: \.offset) { index, balance in
                        MercantisInspectorRow(
                            warehouseName(balance.warehouse),
                            value: formatQty(balance.actualQty),
                            isNumeric: true
                        )
                        Divider()
                    }
                    MercantisInspectorRow("Total", value: formatQty(totalQty), isNumeric: true)
                }
            }
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        let service = StockBalanceService(engine: engine)
        balances = ((try? service.balances(forItem: itemID)) ?? [])
            .filter { $0.actualQty != 0 || $0.lastMovementDate != nil }
        loaded = true
    }

    private func warehouseName(_ id: String) -> String {
        guard let warehouse = try? engine.fetch(docType: "Warehouse", id: id),
              case .string(let name)? = warehouse.fields["warehouse_name"],
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return id }
        return name
    }

    private func formatQty(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 3
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

/// Hub-specific lifecycle layer on top of `GenericFormView`. The basic
/// Save / Delete / "Saved · just now" affordances now live in Core's
/// `RecordCollectionHostView`; this editor only contributes the
/// Submit / Cancel / Amend buttons and any DocType-specific workflow
/// transitions, plus the lifecycle status badge.
private struct HubDocumentEditor: View {
    let docType: DocType
    let engine: DocumentEngine
    let workflowEngine: WorkflowEngine
    @Binding var document: Document
    /// Notifies the host that something persisted, so it can reload its
    /// `documents` list. The host owns Save itself; this fires for the
    /// lifecycle actions handled below (submit/cancel/amend/workflow).
    let onPersist: () -> Void
    /// Requests cross-DocType navigation to a related record (lineage links in
    /// the "Related" inspector card). Nil when navigation isn't wired.
    var onOpenRelatedRecord: ((String, String) -> Void)? = nil

    /// Phase 1 — posts atomic-posting DocTypes (Journal Entry) inside the
    /// submit/cancel transaction. Injected at app scope; nil in previews.
    @Environment(\.postingCoordinator) private var posting
    /// ADR-044 print engine, injected at app scope; drives the header Print
    /// menu (per-DocType formats, default first). Nil in previews / tests.
    @Environment(\.printService) private var printService

    @State private var errorMessage: String?
    /// A transient success note (e.g. after converting a Sales Order into a
    /// Delivery / Invoice), shown as a green banner.
    @State private var infoMessage: String?
    /// A pending action awaiting confirmation (Post / Cancel of a
    /// ledger- or stock-affecting document). Drives the confirmation dialog.
    @State private var pendingConfirmation: PendingLifecycleAction?
    @State private var selectedWorkspaceSectionID: String = ""
    @State private var showsInspector = true

    private let displayPolicy = HubWorkflowDisplayPolicy.policy

    private var workflow: WorkflowDefinition? {
        HubWorkflows.workflow(forDocTypeId: docType.id)
    }
    private let evaluator = ExpressionEvaluator()

    /// Identifies a lifecycle action that needs a confirmation step before it
    /// mutates the ledger / stock spine.
    private struct PendingLifecycleAction: Identifiable {
        enum Kind { case submit, cancel, workflow(WorkflowTransition) }
        let id = UUID()
        let kind: Kind
        let title: String
        let message: String
        let confirmLabel: String
    }

    var body: some View {
        Group {
            if let layout = HubDocumentLayoutPolicy.layout(for: docType) {
                polishedWorkspace(layout: layout)
            } else {
                legacyWorkspace
            }
        }
        .frame(minWidth: 480, minHeight: 400)
        .confirmationDialog(
            pendingConfirmation?.title ?? "",
            isPresented: confirmationBinding,
            titleVisibility: .visible,
            presenting: pendingConfirmation
        ) { action in
            Button(action.confirmLabel, role: confirmRole(for: action)) {
                runConfirmedAction(action)
            }
            Button("Keep Editing", role: .cancel) { pendingConfirmation = nil }
        } message: { action in
            Text(action.message)
        }
    }

    private var legacyWorkspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                lifecycleHeader
                GenericFormView(
                    docType: docType,
                    document: $document,
                    linkSearchProvider: { targetDocType, _ in
                        (try? engine.list(docType: targetDocType)) ?? []
                    },
                    linkResolveProvider: { targetDocType, id in
                        try? engine.fetch(docType: targetDocType, id: id)
                    },
                    childDocTypeProvider: { HubManifest.docType(for: $0) },
                    linkCreateProvider: { targetDocType in
                        let now = Date()
                        return Document(
                            id: "", docType: targetDocType, company: "", status: "",
                            createdAt: now, updatedAt: now, syncVersion: 0, syncState: .local,
                            fields: [:], children: [:]
                        )
                    },
                    linkCommitProvider: { document in
                        let saved = try engine.save(document)
                        return (try? engine.fetch(docType: document.docType, id: saved.id)) ?? saved
                    }
                )
                // Phase 3: surface current stock-on-hand on the Item
                // workspace, derived from Stock Balance (Bin) rows.
                if docType.id == "Item", !document.id.isEmpty {
                    ItemStockSummaryView(itemID: document.id, engine: engine)
                }
                if hasLifecycleActions {
                    actionRow
                }
                if let error = errorMessage {
                    errorBanner(error)
                }
                if let infoMessage {
                    infoBanner(infoMessage)
                }
            }
            .padding()
        }
    }

    private func polishedWorkspace(layout: HubDocumentLayoutPolicy.Layout) -> some View {
        let cards = inspectorCards(for: layout)
        let inspectorBinding = Binding(
            get: { !cards.isEmpty && showsInspector },
            set: { showsInspector = $0 }
        )

        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                workspaceHeader(layout: layout, inspectorAvailable: !cards.isEmpty)
                if !summaryItems(for: layout).isEmpty {
                    summaryGridCard(layout: layout)
                }
                if layout.sections.count > 1 {
                    sectionPicker(layout: layout)
                }
                if let error = errorMessage {
                    errorBanner(error)
                }
                if let infoMessage {
                    infoBanner(infoMessage)
                }
            }
            .padding(16)

            Divider()

            GenericFormView(
                docType: filteredDocType(for: layout, sectionID: selectedSectionID(in: layout)),
                document: $document,
                linkSearchProvider: { targetDocType, _ in
                    (try? engine.list(docType: targetDocType)) ?? []
                },
                linkResolveProvider: { targetDocType, id in
                    try? engine.fetch(docType: targetDocType, id: id)
                },
                childDocTypeProvider: { HubManifest.docType(for: $0) },
                linkCreateProvider: { targetDocType in
                    let now = Date()
                    return Document(
                        id: "", docType: targetDocType, company: "", status: "",
                        createdAt: now, updatedAt: now, syncVersion: 0, syncState: .local,
                        fields: [:], children: [:]
                    )
                },
                linkCommitProvider: { document in
                    let saved = try engine.save(document)
                    return (try? engine.fetch(docType: document.docType, id: saved.id)) ?? saved
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(MercantisTheme.appBackground)
        .inspector(isPresented: inspectorBinding) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(cards) { card in
                        inspectorCardView(card)
                    }
                }
                .padding(16)
            }
            .frame(minWidth: 260, idealWidth: 300)
            .background(MercantisTheme.appBackground)
        }
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingConfirmation != nil },
            set: { if !$0 { pendingConfirmation = nil } }
        )
    }

    private func confirmRole(for action: PendingLifecycleAction) -> ButtonRole? {
        if case .cancel = action.kind { return .destructive }
        return nil
    }

    private var hasLifecycleActions: Bool {
        if docType.isSubmittable && document.docStatus != 0 { return true }
        if docType.isSubmittable && document.docStatus == 0 && !document.id.isEmpty { return true }
        return !availableWorkflowTransitions.filter(shouldOfferWorkflowButton).isEmpty
    }

    private struct WorkspaceFieldDisplay: Identifiable {
        let key: String
        let label: String
        let value: String
        let isNumeric: Bool
        /// When set, the row is a tappable link to this (DocType, record) — used
        /// by the "Related" lineage card.
        var navigation: (docTypeId: String, recordId: String)? = nil

        var id: String { key }
    }

    private struct InspectorCardContent: Identifiable {
        let id: String
        let title: String
        let systemImage: String
        let rows: [WorkspaceFieldDisplay]

        var hasContent: Bool { !rows.isEmpty }
    }

    private struct WorkspaceActionDescriptor: Identifiable {
        let id: String
        let label: String
        let role: ButtonRole?
        let isPrimary: Bool
        let perform: () -> Void
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
            printMenuButton
                .controlSize(.small)
        }
    }

    private var statusBadge: some View {
        // The lifecycle (docStatus) badge shows the document-specific business
        // wording via the display policy — so a submitted invoice reads
        // "Posted", a submitted order reads "Confirmed", a submitted BOM reads
        // "Active", etc. — rather than the raw internal "Submitted". The
        // operational workflow state (e.g. "Paid", "Overdue") is shown as a
        // second badge only when it adds information beyond the lifecycle.
        //
        // Non-submittable master data (Item, UOM, Warehouse, …) has no
        // Draft/Submitted lifecycle, so the lifecycle badge is suppressed for it
        // — only a real workflow/status string (if any) is shown.
        let lifecycle: DocumentStatusDisplay? = docType.isSubmittable
            ? displayPolicy.lifecycleDisplay(docTypeId: docType.id, docStatus: document.docStatus)
            : nil

        let workflowDisplay: DocumentStatusDisplay? = {
            let trimmed = document.status.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let display = displayPolicy.statusDisplay(docTypeId: docType.id, state: trimmed)
            // Hide the second badge when it would just repeat the lifecycle one.
            if let lifecycle, display.label.lowercased() == lifecycle.label.lowercased() {
                return nil
            }
            return display
        }()

        return HStack(spacing: 6) {
            if let lifecycle {
                MercantisStatusBadge(display: lifecycle)
            }
            if let workflowDisplay {
                MercantisStatusBadge(display: workflowDisplay)
            }
        }
    }

    private func workspaceHeader(layout: HubDocumentLayoutPolicy.Layout, inspectorAvailable: Bool) -> some View {
        let leadingContext = headerContext(for: layout)
        let metadata = headerMetadata

        return MercantisCard(padding: .standard, tinted: true) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(document.id.isEmpty ? "New \(docType.name)" : docType.name)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(MercantisTheme.textPrimary)
                        Spacer(minLength: 12)
                        if !document.id.isEmpty {
                            Text(document.id)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(MercantisTheme.textSecondary)
                                .textSelection(.enabled)
                        }
                    }

                    if let leadingContext {
                        Text(leadingContext)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(MercantisTheme.textSecondary)
                            .lineLimit(2)
                    }

                    HStack(spacing: 6) {
                        statusBadge
                    }

                    if !metadata.isEmpty {
                        Text(metadata.joined(separator: "  •  "))
                            .font(.caption)
                            .foregroundStyle(MercantisTheme.textSecondary)
                            .lineLimit(2)
                    }
                }

                headerActionBar(inspectorAvailable: inspectorAvailable)
            }
        }
    }

    /// The document's action bar: a single aligned, consistently styled row
    /// instead of the old cramped two-tier corner cluster. Document / workflow
    /// actions sit on the left (primary first), so the row has room to grow as
    /// more are added (e.g. Convert to Delivery / Convert to Invoice); the
    /// view-only inspector toggle is pushed to the right and visually separated.
    @ViewBuilder
    /// The Print menu, available on any saved document (polished or legacy
    /// workspace) so every printable DocType — Delivery Note, Purchase Receipt,
    /// master data, … — can print and manage its formats, not just the
    /// sales/purchase transaction docs.
    @ViewBuilder
    private var printMenuButton: some View {
        if let printService, !document.id.isEmpty {
            HubPrintButton(document: document, printService: printService, engine: engine)
                .buttonStyle(.bordered)
                .fixedSize()
        }
    }

    private func headerActionBar(inspectorAvailable: Bool) -> some View {
        let actions = workspaceActions
        if !actions.isEmpty || inspectorAvailable {
            HStack(spacing: 8) {
                if let primary = actions.first(where: \.isPrimary) {
                    Button(primary.label, role: primary.role, action: primary.perform)
                        .buttonStyle(.borderedProminent)
                }
                ForEach(actions.filter { !$0.isPrimary }) { action in
                    Button(action.label, role: action.role, action: action.perform)
                        .buttonStyle(.bordered)
                }

                Spacer(minLength: 12)

                printMenuButton

                if inspectorAvailable {
                    Button {
                        showsInspector.toggle()
                    } label: {
                        Label(showsInspector ? "Hide Inspector" : "Show Inspector",
                              systemImage: "sidebar.right")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var headerMetadata: [String] {
        var metadata: [String] = []
        if let workflow {
            metadata.append(workflow.name)
        }
        if !document.company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            metadata.append(document.company)
        }
        if !document.id.isEmpty {
            metadata.append("Created \(dateTimeFormatter.string(from: document.createdAt))")
        }
        metadata.append("Updated \(dateTimeFormatter.string(from: document.updatedAt))")
        return metadata
    }

    private func headerContext(for layout: HubDocumentLayoutPolicy.Layout) -> String? {
        var segments: [String] = []
        if let party = firstDisplay(for: layout.partyFieldKeys)?.value {
            segments.append(party)
        }
        for key in layout.dateFieldKeys {
            guard let item = fieldDisplay(for: key) else { continue }
            segments.append("\(item.label): \(item.value)")
        }
        let joined = segments.joined(separator: "  •  ")
        return joined.isEmpty ? nil : joined
    }

    private func summaryGridCard(layout: HubDocumentLayoutPolicy.Layout) -> some View {
        let items = summaryItems(for: layout)
        return MercantisCard(padding: .compact) {
            VStack(alignment: .leading, spacing: 10) {
                MercantisPanelHeader("Summary", systemImage: "square.grid.2x2")

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 10)], spacing: 10) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.label)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(MercantisTheme.textSecondary)
                                .lineLimit(1)
                            Text(item.value)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(MercantisTheme.textPrimary)
                                .multilineTextAlignment(item.isNumeric ? .trailing : .leading)
                                .lineLimit(2)
                                .monospacedDigit()
                                .frame(maxWidth: .infinity, alignment: item.isNumeric ? .trailing : .leading)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(MercantisTheme.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(MercantisTheme.hairline, lineWidth: 1)
                        )
                    }
                }
            }
        }
    }

    private func sectionPicker(layout: HubDocumentLayoutPolicy.Layout) -> some View {
        Picker("Workspace Section", selection: sectionSelection(for: layout)) {
            ForEach(layout.sections) { section in
                Text(section.title).tag(section.id)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(MercantisTheme.danger)
            Text(error)
                .foregroundStyle(MercantisTheme.danger)
                .lineLimit(2)
            Spacer()
        }
        .font(.callout)
        .padding(10)
        .background(MercantisTheme.fillSoft(for: .danger), in: RoundedRectangle(cornerRadius: 8))
    }

    private func infoBanner(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(MercantisTheme.success)
            Text(text)
                .foregroundStyle(MercantisTheme.success)
                .lineLimit(2)
            Spacer()
        }
        .font(.callout)
        .padding(10)
        .background(MercantisTheme.fillSoft(for: .success), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Sales Order → Delivery / Invoice conversion buttons, offered once the
    /// order is confirmed (docStatus 1). Each builds a draft of the target
    /// document from the order and saves it; the operator opens and submits it.
    private var conversionActions: [WorkspaceActionDescriptor] {
        guard document.docStatus == 1, !document.id.isEmpty else { return [] }
        switch docType.id {
        case "Quotation":
            // Only an accepted/won quote (workflow state "Ordered", shown as
            // "Accepted") converts to an order — a merely sent quote can't yet.
            guard document.status == "Ordered" else { return [] }
            return [
                WorkspaceActionDescriptor(
                    id: "convert:salesorder", label: "Convert to Sales Order", role: nil, isPrimary: false,
                    perform: { convertDocument(to: "SalesOrder", label: "sales order", linkField: "quotation") }
                ),
            ]
        case "SalesOrder":
            return [
                WorkspaceActionDescriptor(
                    id: "convert:delivery", label: "Convert to Delivery", role: nil, isPrimary: false,
                    perform: { convertDocument(to: "SalesDelivery", label: "delivery", linkField: "sales_order") }
                ),
                WorkspaceActionDescriptor(
                    id: "convert:invoice", label: "Convert to Invoice", role: nil, isPrimary: false,
                    perform: { convertDocument(to: "SalesInvoice", label: "invoice", linkField: "sales_order") }
                ),
            ]
        default:
            return []
        }
    }

    /// Build a downstream draft (`targetDocType`) from the current document,
    /// guarding against a duplicate conversion via `linkField` (the back-link
    /// the target carries to this document).
    private func convertDocument(to targetDocType: String, label: String, linkField: String) {
        errorMessage = nil
        infoMessage = nil
        do {
            // Don't create a second conversion for the same source. A cancelled
            // (docStatus 2) one doesn't count, so the operator can re-convert
            // after voiding a mistake.
            let existing = (try? engine.list(
                docType: targetDocType,
                filters: [linkField: .string(document.id)],
                applyRowAccess: false
            ))?.first(where: { $0.docStatus != 2 })
            if let existing {
                errorMessage = "A \(label) already exists for this document (\(existing.id)). Cancel it before creating another."
                return
            }

            var draft: Document
            switch targetDocType {
            case "SalesOrder":    draft = HubDocumentConversion.quotationToSalesOrder(document)
            case "SalesDelivery": draft = HubDocumentConversion.salesOrderToDelivery(document)
            case "SalesInvoice":  draft = HubDocumentConversion.salesOrderToInvoice(document)
            default: return
            }
            // Fill posting accounts / default warehouse from the Business
            // Profile, the same way a brand-new document's first save does, so
            // the draft carries the fields it needs to be submittable.
            if let targetType = HubManifest.docType(for: targetDocType),
               let profile = (try? engine.list(docType: "Company"))?.first {
                draft = HubBusinessProfileDefaultsPolicy.prepareForFirstSave(draft, docType: targetType, businessProfile: profile)
            }
            let saved = try engine.save(draft)
            infoMessage = "Created \(label) \(saved.id) — open it to review and submit."
            onPersist()
        } catch {
            errorMessage = humanReadable(error)
        }
    }

    private var workspaceActions: [WorkspaceActionDescriptor] {
        var actions: [WorkspaceActionDescriptor] = []
        var primaryAssigned = false

        if docType.isSubmittable, document.docStatus == 0, !document.id.isEmpty {
            let action = displayPolicy.actionDisplay(docTypeId: docType.id, action: "Submit")
            actions.append(
                WorkspaceActionDescriptor(
                    id: "submit",
                    label: action.label,
                    role: nil,
                    isPrimary: true,
                    perform: { requestSubmit(action) }
                )
            )
            primaryAssigned = true
        }

        if docType.isSubmittable, document.docStatus == 2 {
            let action = displayPolicy.actionDisplay(docTypeId: docType.id, action: "Amend")
            actions.append(
                WorkspaceActionDescriptor(
                    id: "amend",
                    label: action.label,
                    role: nil,
                    isPrimary: !primaryAssigned,
                    perform: { amend() }
                )
            )
            primaryAssigned = true
        }

        for transition in availableWorkflowTransitions where shouldOfferWorkflowButton(transition) {
            let action = displayPolicy.actionDisplay(docTypeId: docType.id, action: transition.action)
            let isPrimary = !primaryAssigned
            actions.append(
                WorkspaceActionDescriptor(
                    id: "workflow:\(transition.action)",
                    label: action.label,
                    role: nil,
                    isPrimary: isPrimary,
                    perform: { requestWorkflow(transition, action) }
                )
            )
            if isPrimary {
                primaryAssigned = true
            }
        }

        if docType.isSubmittable, document.docStatus == 1 {
            let action = displayPolicy.actionDisplay(docTypeId: docType.id, action: "Cancel")
            actions.append(
                WorkspaceActionDescriptor(
                    id: "cancel",
                    label: action.label,
                    role: .destructive,
                    isPrimary: false,
                    perform: { requestCancel(action) }
                )
            )
        }

        actions.append(contentsOf: conversionActions)
        return actions
    }

    private func sectionSelection(for layout: HubDocumentLayoutPolicy.Layout) -> Binding<String> {
        Binding(
            get: { selectedSectionID(in: layout) },
            set: { selectedWorkspaceSectionID = $0 }
        )
    }

    private func selectedSectionID(in layout: HubDocumentLayoutPolicy.Layout) -> String {
        if layout.sections.contains(where: { $0.id == selectedWorkspaceSectionID }) {
            return selectedWorkspaceSectionID
        }
        return layout.sections.first?.id ?? ""
    }

    private func filteredDocType(for layout: HubDocumentLayoutPolicy.Layout, sectionID: String) -> DocType {
        guard let selection = layout.sections.first(where: { $0.id == sectionID }),
              let formLayout = docType.formLayout
        else { return docType }

        var filteredSections = selection.layoutSectionKeys.compactMap { key in
            formLayout.sections.first(where: { $0.key == key })
        }

        if selection.includesUnmappedFields {
            let mappedKeys = Set(formLayout.sections.flatMap(\.fieldKeys))
            let unmapped = docType.fields.map(\.key).filter { !mappedKeys.contains($0) }
            if !unmapped.isEmpty {
                filteredSections.append(
                    FormLayoutSection(
                        key: "hub-unmapped-\(selection.id)",
                        title: filteredSections.isEmpty ? "Custom Fields" : "Additional Fields",
                        columns: 2,
                        fieldKeys: unmapped
                    )
                )
            }
        }

        guard !filteredSections.isEmpty else { return docType }
        var filtered = docType
        filtered.formLayout = FormLayout(sections: filteredSections)
        return filtered
    }

    private func summaryItems(for layout: HubDocumentLayoutPolicy.Layout) -> [WorkspaceFieldDisplay] {
        var seen = Set<String>()
        return layout.summaryFieldKeys.compactMap { key in
            guard seen.insert(key).inserted else { return nil }
            return fieldDisplay(for: key)
        }
    }

    private func firstDisplay(for keys: [String]) -> WorkspaceFieldDisplay? {
        for key in keys {
            if let item = fieldDisplay(for: key) {
                return item
            }
        }
        return nil
    }

    private func inspectorCards(for layout: HubDocumentLayoutPolicy.Layout) -> [InspectorCardContent] {
        let detailsRows = [
            WorkspaceFieldDisplay(key: "document_id", label: "Document", value: document.id.isEmpty ? "Draft" : document.id, isNumeric: false),
            WorkspaceFieldDisplay(key: "company", label: "Company", value: document.company.isEmpty ? "—" : document.company, isNumeric: false),
            WorkspaceFieldDisplay(key: "created_at", label: "Created", value: dateTimeFormatter.string(from: document.createdAt), isNumeric: false),
            WorkspaceFieldDisplay(key: "updated_at", label: "Updated", value: dateTimeFormatter.string(from: document.updatedAt), isNumeric: false)
        ]

        var cards: [InspectorCardContent] = [
            InspectorCardContent(id: "details", title: "Details", systemImage: "info.circle", rows: detailsRows)
        ]

        for card in layout.inspectorCards {
            let rows = card.fieldKeys.compactMap { fieldDisplay(for: $0) }
            if !rows.isEmpty {
                cards.append(
                    InspectorCardContent(
                        id: card.id,
                        title: card.title,
                        systemImage: card.systemImage,
                        rows: rows
                    )
                )
            }
        }

        if let related = relatedDocumentsCard() {
            cards.append(related)
        }

        return cards.filter(\.hasContent)
    }

    /// Lineage card: the documents this one was converted from / into, in both
    /// directions, shown by id. Back-links (quotation, sales_order) are read
    /// from this document's fields; forward links are found by querying the
    /// targets that point back here. Cancelled (docStatus 2) targets are
    /// excluded so a voided conversion doesn't linger.
    private func relatedDocumentsCard() -> InspectorCardContent? {
        guard !document.id.isEmpty else { return nil }
        var rows: [WorkspaceFieldDisplay] = []

        func backLink(_ label: String, field: String, target: String) {
            if let value = stringValue(document.fields[field]), !value.isEmpty {
                rows.append(WorkspaceFieldDisplay(
                    key: "rel-\(field)", label: label, value: value, isNumeric: false,
                    navigation: (docTypeId: target, recordId: value)))
            }
        }
        func forwardLinks(_ label: String, target: String, linkField: String) {
            let docs = (try? engine.list(
                docType: target,
                filters: [linkField: .string(document.id)],
                applyRowAccess: false
            )) ?? []
            for related in docs where related.docStatus != 2 {
                rows.append(WorkspaceFieldDisplay(
                    key: "rel-\(target)-\(related.id)", label: label, value: related.id, isNumeric: false,
                    navigation: (docTypeId: target, recordId: related.id)))
            }
        }

        switch docType.id {
        case "Quotation":
            forwardLinks("Sales Order", target: "SalesOrder", linkField: "quotation")
        case "SalesOrder":
            backLink("Quotation", field: "quotation", target: "Quotation")
            forwardLinks("Delivery", target: "SalesDelivery", linkField: "sales_order")
            forwardLinks("Invoice", target: "SalesInvoice", linkField: "sales_order")
        case "SalesDelivery", "SalesInvoice":
            backLink("Sales Order", field: "sales_order", target: "SalesOrder")
        default:
            return nil
        }

        guard !rows.isEmpty else { return nil }
        return InspectorCardContent(id: "related", title: "Related", systemImage: "link", rows: rows)
    }

    private func inspectorCardView(_ card: InspectorCardContent) -> some View {
        MercantisInspectorCard(card.title, systemImage: card.systemImage) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(card.rows.enumerated()), id: \.element.id) { index, row in
                    inspectorRowView(row)
                    if index < card.rows.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    /// A normal inspector row, or — when the row carries a lineage navigation
    /// target and a handler is wired — a tappable link that opens that record.
    @ViewBuilder
    private func inspectorRowView(_ row: WorkspaceFieldDisplay) -> some View {
        if let nav = row.navigation, let open = onOpenRelatedRecord {
            Button {
                open(nav.docTypeId, nav.recordId)
            } label: {
                HStack(spacing: 6) {
                    Text(row.label)
                        .font(.system(size: 12))
                        .foregroundStyle(MercantisTheme.textMuted)
                    Spacer(minLength: 8)
                    Text(row.value)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MercantisTheme.brandPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(MercantisTheme.textMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open \(row.value)")
        } else {
            MercantisInspectorRow(row.label, value: row.value, isNumeric: row.isNumeric)
        }
    }

    private func fieldDisplay(for key: String) -> WorkspaceFieldDisplay? {
        let value = displayValue(for: key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty else { return nil }

        let field = fieldDefinition(for: key)
        let label = field?.label ?? humanizedFieldLabel(for: key)
        let isNumeric = {
            switch field?.type {
            case .number, .decimal, .currency:
                return true
            default:
                return key == "total_qty"
            }
        }()

        return WorkspaceFieldDisplay(key: key, label: label, value: value, isNumeric: isNumeric)
    }

    private func displayValue(for key: String) -> String? {
        if key == "total_qty",
           document.fields[key] == nil,
           let derivedQty = derivedQuantityTotal() {
            return numberFormatter.string(from: NSNumber(value: derivedQty))
        }

        guard let field = fieldDefinition(for: key) else {
            return stringValue(document.fields[key])
        }

        guard let raw = document.fields[key] else {
            return nil
        }

        switch field.type {
        case .link:
            let rawID = stringValue(raw)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !rawID.isEmpty else { return nil }
            return resolveLinkValue(field: field, rawID: rawID)
        case .date:
            return formatDate(raw)
        case .datetime:
            return formatDateTime(raw)
        case .currency:
            return formatCurrency(raw)
        case .number, .decimal:
            return formatNumber(raw)
        case .boolean:
            if case .bool(let value) = raw {
                return value ? "Yes" : "No"
            }
            return stringValue(raw)
        default:
            return stringValue(raw)
        }
    }

    private func fieldDefinition(for key: String) -> FieldDefinition? {
        docType.fields.first(where: { $0.key == key })
    }

    private func resolveLinkValue(field: FieldDefinition, rawID: String) -> String {
        guard let targetDocType = field.linkedDocType,
              let linked = try? engine.fetch(docType: targetDocType, id: rawID)
        else { return rawID }

        if let targetMeta = HubManifest.docType(for: targetDocType),
           let title = stringValue(linked.fields[targetMeta.titleField]),
           !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }

        return rawID
    }

    private func derivedQuantityTotal() -> Double? {
        let keys = ["items", "references", "accounts"]
        for key in keys {
            let total = document.children[key, default: []].reduce(0.0) { partial, row in
                partial + numericValue(row.fields["qty"])
            }
            if total > 0 {
                return total
            }
        }
        return nil
    }

    private func numericValue(_ raw: FieldValue?) -> Double {
        switch raw {
        case .double(let value):
            return value
        case .int(let value):
            return Double(value)
        case .string(let value):
            return Double(value) ?? 0
        default:
            return 0
        }
    }

    private func stringValue(_ raw: FieldValue?) -> String? {
        switch raw {
        case .string(let value):
            return value
        case .int(let value):
            return "\(value)"
        case .double(let value):
            return numberFormatter.string(from: NSNumber(value: value))
        case .bool(let value):
            return value ? "Yes" : "No"
        case .date(let value), .dateTime(let value):
            return dateFormatter.string(from: value)
        default:
            return nil
        }
    }

    private func formatNumber(_ raw: FieldValue) -> String? {
        switch raw {
        case .int(let value):
            return numberFormatter.string(from: NSNumber(value: value))
        case .double(let value):
            return numberFormatter.string(from: NSNumber(value: value))
        case .string(let value):
            return Double(value).flatMap { numberFormatter.string(from: NSNumber(value: $0)) } ?? value
        default:
            return nil
        }
    }

    private func formatCurrency(_ raw: FieldValue) -> String? {
        switch raw {
        case .int(let value):
            return currencyString(Double(value))
        case .double(let value):
            return currencyString(value)
        case .string(let value):
            return Double(value).map { currencyString($0) } ?? value
        default:
            return nil
        }
    }

    private func currencyString(_ value: Double) -> String {
        let code = stringValue(document.fields["currency"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if code.count == 3 {
            return value.formatted(.currency(code: code))
        }
        return numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func formatDate(_ raw: FieldValue) -> String? {
        switch raw {
        case .date(let value), .dateTime(let value):
            return dateFormatter.string(from: value)
        case .string(let value):
            return value
        default:
            return nil
        }
    }

    private func formatDateTime(_ raw: FieldValue) -> String? {
        switch raw {
        case .date(let value), .dateTime(let value):
            return dateTimeFormatter.string(from: value)
        case .string(let value):
            return value
        default:
            return nil
        }
    }

    private func humanizedFieldLabel(for key: String) -> String {
        key
            .split(separator: "_")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }

    private var dateTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    // MARK: - Action row

    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: 8) {
            // Post / Submit appears when the DocType is submittable and the
            // document is a persisted Draft. The label is document-specific
            // ("Post Invoice", "Confirm Order", "Activate BOM", …).
            if docType.isSubmittable, document.docStatus == 0, !document.id.isEmpty {
                let action = displayPolicy.actionDisplay(docTypeId: docType.id, action: "Submit")
                Button(action.label) { requestSubmit(action) }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .buttonStyle(.borderedProminent)
            }

            // Cancel / Reverse appears when the document is posted (Submitted).
            if docType.isSubmittable, document.docStatus == 1 {
                let action = displayPolicy.actionDisplay(docTypeId: docType.id, action: "Cancel")
                Button(action.label, role: .destructive) { requestCancel(action) }
            }

            // Amend appears when the document has been Cancelled.
            if docType.isSubmittable, document.docStatus == 2 {
                let action = displayPolicy.actionDisplay(docTypeId: docType.id, action: "Amend")
                Button(action.label) { amend() }
                    .buttonStyle(.borderedProminent)
            }

            // Workflow transition buttons surface every status transition
            // available from the current state, with business-friendly labels.
            ForEach(availableWorkflowTransitions, id: \.action) { transition in
                if shouldOfferWorkflowButton(transition) {
                    let action = displayPolicy.actionDisplay(docTypeId: docType.id, action: transition.action)
                    Button(action.label) { requestWorkflow(transition, action) }
                        .buttonStyle(.bordered)
                }
            }

            Spacer()
        }
    }

    // MARK: - Confirmation routing

    /// Posts immediately when the action has no confirmation copy, otherwise
    /// stages a confirmation dialog first.
    private func requestSubmit(_ action: DocumentActionDisplay) {
        if let message = action.confirmation {
            pendingConfirmation = PendingLifecycleAction(
                kind: .submit,
                title: action.label,
                message: message,
                confirmLabel: action.label
            )
        } else {
            submit()
        }
    }

    private func requestCancel(_ action: DocumentActionDisplay) {
        if let message = action.confirmation {
            pendingConfirmation = PendingLifecycleAction(
                kind: .cancel,
                title: action.label,
                message: message,
                confirmLabel: action.label
            )
        } else {
            cancel()
        }
    }

    private func requestWorkflow(_ transition: WorkflowTransition, _ action: DocumentActionDisplay) {
        if let message = action.confirmation {
            pendingConfirmation = PendingLifecycleAction(
                kind: .workflow(transition),
                title: action.label,
                message: message,
                confirmLabel: action.label
            )
        } else {
            runWorkflow(transition)
        }
    }

    private func runConfirmedAction(_ action: PendingLifecycleAction) {
        pendingConfirmation = nil
        switch action.kind {
        case .submit:                 submit()
        case .cancel:                 cancel()
        case .workflow(let transition): runWorkflow(transition)
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

    private func submit() {
        do {
            // Phase 2 (VAT): make sure taxes + totals reflect the latest
            // line items before they are frozen by submit and read by the
            // ledger / TaxTrans derivation.
            document = HubTaxCalculationPolicy.applied(
                to: document,
                docType: docType,
                engine: engine
            )
            // 1. Persist any pending edits.
            _ = try engine.save(document)
            if let refreshed = try engine.fetch(docType: docType.id, id: document.id) {
                document = refreshed
            }
            // 2. Flip docStatus 0 → 1 through Core's submit pipeline so
            //    immutability + audit + workflow-history rows fire. For
            //    atomic-posting DocTypes, posting runs inside this same
            //    transaction (Phase 1) — a posting failure rolls the submit back.
            if let posting, let closure = posting.submitClosure(for: document) {
                try engine.submit(&document, inTransaction: closure)
            } else {
                try engine.submit(&document)
            }
            // Refetch so the in-memory copy carries the timestamp `submit`'s
            // save just wrote; the workflow transition below saves again and
            // would otherwise hit the optimistic-concurrency check with a stale
            // `updatedAt`.
            if let refreshed = try engine.fetch(docType: docType.id, id: document.id) {
                document = refreshed
            }
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
                    userId: HubIdentity.userId()
                )
                _ = try engine.save(document)
            }
            refreshBinding(toID: document.id)
            errorMessage = nil
            onPersist()
        } catch {
            errorMessage = humanReadable(error)
        }
    }

    private func cancel() {
        do {
            // Atomic-posting DocTypes write their reversal rows inside the
            // cancel transaction (Phase 1); others reverse via the event path.
            if let posting, let closure = posting.cancelClosure(for: document) {
                try engine.cancel(&document, inTransaction: closure)
            } else {
                try engine.cancel(&document)
            }
            // Refetch so the workflow transition's save below sees the
            // timestamp `cancel`'s save just wrote (optimistic concurrency).
            if let refreshed = try engine.fetch(docType: docType.id, id: document.id) {
                document = refreshed
            }
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
                    userId: HubIdentity.userId()
                )
                _ = try engine.save(document)
            }
            refreshBinding(toID: document.id)
            errorMessage = nil
            onPersist()
        } catch {
            errorMessage = humanReadable(error)
        }
    }

    private func amend() {
        do {
            let amended = try engine.amend(document)
            refreshBinding(toID: amended.id, fallback: amended)
            errorMessage = nil
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
                userId: HubIdentity.userId()
            )
            _ = try engine.save(document)
            refreshBinding(toID: document.id)
            errorMessage = nil
            onPersist()
        } catch {
            errorMessage = humanReadable(error)
        }
    }

    // MARK: - Helpers

    /// Re-reads the persisted document so the in-memory binding carries
    /// the latest `updatedAt` and any engine-applied side-effects (naming
    /// series, computed fields, etc.). Mirrors the Core host's own
    /// refetch-after-save behaviour for the lifecycle paths Hub owns.
    private func refreshBinding(toID id: String, fallback: Document? = nil) {
        if !id.isEmpty,
           let refreshed = try? engine.fetch(docType: docType.id, id: id) {
            document = refreshed
        } else if let fallback {
            document = fallback
        }
    }

    private func humanReadable(_ error: Error) -> String {
        let description = (error as NSError).localizedDescription
        if description.isEmpty || description == "The operation couldn’t be completed." {
            return String(describing: error)
        }
        return description
    }
}

enum HubDocumentLayoutPolicy {
    struct Layout {
        let summaryFieldKeys: [String]
        let partyFieldKeys: [String]
        let dateFieldKeys: [String]
        let sections: [Section]
        let inspectorCards: [InspectorCard]
    }

    struct Section: Identifiable, Hashable {
        let id: String
        let title: String
        let layoutSectionKeys: [String]
        var includesUnmappedFields: Bool = false
    }

    struct InspectorCard: Identifiable, Hashable {
        let id: String
        let title: String
        let systemImage: String
        let fieldKeys: [String]
    }

    static func layout(for docType: DocType) -> Layout? {
        layout(for: docType.id)
    }

    static func layout(for docTypeId: String) -> Layout? {
        switch docTypeId {
        case "Quotation", "SalesOrder":
            return Layout(
                summaryFieldKeys: [
                    "customer", "transaction_date", "delivery_date",
                    "price_list", "currency", "payment_terms",
                    "warehouse", "grand_total"
                ],
                partyFieldKeys: ["customer"],
                dateFieldKeys: ["transaction_date", "delivery_date"],
                sections: [
                    Section(id: "details", title: "Details", layoutSectionKeys: ["header"]),
                    Section(id: "items", title: "Items & Pricing", layoutSectionKeys: ["items", "totals"]),
                    Section(id: "terms", title: "Terms", layoutSectionKeys: ["notes"], includesUnmappedFields: true)
                ],
                inspectorCards: [
                    InspectorCard(id: "customer", title: "Customer", systemImage: "person.crop.circle", fieldKeys: ["customer", "currency", "price_list"]),
                    InspectorCard(id: "totals", title: "Summary Totals", systemImage: "sum", fieldKeys: ["total_qty", "grand_total"])
                ]
            )
        case "SalesInvoice":
            return Layout(
                summaryFieldKeys: [
                    "customer", "transaction_date", "due_date",
                    "price_list", "currency", "payment_terms",
                    "warehouse", "grand_total"
                ],
                partyFieldKeys: ["customer"],
                dateFieldKeys: ["transaction_date", "due_date"],
                sections: [
                    Section(id: "details", title: "Details", layoutSectionKeys: ["header", "billing"]),
                    Section(id: "items", title: "Items & Pricing", layoutSectionKeys: ["items", "totals"]),
                    Section(id: "more", title: "More Info", layoutSectionKeys: ["posting", "notes"], includesUnmappedFields: true)
                ],
                inspectorCards: [
                    InspectorCard(id: "customer", title: "Customer", systemImage: "person.crop.circle", fieldKeys: ["customer", "currency", "price_list"]),
                    InspectorCard(id: "totals", title: "Summary Totals", systemImage: "sum", fieldKeys: ["total_qty", "grand_total", "outstanding_amount"])
                ]
            )
        case "SupplierQuotation", "PurchaseOrder":
            return Layout(
                summaryFieldKeys: [
                    "supplier", "transaction_date", "schedule_date",
                    "price_list", "currency", "payment_terms",
                    "warehouse", "grand_total"
                ],
                partyFieldKeys: ["supplier"],
                dateFieldKeys: ["transaction_date", "schedule_date"],
                sections: [
                    Section(id: "details", title: "Details", layoutSectionKeys: ["header"]),
                    Section(id: "items", title: "Items & Pricing", layoutSectionKeys: ["items", "totals"]),
                    Section(id: "terms", title: "Terms", layoutSectionKeys: ["notes"], includesUnmappedFields: true)
                ],
                inspectorCards: [
                    InspectorCard(id: "supplier", title: "Supplier", systemImage: "shippingbox", fieldKeys: ["supplier", "currency", "price_list"]),
                    InspectorCard(id: "totals", title: "Summary Totals", systemImage: "sum", fieldKeys: ["total_qty", "grand_total"])
                ]
            )
        case "PurchaseInvoice":
            return Layout(
                summaryFieldKeys: [
                    "supplier", "transaction_date", "due_date",
                    "price_list", "currency", "payment_terms",
                    "warehouse", "grand_total"
                ],
                partyFieldKeys: ["supplier"],
                dateFieldKeys: ["transaction_date", "due_date"],
                sections: [
                    Section(id: "details", title: "Details", layoutSectionKeys: ["header", "billing"]),
                    Section(id: "items", title: "Items & Pricing", layoutSectionKeys: ["items", "totals"]),
                    Section(id: "more", title: "More Info", layoutSectionKeys: ["posting", "notes"], includesUnmappedFields: true)
                ],
                inspectorCards: [
                    InspectorCard(id: "supplier", title: "Supplier", systemImage: "shippingbox", fieldKeys: ["supplier", "currency", "price_list"]),
                    InspectorCard(id: "totals", title: "Summary Totals", systemImage: "sum", fieldKeys: ["total_qty", "grand_total", "outstanding_amount"])
                ]
            )
        case "StockEntry":
            return Layout(
                summaryFieldKeys: [
                    "purpose", "posting_date", "default_source_warehouse",
                    "default_target_warehouse", "total_qty", "total_value"
                ],
                partyFieldKeys: ["purpose"],
                dateFieldKeys: ["posting_date", "posting_time"],
                sections: [
                    Section(id: "details", title: "Details", layoutSectionKeys: ["header", "defaults"]),
                    Section(id: "items", title: "Items & Pricing", layoutSectionKeys: ["items", "totals"]),
                    Section(id: "more", title: "More Info", layoutSectionKeys: ["remarks"], includesUnmappedFields: true)
                ],
                inspectorCards: [
                    InspectorCard(id: "movement", title: "Stock Movement", systemImage: "tray.full", fieldKeys: ["purpose", "default_source_warehouse", "default_target_warehouse"]),
                    InspectorCard(id: "totals", title: "Summary Totals", systemImage: "sum", fieldKeys: ["total_qty", "total_value"])
                ]
            )
        case "PaymentEntry":
            return Layout(
                summaryFieldKeys: [
                    "payment_type", "party_type", "party",
                    "posting_date", "paid_amount", "received_amount",
                    "reference_no"
                ],
                partyFieldKeys: ["party"],
                dateFieldKeys: ["posting_date"],
                sections: [
                    Section(id: "details", title: "Details", layoutSectionKeys: ["header", "party", "accounts"]),
                    Section(id: "terms", title: "Terms", layoutSectionKeys: ["references"]),
                    Section(id: "more", title: "More Info", layoutSectionKeys: ["remarks"], includesUnmappedFields: true)
                ],
                inspectorCards: [
                    InspectorCard(id: "party", title: "Party", systemImage: "person.crop.circle", fieldKeys: ["party_type", "party", "paid_from", "paid_to"]),
                    InspectorCard(id: "totals", title: "Summary Totals", systemImage: "sum", fieldKeys: ["paid_amount", "received_amount"])
                ]
            )
        default:
            return nil
        }
    }
}

// MARK: - Menu commands

/// A context-aware "create new record" action published by the active
/// workspace via the focused-scene value below, so the File ▸ New menu
/// command (⌘N) targets whatever the user is currently looking at (e.g.
/// "New Customer" in the Customers workspace) and is disabled where there's
/// nothing to create (Home, reports, dashboards).
struct NewRecordAction {
    let label: String
    let perform: () -> Void
}

private struct NewRecordActionKey: FocusedValueKey {
    typealias Value = NewRecordAction
}

extension FocusedValues {
    var newRecordAction: NewRecordAction? {
        get { self[NewRecordActionKey.self] }
        set { self[NewRecordActionKey.self] = newValue }
    }
}

/// Focused, native macOS menu commands for Mercantis Hub.
///
/// Deliberately minimal: these mirror on-screen affordances and add keyboard
/// access — they do not introduce menu-only features. Wired into the app via
/// `.commands { HubCommands() }`.
/// Window ids for app-scene windows opened from menu commands.
enum HubWindows {
    static let printFormats = "developer-print-formats"
}

struct HubCommands: Commands {
    @FocusedValue(\.newRecordAction) private var newRecordAction
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some Commands {
        // File ▸ New <record> — replaces the stock "New" item with a
        // context-aware create that drives the active workspace.
        CommandGroup(replacing: .newItem) {
            Button(newRecordAction.map { "New \($0.label)" } ?? "New") {
                newRecordAction?.perform()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(newRecordAction == nil)
        }

        #if os(macOS)
        // View ▸ Show/Hide Sidebar — native split-view toggle so the sidebar
        // has a keyboard path, not just the toolbar button.
        CommandGroup(replacing: .sidebar) {
            Button("Show/Hide Sidebar") {
                NSApp.keyWindow?.firstResponder?.tryToPerform(
                    #selector(NSSplitViewController.toggleSidebar(_:)),
                    with: nil
                )
            }
            .keyboardShortcut("s", modifiers: [.control, .command])
        }

        // Developer ▸ Print Formats — manage every DocType's print formats
        // (duplicate, edit drafts, publish, restore) in a dedicated window.
        CommandMenu("Developer") {
            Button("Print Formats…") { openWindow(id: HubWindows.printFormats) }
        }
        #endif
    }
}

// MARK: - Print service environment injection

private struct PrintServiceKey: EnvironmentKey {
    static let defaultValue: PrintService? = nil
}

extension EnvironmentValues {
    /// The app's print service (ADR-044), injected at app scope so any document
    /// header can offer the Print menu. Nil in previews / tests.
    var printService: PrintService? {
        get { self[PrintServiceKey.self] }
        set { self[PrintServiceKey.self] = newValue }
    }
}

private struct OperatorRolesKey: EnvironmentKey {
    static let defaultValue: Set<String> = []
}

extension EnvironmentValues {
    /// The signed-in operator's roles, injected at app scope so views can gate
    /// advanced capabilities (e.g. the print-format HTML/CSS developer mode).
    var operatorRoles: Set<String> {
        get { self[OperatorRolesKey.self] }
        set { self[OperatorRolesKey.self] = newValue }
    }
}
