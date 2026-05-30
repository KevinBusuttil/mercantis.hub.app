import SwiftUI
import MercantisCore

/// SwiftUI consumer of `DashboardEngine.resolve(dashboardId:)`. Renders
/// each `DashboardWidgetResult` case as a self-contained tile so one
/// failed widget doesn't blank the dashboard.
struct HubDashboardView: View {

    let dashboardId: String
    let dashboardTitle: String
    let dashboardEngine: DashboardEngine
    let onSelect: (HubMenuItem) -> Void

    @State private var result: DashboardResult?
    @State private var errorMessage: String?

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 360), spacing: 16)
    ]

    var body: some View {
        Group {
            if let result {
                content(result)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("\(dashboardTitle) isn't available yet", systemImage: "chart.bar.doc.horizontal")
                } description: {
                    Text("This dashboard will summarise your business as soon as there's data to show. Create some records first, then come back.\n\nDetails: \(errorMessage)")
                }
            } else {
                ProgressView("Loading \(dashboardTitle)…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear(perform: load)
        .onChange(of: dashboardId) { _, _ in load() }
    }

    // MARK: - Content

    private func content(_ result: DashboardResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Array(result.widgets.enumerated()), id: \.offset) { (_, widget) in
                        tile(for: widget)
                    }
                }
            }
            .padding(20)
        }
    }

    private var header: some View {
        HStack {
            Text(dashboardTitle)
                .font(.title3.weight(.semibold))
            Spacer()
            Button("Refresh", systemImage: "arrow.clockwise") { load() }
                .labelStyle(.iconOnly)
        }
    }

    // MARK: - Tile dispatch

    @ViewBuilder
    private func tile(for widget: DashboardWidgetResult) -> some View {
        switch widget {
        case .count(let title, let value, let docType):
            countTile(title: title, value: value, docType: docType)
        case .list(let title, let columns, let rows, _):
            listTile(title: title, columns: columns, rows: rows)
        case .chart(let title, let columns, let rows, _):
            listTile(title: title, columns: columns, rows: rows)
        case .shortcut(let title, let target):
            shortcutTile(title: title, target: target)
        case .error(let title, let reason):
            errorTile(title: title, reason: reason)
        }
    }

    // MARK: - Concrete tiles

    private func countTile(title: String, value: Int, docType: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("\(value)")
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
            if !docType.isEmpty {
                Text(docType)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .tileChrome()
    }

    private func listTile(title: String, columns: [String], rows: [[String?]]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if rows.isEmpty {
                Text("Nothing to show yet — this fills in as you add records.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(rows.prefix(10).indices, id: \.self) { idx in
                        let row = rows[idx]
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.first.flatMap { $0 } ?? "—")
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(row.last.flatMap { $0 } ?? "")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            Text("\(columns.count) cols · \(rows.count) rows")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .tileChrome()
    }

    private func shortcutTile(title: String, target: String) -> some View {
        Button {
            handleShortcut(target: target)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(target)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.forward.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.tint.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func errorTile(title: String, reason: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            Text(reason)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .tileChrome()
    }

    // MARK: - Shortcut routing

    private func handleShortcut(target: String) {
        if target.hasPrefix("doctype:") {
            let id = String(target.dropFirst("doctype:".count))
            if let doctype = HubManifest.docType(for: id) {
                onSelect(.docType(doctype))
            }
        } else if target.hasPrefix("report:") {
            let id = String(target.dropFirst("report:".count))
            if let report = HubReports.report(forId: id) {
                onSelect(.report(id: report.id, label: report.name))
            }
        } else if target.hasPrefix("dashboard:") {
            let id = String(target.dropFirst("dashboard:".count))
            if let dash = HubDashboards.dashboard(forId: id) {
                onSelect(.dashboard(id: dash.id, label: dash.name))
            }
        }
    }

    // MARK: - Load

    private func load() {
        do {
            result = try dashboardEngine.resolve(dashboardId: dashboardId)
            errorMessage = nil
        } catch {
            result = nil
            errorMessage = String(describing: error)
        }
    }
}

private extension View {
    /// Shared tile chrome — material background, rounded corners, soft border.
    func tileChrome() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.secondary.opacity(0.18), lineWidth: 1)
            )
    }
}
