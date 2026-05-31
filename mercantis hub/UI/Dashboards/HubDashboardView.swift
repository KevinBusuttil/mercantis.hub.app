import SwiftUI
import MercantisCore
import MercantisCoreUI

/// SwiftUI consumer of `DashboardEngine.resolve(dashboardId:)`. Renders each
/// `DashboardWidgetResult` case as a self-contained card so one failed widget
/// doesn't blank the dashboard.
///
/// Layout mirrors the polished business-dashboard direction
/// (`Docs/HIG-COMPLIANT-VISUAL-THEME.md`): a compact header, a KPI row built
/// from the dashboard's `count` widgets, then a card grid for the remaining
/// list / chart / shortcut widgets. Everything stays data-driven — there are no
/// hard-coded business values; widgets with no data fall back to soft empty
/// states.
struct HubDashboardView: View {

    let dashboardId: String
    let dashboardTitle: String
    let dashboardEngine: DashboardEngine
    let onSelect: (HubMenuItem) -> Void

    @State private var result: DashboardResult?
    @State private var errorMessage: String?

    /// KPI row — compact, several across.
    private let kpiColumns = [
        GridItem(.adaptive(minimum: 180, maximum: 280), spacing: 12)
    ]
    /// Main widget grid — roomier cards for lists / charts / shortcuts.
    private let widgetColumns = [
        GridItem(.adaptive(minimum: 260, maximum: 420), spacing: 16)
    ]

