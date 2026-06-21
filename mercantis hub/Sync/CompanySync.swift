import Foundation
import Combine
import AppKit
import MercantisCore

/// Phase of the company-sync engine, mirrored from the Flutter port's
/// `SyncPhase` (`company_sync.dart`).
public enum SyncPhase: Sendable {
    case idle
    case syncing
    case error
}

/// An immutable snapshot of the company-sync state, published to the UI.
/// Mirrors Flutter's `SyncStatus` value type.
public struct SyncStatus: Sendable, Equatable {
    /// Display path of the connected shared folder, or `nil` when not joined
    /// to a company. (Resolved from the persisted security-scoped bookmark.)
    public var folder: String?
    public var deviceId: String

    /// Whether background sync (timer + on-change + on-resume) is on.
    public var autoEnabled: Bool
    public var phase: SyncPhase

    /// Local changes still waiting to be pushed.
    public var pending: Int
    public var lastSyncedAt: Date?
    public var lastPushed: Int
    public var lastPulled: Int
    public var message: String?

    public var connected: Bool { (folder?.isEmpty == false) }

    public init(
        folder: String? = nil,
        deviceId: String,
        autoEnabled: Bool = true,
        phase: SyncPhase = .idle,
        pending: Int = 0,
        lastSyncedAt: Date? = nil,
        lastPushed: Int = 0,
        lastPulled: Int = 0,
        message: String? = nil
    ) {
        self.folder = folder
        self.deviceId = deviceId
        self.autoEnabled = autoEnabled
        self.phase = phase
        self.pending = pending
        self.lastSyncedAt = lastSyncedAt
        self.lastPushed = lastPushed
        self.lastPulled = lastPulled
        self.message = message
    }
}

/// Drives serverless multi-user sync of the company file across devices: a
/// shared folder is the "cloud" (Core's `FileSystemCloudAdapter`, ADR-047).
///
/// This is the Hub Swift port of Flutter's `CompanySyncNotifier`
/// (`lib/sync/company_sync.dart`). It sits **on top of** Core's existing
/// `SyncEngine` / `CloudAdapter` rather than reinventing mutation transport:
/// a sync run is *push local pending mutations → pull + apply peers' mutations
/// → re-derive local balances → refresh the UI*.
///
/// On macOS the shared folder is reached through a **security-scoped bookmark**
/// (the user picks it once via `NSOpenPanel`; the bookmark is persisted in
/// `UserDefaults` and re-resolved on launch). Each device mounts the folder at
/// its own path, so the bookmark (and the auto-sync flag) are device-local and
/// never live in a synced document — matching the Flutter `SharedPreferences`
/// strategy.
///
/// When connected and auto-sync is on it also syncs in the background: on a
/// 30s timer, shortly after local document changes (debounced), and on app
/// foreground (`NSApplication.didBecomeActiveNotification`).
@MainActor
public final class CompanySync: ObservableObject {

    /// The single source of truth the UI binds to.
    @Published public private(set) var status: SyncStatus

    // MARK: - Injected Core handles

    private let database: MercantisDatabase
    private let documentEngine: DocumentEngine
    private let registry: MetadataRegistry
    private let emitter: EventEmitter
    private let deviceId: String

    /// Optional hook the host wires so balances/derived rows are recomputed
    /// after a pull brings in remote ledger mutations. Mirrors Flutter's
    /// `ledger.recomputeAllDerived()` call. Left `nil` if the host has no such
    /// pass; the append-only ledgers still replicate correctly.
    private let recomputeDerived: (() throws -> Void)?

    /// Returns the number of `sync_queue` rows still `pending` (not yet pushed),
    /// i.e. the local changes waiting to go out. Injected by the host because
    /// Core does not (yet) expose a public counter and the Hub target does not
    /// link GRDB directly — see `HUB_SYNC_WIRING.md`. Defaults to `{ 0 }`, which
    /// only affects the "Pending changes" badge, never sync correctness.
    private let pendingCountProvider: () -> Int

    // MARK: - Device-local persisted prefs

    private static let bookmarkKey = "hub.company_folder_bookmark"
    private static let autoKey = "hub.auto_sync"

    // MARK: - Background machinery

    private static let interval: TimeInterval = 30
    private static let debounceDelay: TimeInterval = 3

    /// Resolved shared-folder URL (from the security-scoped bookmark) while we
    /// hold access to it. `nil` when not connected.
    private var folderURL: URL?
    /// Whether we currently hold a security-scoped resource for `folderURL`.
    private var isAccessingScopedResource = false

    private var timer: Timer?
    private var debounce: Timer?
    private var tokens: [SubscriptionToken] = []
    private var lifecycleObserver: NSObjectProtocol?
    private var isBusy = false

    public init(
        database: MercantisDatabase,
        documentEngine: DocumentEngine,
        registry: MetadataRegistry,
        emitter: EventEmitter,
        deviceId: String,
        pendingCountProvider: @escaping () -> Int = { 0 },
        recomputeDerived: (() throws -> Void)? = nil
    ) {
        self.database = database
        self.documentEngine = documentEngine
        self.registry = registry
        self.emitter = emitter
        self.deviceId = deviceId
        self.pendingCountProvider = pendingCountProvider
        self.recomputeDerived = recomputeDerived

        let autoEnabled = (UserDefaults.standard.object(forKey: Self.autoKey) as? Bool) ?? true
        self.status = SyncStatus(deviceId: deviceId, autoEnabled: autoEnabled)

        // Resolve a previously connected folder, if any, then report initial
        // pending count and arm the background machinery.
        resolvePersistedFolder()
        self.status.pending = pendingCountProvider()
        startAuto()
    }

