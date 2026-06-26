import SwiftUI
import MercantisCore

@main
struct mercantis_hubApp: App {

    let documentEngine: DocumentEngine
    let workflowEngine: WorkflowEngine
    /// Phase 1 — posts the DocTypes it owns (Journal Entry today) inside the
    /// submit/cancel transaction. Routed from RootView's submit/cancel actions.
    let postingCoordinator: PostingCoordinator
    /// Wall 7 — retained so its event subscriptions stay alive for the
    /// lifetime of the app. Held via a strong reference at app scope.
    let ledgerDerivation: LedgerDerivationService
    /// Manufacturing rollups + Stock Entry on WO completion. Same
    /// lifecycle / strong-retention contract as `ledgerDerivation`.
    let manufacturingDerivation: ManufacturingDerivationService
    /// Phase 7 — mirrors Delivery Route stop status onto Sales Deliveries
    /// and appends the status-event history. Same retention contract.
    let deliveryRouteService: DeliveryRouteService
    /// Wall 9 — engines for report execution and dashboard resolution.
    let reportEngine: ReportEngine
    let dashboardEngine: DashboardEngine
    /// Core's generic saved-report engine, used to execute user-built
    /// (from-scratch) custom reports directly against DocType metadata.
    let savedReportEngine: SavedReportEngine
    /// End-user customizations (ADR-021). Persisted in the `custom_fields`
    /// table so they survive app restarts and HubManifest reinstalls.
    let customFieldStore: CustomFieldStore
    /// Shared attachment store/manager. Backs the Document Capture flow
    /// (receipt images are synced attachments, ADR-048).
    let attachmentManager: AttachmentManager
    /// User-saved custom report variants. Persisted in `UserDefaults` (Hub is
    /// single-user / offline) and observed by the Custom Reports UI.
    @StateObject private var savedReportStore = HubSavedReportStore()

    /// App-wide workspace preferences (advanced view, business preset,
    /// optional-module flags, onboarding state). Owned at app scope so the
    /// main window and the Settings (⌘,) window share one instance.
    @StateObject private var visibility = HubVisibilitySettings()

    /// Multi-operator local auth. Gates the app behind a passcode lock; the
    /// active operator will drive the audit identity once Core grows a session
    /// hook (see `HubIdentity`).
    @StateObject private var authStore: AuthStore

    /// Serverless cross-device company sync over a shared folder (ADR-047).
    /// Held at app scope so its background timer / event subscriptions live for
    /// the app's lifetime.
    @StateObject private var companySync: CompanySync