    var body: some View {
        Group {
            if let result {
                content(result)
            } else if let errorMessage {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        MercantisCard {
                            MercantisEmptyState(
                                systemImage: "chart.bar.doc.horizontal",
                                title: "\(dashboardTitle) isn't available yet",
                                message: "This dashboard summarises your business as soon as there's data to show. Create some records, then come back.",
                                actionTitle: "Try again"
                            ) { load() }
                        }
                        // Keep the underlying reason available but de-emphasised.
                        Text(errorMessage)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }
                    .padding(20)
                }
            } else {
                ProgressView("Loading \(dashboardTitle)…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(MercantisTheme.appBackground)
        .onAppear(perform: load)
        .onChange(of: dashboardId) { _, _ in load() }
    }

    // MARK: - Content

    private func content(_ result: DashboardResult) -> some View {
        // Split count widgets (KPIs) from the rest so the top row reads like the
        // reference's metric strip and the body holds the richer cards.
        let metrics = result.widgets.compactMap { widget -> MetricSpec? in
            if case let .count(title, value, docType) = widget {
                return MetricSpec(title: title, value: value, docType: docType)
            }
            return nil
        }
        let others = result.widgets.filter {
            if case .count = $0 { return false }
            return true
        }

        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if !metrics.isEmpty {
                    LazyVGrid(columns: kpiColumns, spacing: 12) {
                        ForEach(Array(metrics.enumerated()), id: \.offset) { _, m in
                            metricCard(m)
                        }
                    }
                }

                if !others.isEmpty {
                    LazyVGrid(columns: widgetColumns, spacing: 16) {
                        ForEach(Array(others.enumerated()), id: \.offset) { _, widget in
                            tile(for: widget)
                        }
                    }
                } else if metrics.isEmpty {
                    MercantisCard {
                        MercantisEmptyState(
                            systemImage: "rectangle.on.rectangle.angled",
                            title: "Nothing to summarise yet",
                            message: "Add a few records and this dashboard fills in automatically."
                        )
                    }
                }
            }
            .padding(20)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dashboardTitle)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(MercantisTheme.textPrimary)
                Text("Overview of your business activity")
                    .font(.system(size: 12))
                    .foregroundStyle(MercantisTheme.textSecondary)
            }
            Spacer()
            Button {
                load()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh dashboard")
        }
    }

    // MARK: - Tile dispatch

    @ViewBuilder
    private func tile(for widget: DashboardWidgetResult) -> some View {
        switch widget {
        case .count(let title, let value, let docType):
            // Counts are normally promoted to the KPI row, but render defensively
            // in case dispatch reaches here.
            metricCard(MetricSpec(title: title, value: value, docType: docType))
        case .list(let title, let columns, let rows, let docType):
            listTile(title: title, columns: columns,
                     rows: displayRows(columns: columns, rows: rows, docType: docType))
        case .chart(let title, let columns, let rows, _):
            listTile(title: title, columns: columns, rows: rows)
        case .shortcut(let title, let target):
            shortcutTile(title: title, target: target)
        case .error(let title, let reason):
            errorTile(title: title, reason: reason)
        }
    }

    /// Replaces raw values in a "status" column with the document-specific
    /// business label (e.g. "Submitted" → "Posted") so dashboard list tiles
    /// match the wording used everywhere else. Other columns pass through.
    private func displayRows(columns: [String], rows: [[String?]], docType: String) -> [[String?]] {
        guard !docType.isEmpty,
              let statusIdx = columns.firstIndex(where: { $0.lowercased() == "status" })
        else { return rows }
        return rows.map { row in
            guard statusIdx < row.count, let raw = row[statusIdx], !raw.isEmpty else { return row }
            var copy = row
            copy[statusIdx] = HubWorkflowDisplayPolicy.policy
                .statusDisplay(docTypeId: docType, state: raw).label
            return copy
        }
    }

    // MARK: - Concrete cards

    private struct MetricSpec {
        let title: String
        let value: Int
        let docType: String
    }

    private func metricCard(_ spec: MetricSpec) -> some View {
        MercantisMetricCard(
            title: spec.title,
            value: spec.value.formatted(),
            comparison: spec.docType.isEmpty ? nil : friendlyDocType(spec.docType),
            systemImage: metricSymbol(title: spec.title, docType: spec.docType)
        )
    }

    private func listTile(title: String, columns: [String], rows: [[String?]]) -> some View {
        // A `status` column is rendered as a badge; numeric-looking trailing
        // values are right-aligned and monospaced so the card reads like a
        // compact business table rather than a debug dump.
        let statusIdx = columns.firstIndex { $0.lowercased() == "status" }
        return MercantisCard(padding: .compact) {
            VStack(alignment: .leading, spacing: 10) {
                MercantisPanelHeader(title, systemImage: "list.bullet.rectangle") {
                    Text("\(rows.count)")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(MercantisTheme.textSecondary)
                }

                if rows.isEmpty {
                    MercantisEmptyState(
                        systemImage: "tray",
                        title: "Nothing yet",
                        message: "Fills in as you add records."
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(rows.prefix(8).indices, id: \.self) { idx in
                            listRow(rows[idx], statusIdx: statusIdx)
                            if idx < min(rows.count, 8) - 1 {
                                Divider().overlay(MercantisTheme.hairline)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func listRow(_ row: [String?], statusIdx: Int?) -> some View {
        let primary = row.first.flatMap { $0 } ?? "—"
        let trailing = row.last.flatMap { $0 } ?? ""
        let trailingIsStatus = statusIdx != nil && statusIdx == row.count - 1
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(primary)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MercantisTheme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if trailingIsStatus, !trailing.isEmpty {
                MercantisStatusBadge(trailing)
            } else {
                Text(trailing)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(MercantisTheme.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 5)
    }

    private func shortcutTile(title: String, target: String) -> some View {
        Button {
            handleShortcut(target: target)
        } label: {
            MercantisCard(padding: .compact, tinted: true) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(MercantisTheme.textPrimary)
                        Text(friendlyTarget(target))
                            .font(.caption2)
                            .foregroundStyle(MercantisTheme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "arrow.forward.circle.fill")
                        .font(.title3)
                        .foregroundStyle(MercantisTheme.brandPrimary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text("Opens \(friendlyTarget(target))"))
    }

    private func errorTile(title: String, reason: String) -> some View {
        MercantisCard(padding: .compact) {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MercantisTheme.warning)
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(MercantisTheme.textSecondary)
            }
        }
    }

    // MARK: - Presentation helpers

    /// Turns a raw docType id ("SalesOrder") into spaced words ("Sales Order").
    private func friendlyDocType(_ id: String) -> String {
        var out = ""
        for (i, ch) in id.enumerated() {
            if i > 0, ch.isUppercase { out.append(" ") }
            out.append(ch)
        }
        return out
    }

    private func friendlyTarget(_ target: String) -> String {
        if let colon = target.firstIndex(of: ":") {
            return friendlyDocType(String(target[target.index(after: colon)...]))
        }
        return target
    }

    /// Best-effort SF Symbol for a KPI, derived from the docType then the title.
    private func metricSymbol(title: String, docType: String) -> String {
        let key = (docType.isEmpty ? title : docType).lowercased()
        if key.contains("customer") { return "person.2" }
        if key.contains("invoice") { return "doc.text" }
        if key.contains("order") { return "cart" }
        if key.contains("item") { return "shippingbox" }
        if key.contains("warehouse") { return "building.2" }
        if key.contains("stock") || key.contains("ledger") { return "tray.full" }
        if key.contains("account") { return "creditcard" }
        if key.contains("payment") { return "banknote" }
        if key.contains("journal") { return "book.closed" }
        if key.contains("bom") { return "square.stack.3d.up" }
        if key.contains("work") { return "hammer" }
        if key.contains("production") { return "gearshape.2" }
        return "number"
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