    deinit {
        // `stopAuto` is @MainActor; `deinit` may run off-main. Tear down the
        // non-isolated resources directly and let ARC drop the timers.
        timer?.invalidate()
        debounce?.invalidate()
        for token in tokens { token.cancel() }
        if let observer = lifecycleObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if isAccessingScopedResource {
            folderURL?.stopAccessingSecurityScopedResource()
        }
    }

    // MARK: - Public API (mirrors the Flutter notifier)

    /// Connect (or switch) the company folder and run an initial exchange.
    ///
    /// `url` is a folder the user just chose via `NSOpenPanel` (which must be
    /// configured with `canChooseDirectories = true`). We mint and persist a
    /// security-scoped bookmark so access survives relaunch, then sync.
    public func connect(to url: URL) {
        do {
            let bookmark = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
        } catch {
            status.phase = .error
            status.message = "Could not bookmark folder: \(error.localizedDescription)"
            return
        }

        releaseFolder()
        beginAccess(to: url)
        status.folder = url.path
        startAuto()
        Task { await syncNow() }
    }

    /// Forget the company folder (stops syncing; local data stays).
    public func disconnect() {
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        stopAuto()
        releaseFolder()
        status.folder = nil
        status.phase = .idle
        status.message = nil
    }

    /// Turn background sync on/off (persisted).
    public func setAutoEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.autoKey)
        status.autoEnabled = enabled
        startAuto()
    }

    /// Push local pending mutations, pull + apply peers', recompute derived
    /// rows, and refresh the published status. No-ops when not connected or a
    /// sync is already in flight.
    public func syncNow() async {
        guard status.connected, let root = folderURL, !isBusy else { return }
        isBusy = true
        status.phase = .syncing
        status.message = nil

        do {
            let pushed = pendingCountProvider()

            let adapter = try FileSystemCloudAdapter(
                rootURL: root,
                localDeviceId: deviceId
            )
            let sync = SyncEngine(
                database: database,
                documentEngine: documentEngine,
                registry: registry,
                cloudAdapter: adapter
            )

            // Snapshot the adapter's receive cursor so we can report how many
            // remote mutations this exchange ingested. `pullAndApplyRemoteMutations`
            // owns the persisted `lastServerSequence` bookmark in `sync_state`.
            let beforeReceive = adapter.currentGlobalReceiveSequence()
            try await sync.pushPendingMutations()
            try await sync.pullAndApplyRemoteMutations()
            let pulled = Int(adapter.currentGlobalReceiveSequence() - beforeReceive)

            if pulled > 0 {
                try recomputeDerived?()
            }

            status.phase = .idle
            status.pending = pendingCountProvider()
            status.lastSyncedAt = Date()
            status.lastPushed = pushed
            status.lastPulled = pulled
        } catch {
            status.phase = .error
            status.message = "\(error.localizedDescription)"
        }

        isBusy = false
    }

    // MARK: - Folder / security-scoped bookmark

    /// Re-resolve a persisted bookmark on launch and begin scoped access.
    private func resolvePersistedFolder() {
        guard let bookmark = UserDefaults.standard.data(forKey: Self.bookmarkKey) else {
            return
        }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return
        }
        // Refresh a stale bookmark in place so it keeps resolving next launch.
        if isStale,
           let refreshed = try? url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
           ) {
            UserDefaults.standard.set(refreshed, forKey: Self.bookmarkKey)
        }
        beginAccess(to: url)
        status.folder = url.path
    }

    private func beginAccess(to url: URL) {
        isAccessingScopedResource = url.startAccessingSecurityScopedResource()
        folderURL = url
    }

    private func releaseFolder() {
        if isAccessingScopedResource {
            folderURL?.stopAccessingSecurityScopedResource()
        }
        isAccessingScopedResource = false
        folderURL = nil
    }

    // MARK: - Background machinery

    /// (Re)arm the timer, the on-change subscriptions and the foreground hook to
    /// match the current folder + auto-enabled state. Idempotent.
    private func startAuto() {
        stopAuto()
        guard status.connected, status.autoEnabled else { return }

        let timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.autoSync() }
        }
        self.timer = timer

        // A submit fans out into many ledger saves; debounce so a burst of
        // local writes coalesces into a single background sync.
        tokens.append(emitter.subscribe(DocumentSavedEvent.self) { [weak self] _ in
            Task { @MainActor in self?.scheduleAuto() }
        })
        tokens.append(emitter.subscribe(DocumentSubmittedEvent.self) { [weak self] _ in
            Task { @MainActor in self?.scheduleAuto() }
        })
        tokens.append(emitter.subscribe(DocumentCancelledEvent.self) { [weak self] _ in
            Task { @MainActor in self?.scheduleAuto() }
        })

        // App foreground → opportunistic sync (mirrors Flutter's onResume).
        lifecycleObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.autoSync() }
        }
    }

    private func stopAuto() {
        timer?.invalidate()
        timer = nil
        debounce?.invalidate()
        debounce = nil
        for token in tokens { token.cancel() }
        tokens.removeAll()
        if let observer = lifecycleObserver {
            NotificationCenter.default.removeObserver(observer)
            lifecycleObserver = nil
        }
    }

    /// Coalesce a burst of local changes into a single sync shortly after
    /// activity settles.
    private func scheduleAuto() {
        guard status.autoEnabled, status.connected else { return }
        debounce?.invalidate()
        debounce = Timer.scheduledTimer(withTimeInterval: Self.debounceDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.autoSync() }
        }
    }

    private func autoSync() {
        guard status.autoEnabled, status.connected, !isBusy else { return }
        // Fire-and-forget; `syncNow` owns its own error handling and busy guard.
        Task { await syncNow() }
    }
}