    init() {
        let databaseURL = Self.makeDatabaseURL()

        let database = try! MercantisDatabase(databaseURL: databaseURL)
        let registry = MetadataRegistry(database: database)
        let validator = SchemaValidator()

        let installer = AppInstaller(
            database: database,
            schemaValidator: validator,
            registry: registry
        )
        try! installer.install(HubManifest.build())

        // One shared event bus: DocumentEngine publishes
        // DocumentSubmittedEvent / DocumentCancelledEvent into it;
        // LedgerDerivationService subscribes from the same instance.
        let emitter = EventEmitter()

        // P0.2: the signed-in operator (id + roles) drives audit identity and
        // permission checks. Built here so the context provider below can capture
        // a stable reference; injected into the StateObject like `companySync`.
        let authStore = AuthStore()
        _authStore = StateObject(wrappedValue: authStore)

        let documentEngine = DocumentEngine(
            database: database,
            registry: registry,
            deviceId: Self.deviceId(),
            userId: HubIdentity.userId(),
            eventEmitter: emitter,
            // P0.4: financial / transactional (submittable) DocTypes fail CLOSED —
            // submit / cancel / amend now demand an explicit granting role rather
            // than silently allowing an unconstrained write. The seeded operator
            // is a System Manager (full rights), so the default flows are
            // unaffected; restricted roles are gated to their scope.
            failClosedForSubmittable: true
        )
        // P0.2: resolve the live operator at call time. DocumentEngine mutations
        // originate from MainActor UI (and the synchronous derivation services
        // they trigger), so reading the MainActor-isolated AuthStore here is
        // safe. Before unlock, `currentOperator` is nil and the engine falls back
        // to the device identity (HubIdentity.userId via .legacy).
        documentEngine.setExecutionContextProvider {
            // Only the MainActor-bound UI path has a meaningful operator. Off the
            // main thread (e.g. the sync engine applying remote mutations) fall
            // back to nil so the engine uses its legacy identity rather than
            // crashing on an isolation assumption.
            guard Thread.isMainThread else { return nil }
            return MainActor.assumeIsolated {
                guard let op = authStore.currentOperator else { return nil }
                return ExecutionContext(
                    operatorId: op.id,
                    companyId: "Default Company",
                    roles: op.roles,
                    deviceId: HubIdentity.deviceId(),
                    sessionId: op.id
                )
            }
        }
        self.documentEngine = documentEngine
        // Wall 6: Hub uses Core's WorkflowEngine for post-submit state
        // transitions. The convenience init wires
        // WorkflowTransitionHistoryWriter so every transition persists
        // into `workflow_transitions` automatically (Phase A / ADR-038).
        //
        // Share the same `emitter` instance so the WorkflowTransitionEvent
        // fired here lands on the same bus that ManufacturingDerivationService
        // (and any future cross-DocType reaction) is subscribed to.
        self.workflowEngine = WorkflowEngine(database: database, eventEmitter: emitter)
        // Wall 7: LedgerDerivationService listens for transactional
        // submit / cancel events and writes append-only Stock Ledger
        // Entry / GL Entry rows with deterministic ids.
        self.postingCoordinator = PostingCoordinator(engine: documentEngine)
        self.ledgerDerivation = LedgerDerivationService(
            engine: documentEngine,
            emitter: emitter,
            // Skip the DocTypes posted atomically by PostingCoordinator so they
            // are not double-posted by this legacy event path. (Phase 1 cutover)
            atomicDocTypes: PostingCoordinator.atomicDocTypes
        )
        // Manufacturing: BOM cost rollup on save, Stock Entry on Work
        // Order completion, Work Order generation from Production Plan.
        // Shares the same `emitter` so it sees the same submit /
        // transition events as the ledger derivation.
        self.manufacturingDerivation = ManufacturingDerivationService(
            engine: documentEngine,
            emitter: emitter
        )
        // Phase 7: Delivery Route → Sales Delivery status mirroring + the
        // append-only Delivery Status Event history. Shares the same bus.
        self.deliveryRouteService = DeliveryRouteService(
            engine: documentEngine,
            emitter: emitter
        )
        // Wall 9: ReportEngine + DashboardEngine. ReportEngine holds the
        // registered ReportDefinitions for discovery / role filtering
        // (the actual aggregation lives in HubReports). DashboardEngine
        // resolves manifest-declared widget descriptors into typed
        // result tiles.
        let reportEngine = ReportEngine(documentEngine: documentEngine)
        for report in HubReports.allReports {
            reportEngine.register(report)
        }
        self.reportEngine = reportEngine

        let dashboardEngine = DashboardEngine(
            documentEngine: documentEngine,
            reportEngine: reportEngine
        )
        for dashboard in HubDashboards.allDashboards {
            dashboardEngine.register(dashboard)
        }
        self.dashboardEngine = dashboardEngine

        // Generic saved-report engine (Core ADR-050). Shares the same registry
        // so from-scratch reports validate their fields against the installed
        // DocType metadata and run through the same document-access rules.
        self.savedReportEngine = SavedReportEngine(
            documentEngine: documentEngine,
            registry: registry
        )

        // End-user customizations. The MigrationRunner has already created
        // the `custom_fields` table by the time we reach here; this just
        // hands the same database to the store so workspaces can read/write
        // their own fields without colliding with the HubManifest reinstall
        // that runs above.
        self.customFieldStore = CustomFieldStore(database: database)

        // Shared attachment store/manager (receipt capture + any record
        // attachments). Stored beside the database in Application Support.
        let attachmentStore = try! AttachmentStore(rootURL: Self.makeAttachmentsURL())
        self.attachmentManager = AttachmentManager(
            database: database,
            store: attachmentStore,
            auditWriter: AuditLogWriter(database: database)
        )

        // Company sync engine (built on Core's FileSystemCloudAdapter + SyncEngine).
        // Built as a StateObject from init so its lifetime matches the app. The
        // pending-changes badge defaults to 0 (sync correctness never depends on
        // it — SyncEngine reads the queue itself).
        _companySync = StateObject(wrappedValue: CompanySync(
            database: database,
            documentEngine: documentEngine,
            registry: registry,
            emitter: emitter,
            deviceId: Self.deviceId()
        ))
    }

