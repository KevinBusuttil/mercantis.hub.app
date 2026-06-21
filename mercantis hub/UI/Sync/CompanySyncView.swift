import SwiftUI
import AppKit
import MercantisCore
import MercantisCoreUI

/// Connect this device to a shared company folder (iCloud Drive / Dropbox /
/// OneDrive / a network share) and sync documents across everyone pointed at
/// the same folder. Serverless: the folder is the only "cloud".
///
/// Swift port of Flutter's `CompanySyncScreen` (`lib/screens/company_sync_screen.dart`).
/// The engine is owned at app scope and injected as an `@ObservedObject` so the
/// background sync machinery outlives this view.
struct CompanySyncView: View {

    @ObservedObject var sync: CompanySync

    private var status: SyncStatus { sync.status }
    private var isSyncing: Bool { status.phase == .syncing }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if status.connected {
                    connectedCard
                    actions
                    backgroundSyncToggle
                } else {
                    notConnectedCard
                }

                Divider()
                statusSection
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Company Sync")
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(MercantisTheme.brandPrimary)
                Text("Company Sync")
                    .font(.largeTitle.weight(.semibold))
            }
            Text("Share this company across devices by pointing each one at the "
                 + "same folder in your iCloud Drive, Dropbox, or OneDrive. There "
                 + "is no server — the folder is the cloud.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 640, alignment: .leading)
        }
    }

    // MARK: - Not connected

    private var notConnectedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Not connected")
                .font(.headline)
            Text("Create a folder in your cloud drive (or open one a colleague "
                 + "shared with you), then connect to it.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button(action: pickFolder) {
                Label("Connect shared folder…", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Connected

    private var connectedCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.icloud")
                .font(.system(size: 22))
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Connected")
                    .font(.headline)
                Text(status.folder ?? "")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button(action: { Task { await sync.syncNow() } }) {
                HStack(spacing: 6) {
                    if isSyncing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    Text(isSyncing ? "Syncing…" : "Sync now")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSyncing)

            HStack(spacing: 8) {
                Button(action: pickFolder) {
                    Label("Change folder…", systemImage: "folder")
                }
                .disabled(isSyncing)

                Button(role: .destructive, action: sync.disconnect) {
                    Label("Disconnect", systemImage: "link.badge.plus")
                }
                .disabled(isSyncing)
                Spacer()
            }
        }
    }

    private var backgroundSyncToggle: some View {
        Toggle(isOn: Binding(
            get: { status.autoEnabled },
            set: { sync.setAutoEnabled($0) }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Background sync")
                Text("Sync automatically every 30s, after changes, and on resume")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
    }

    // MARK: - Status

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status")
                .font(.headline)

            kv("This device", shortDeviceId(status.deviceId))
            kv("Pending changes", "\(status.pending)")
            kv("Last synced",
               status.lastSyncedAt.map(Self.formatTime) ?? "—")
            if status.lastSyncedAt != nil {
                kv("Last exchange",
                   "↑ \(status.lastPushed) pushed   ↓ \(status.lastPulled) pulled")
            }
            if status.phase == .error, let message = status.message {
                Text("Sync failed: \(message)")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.top, 4)
            }
        }
    }

    private func kv(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)
            Text(value)
                .font(.callout)
            Spacer()
        }
    }

    // MARK: - Actions

    /// Open an `NSOpenPanel` configured for choosing a single folder, then hand
    /// the chosen URL to the engine (which mints + persists the security-scoped
    /// bookmark and runs an initial exchange).
    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose the shared company folder"
        panel.prompt = "Connect"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            sync.connect(to: url)
        }
    }

    // MARK: - Formatting

    private func shortDeviceId(_ id: String) -> String {
        id.count > 8 ? "\(id.prefix(8))…" : id
    }

    nonisolated private static func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
