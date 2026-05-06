import SwiftUI
import MercantisCore

@main
struct mercantis_hubApp: App {

    let documentEngine: DocumentEngine
    let workflowEngine: WorkflowEngine

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

        self.documentEngine = DocumentEngine(
            database: database,
            registry: registry,
            deviceId: Self.deviceId(),
            userId: "kevin"
        )
        // Wall 6: Hub uses Core's WorkflowEngine for post-submit state
        // transitions. The convenience init wires
        // WorkflowTransitionHistoryWriter so every transition persists
        // into `workflow_transitions` automatically (Phase A / ADR-038).
        self.workflowEngine = WorkflowEngine(database: database)
    }

    var body: some Scene {
        WindowGroup {
            RootView(engine: documentEngine, workflowEngine: workflowEngine)
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
