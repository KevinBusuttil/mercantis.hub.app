import Foundation
import Combine
import MercantisCore

/// Local persistence for the user's custom (saved) reports.
///
/// Hub is an offline-first single-user workspace, so saved reports live in
/// `UserDefaults` as a JSON array — the same lightweight strategy used by
/// `HubVisibilitySettings` / `HubIdentity`. The store is the single source of
/// truth the Custom Reports UI observes; mutating it republishes `reports`.
final class HubSavedReportStore: ObservableObject {

    static let defaultsKey = "MercantisHub.savedReports"

    /// All saved reports, kept sorted by name for stable presentation.
    @Published private(set) var reports: [SavedReportDefinition] = []

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = HubSavedReportStore.defaultsKey) {
        self.defaults = defaults
        self.key = key
        self.reports = load()
    }

    // MARK: - Reads

    func get(id: String) -> SavedReportDefinition? {
        reports.first { $0.id == id }
    }

    /// Saved reports the given user may open (their own private ones plus any
    /// shared). Mirrors `SavedReportDefinition.canBeAccessed`.
    func accessibleReports(forUserId userId: String) -> [SavedReportDefinition] {
        reports.filter { $0.canBeAccessed(byUserId: userId) }
    }

    // MARK: - Writes

    /// Insert or replace a saved report (matched by id), stamping `updatedAt`,
    /// then persist.
    func save(_ report: SavedReportDefinition) {
        var updated = report
        updated.updatedAt = Date()
        var next = reports.filter { $0.id != updated.id }
        next.append(updated)
        commit(next)
    }

    /// Rename a saved report in place.
    func rename(id: String, to name: String) {
        guard var report = get(id: id) else { return }
        report.name = name
        save(report)
    }

    func delete(id: String) {
        commit(reports.filter { $0.id != id })
    }

    // MARK: - Persistence

    private func commit(_ next: [SavedReportDefinition]) {
        let sorted = next.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        reports = sorted
        persist(sorted)
    }

    private func persist(_ reports: [SavedReportDefinition]) {
        do {
            let data = try Self.encoder.encode(reports)
            defaults.set(data, forKey: key)
        } catch {
            // A failed encode shouldn't take the app down; the in-memory list
            // stays correct for this session even if it didn't persist.
            assertionFailure("Failed to persist saved reports: \(error)")
        }
    }

    private func load() -> [SavedReportDefinition] {
        guard let data = defaults.data(forKey: key) else { return [] }
        let decoded = (try? Self.decoder.decode([SavedReportDefinition].self, from: data)) ?? []
        return decoded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