    var body: some Scene {
        WindowGroup {
            AuthGate(store: authStore) {
                RootView(
                    engine: documentEngine,
                    workflowEngine: workflowEngine,
                    reportEngine: reportEngine,
                    dashboardEngine: dashboardEngine,
                    customFieldStore: customFieldStore,
                    savedReportStore: savedReportStore,
                    savedReportEngine: savedReportEngine,
                    visibility: visibility,
                    attachmentManager: attachmentManager,
                    companySync: companySync
                )
                // Phase 1: make the posting coordinator available to the form's
                // submit/cancel actions without threading it through every view.
                .environment(\.postingCoordinator, postingCoordinator)
            }
        }
        .defaultSize(width: 1100, height: 720)
        .commands { HubCommands() }

        // Standard macOS Settings window (⌘,). App configuration lives here
        // rather than in the navigation sidebar (HIG: sidebars are for
        // navigation; settings belong in the Settings window).
        Settings {
            HubSettingsView(settings: visibility)
        }
        // Let the user grow the Settings window instead of pinning it to a
        // fixed size; it can't shrink below the content's minimum.
        .windowResizability(.contentMinSize)
    }

    // MARK: - Bootstrap helpers

    private static func makeDatabaseURL() -> URL {
        let fm = FileManager.default
        let appSupport = try! fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport.appendingPathComponent("MercantisHub", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("hub.sqlite")
    }

    /// Directory that holds attachment blobs, beside the database.
    private static func makeAttachmentsURL() -> URL {
        let fm = FileManager.default
        let appSupport = try! fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport
            .appendingPathComponent("MercantisHub", isDirectory: true)
            .appendingPathComponent("Attachments", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func deviceId() -> String {
        HubIdentity.deviceId()
    }
}

/// Product-safe local identity for Mercantis Hub.
///
/// This pass replaces the previously hard-coded `userId: "kevin"` with a
/// stable, locally generated identifier. There is intentionally **no**
/// account login, sign-in UI, or remote identity in this revision — Hub is
/// an offline-first single-user workspace for now. When Core grows a real
/// user/session mechanism, this is the single place to swap the source of
/// truth from.
///
/// Both ids are persisted in `UserDefaults` so they survive app restarts
/// (mirroring the existing device-id strategy). The user id is prefixed
/// with `"local-"` so audit-log / workflow-history rows are visibly
/// attributed to a local identity rather than masquerading as a named user.
enum HubIdentity {

    private static let userIdKey   = "MercantisHub.userId"
    private static let deviceIdKey = "MercantisHub.deviceId"

    /// Stable per-installation user id, e.g. `"local-<uuid>"`. Generated and
    /// persisted on first launch; reused thereafter.
    static func userId() -> String {
        if let existing = UserDefaults.standard.string(forKey: userIdKey) {
            return existing
        }
        let id = "local-\(UUID().uuidString)"
        UserDefaults.standard.set(id, forKey: userIdKey)
        return id
    }

    /// Stable per-installation device id. Kept identical in behaviour to the
    /// previous `mercantis_hubApp.deviceId()` so existing sync metadata stays
    /// valid; centralised here alongside `userId()`.
    static func deviceId() -> String {
        if let existing = UserDefaults.standard.string(forKey: deviceIdKey) {
            return existing
        }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: deviceIdKey)
        return id
    }
}
