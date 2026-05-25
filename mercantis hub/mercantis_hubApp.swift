import SwiftUI
import MercantisCore

@main
struct mercantis_hubApp: App {

    let documentEngine: DocumentEngine
    let workflowEngine: WorkflowEngine
    /// Wall 7 — retained so its event subscriptions stay alive for the
    /// lifetime of the app. Held via a strong reference at app scope.
    let ledgerDerivation: LedgerDerivationService
    /// Wall 9 — engines for report execution and dashboard resolution.
    let reportEngine: ReportEngine
    let dashboardEngine: DashboardEngine
    /// End-user customizations (ADR-021). Persisted in the `custom_fields`
    /// table so they survive app restarts and HubManifest reinstalls.
    let customFieldStore: CustomFieldStore

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

        let documentEngine = DocumentEngine(
            database: database,
            registry: registry,
            deviceId: Self.deviceId(),
            userId: "kevin",
            eventEmitter: emitter
        )
        self.documentEngine = documentEngine
        // Wall 6: Hub uses Core's WorkflowEngine for post-submit state
        // transitions. The convenience init wires
        // WorkflowTransitionHistoryWriter so every transition persists
        // into `workflow_transitions` automatically (Phase A / ADR-038).
        self.workflowEngine = WorkflowEngine(database: database)
        // Wall 7: LedgerDerivationService listens for transactional
        // submit / cancel events and writes append-only Stock Ledger
        // Entry / GL Entry rows with deterministic ids.
        self.ledgerDerivation = LedgerDerivationService(
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

        // End-user customizations. The MigrationRunner has already created
        // the `custom_fields` table by the time we reach here; this just
        // hands the same database to the store so workspaces can read/write
        // their own fields without colliding with the HubManifest reinstall
        // that runs above.
        self.customFieldStore = CustomFieldStore(database: database)
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                engine: documentEngine,
                workflowEngine: workflowEngine,
                reportEngine: reportEngine,
                dashboardEngine: dashboardEngine,
                customFieldStore: customFieldStore
            )
        }
        .defaultSize(width: 1100, height: 720)
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

    private static func deviceId() -> String {
        let key = "MercantisHub.deviceId"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }
}
