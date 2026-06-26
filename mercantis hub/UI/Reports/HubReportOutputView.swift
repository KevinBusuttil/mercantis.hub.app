import SwiftUI
import Charts
import MercantisCore

/// Renders a projected report: an optional chart above a grouped table with
/// group headers, per-group subtotals and a grand total. Shared by the Report
/// Builder's live preview and the saved-report runner so both look identical.
struct HubReportOutputView: View {

    let table: HubReportProjection.Table?
    let chartPoints: [HubReportProjection.ChartPoint]
    let chartKind: SavedReportChartKind?
    var errorMessage: String? = nil
    var emptyText: String = "No matching records."

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(MercantisTheme.danger)
            }
            if let chartKind, !chartPoints.isEmpty {
                chart(kind: chartKind)
                    .frame(height: 240)
                    .padding(12)
                    .background(MercantisTheme.surface, in: RoundedRectangle(cornerRadius: 10))
            }
            if let table {
                tableView(table)
            }
        }
    }

    // MARK: - Chart

    @ViewBuilder
    private func chart(kind: SavedReportChartKind) -> some View {
        Chart(chartPoints) { point in
            switch kind {
            case .bar:
                BarMark(x: .value("Category", point.category), y: .value("Value", point.value))
                    .foregroundStyle(MercantisTheme.brandPrimary)
            case .line:
                LineMark(x: .value("Category", point.category), y: .value("Value", point.value))
                    .foregroundStyle(MercantisTheme.brandPrimary)
                PointMark(x: .value("Category", point.category), y: .value("Value", point.value))
                    .foregroundStyle(MercantisTheme.brandPrimary)
            case .pie:
                SectorMark(angle: .value("Value", point.value), innerRadius: .ratio(0.55))
                    .foregroundStyle(by: .value("Category", point.category))
            }
        }
    }

    // MARK: - Table

    private func tableView(_ table: HubReportProjection.Table) -> some View {
        let columnCount = table.columnLabels.count
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(table.columnLabels.enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MercantisTheme.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                }
            }
            .padding(.vertical, 6)
            .background(MercantisTheme.surfaceMuted)
            Divider()
            if table.rows.isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                ForEach(table.rows) { row in
                    rowView(row, columnCount: columnCount)
                    Divider().opacity(0.3)
                }
            }
        }
        .background(MercantisTheme.surface, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func rowView(_ row: HubReportProjection.DisplayRow, columnCount: Int) -> some View {
        switch row.kind {
        case .groupHeader:
            HStack {
                Text(row.cells.first.flatMap { $0 } ?? "")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MercantisTheme.brandPrimary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(MercantisTheme.brandPrimarySoft.opacity(0.5))
        case .subtotal:
            cells(row.cells, columnCount: columnCount, weight: .semibold)
                .background(MercantisTheme.surfaceMuted.opacity(0.5))
        case .grandTotal:
            cells(row.cells, columnCount: columnCount, weight: .semibold)
                .background(MercantisTheme.surfaceMuted)
        case .data:
            cells(row.cells, columnCount: columnCount, weight: .regular)
        }
    }

    private func cells(_ values: [String?], columnCount: Int, weight: Font.Weight) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<columnCount, id: \.self) { index in
                Text(index < values.count ? (values[index] ?? "") : "")
                    .font(.system(size: 12, weight: weight))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 5)
    }
}
