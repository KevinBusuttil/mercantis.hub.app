import SwiftUI
import MercantisCore
import MercantisCoreUI

/// Sales Orders list/detail screen on real data: the order list on the left
/// (searchable, filterable by lifecycle), the selected order's overview and
/// line items on the right. A focused operational view over the generic record
/// workspace — for full editing the user opens the Sales Orders workspace from
/// the Selling module.
///
/// Ported from the Flutter `SalesOrdersScreen`. Reads `SalesOrder` documents
/// and their `items` (`SalesItem`) child rows directly from the engine.
struct SalesOrdersView: View {
    let engine: DocumentEngine

    private enum Filter: String, CaseIterable, Identifiable {
        case all, draft, submitted, cancelled
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    @State private var orders: [Document] = []
    @State private var selectedId: String?
    @State private var filter: Filter = .all
    @State private var query: String = ""
    @State private var loaded = false

    private var filtered: [Document] {
        orders.filter { order in
            switch filter {
            case .all:       break
            case .draft:     if order.docStatus != 0 { return false }
            case .submitted: if order.docStatus != 1 { return false }
            case .cancelled: if order.docStatus != 2 { return false }
            }
            guard !query.isEmpty else { return true }
            let q = query.lowercased()
            return order.id.lowercased().contains(q)
                || (string(order.fields["customer"]) ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        Group {
            if orders.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    listPane.frame(width: 340)
                    Divider()
                    detailPane.frame(maxWidth: .infinity)
                }
            }
        }
        .background(MercantisTheme.appBackground)
        .onAppear(perform: reload)
    }

    // MARK: - List

    private var listPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Sales Orders")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MercantisTheme.textPrimary)
                Text("\(orders.count) total")
                    .font(.caption)
                    .foregroundStyle(MercantisTheme.textSecondary)
                TextField("Search by number or customer", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                Picker("Filter", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(filtered, id: \.id) { order in
                        orderRow(order)
                    }
                }
                .padding(8)
            }
        }
    }

    private func orderRow(_ order: Document) -> some View {
        Button { selectedId = order.id } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("\(order.id) · \(string(order.fields["customer"]) ?? "—")")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MercantisTheme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(money(double(order.fields["grand_total"])))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(MercantisTheme.textSecondary)
                }
                HStack {
                    statusBadge(order.docStatus)
                    Spacer()
                    if let date = dateText(order.fields["transaction_date"]) {
                        Text(date).font(.caption2).foregroundStyle(MercantisTheme.textTertiary)
                    }
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(order.id == effectiveSelection
                          ? MercantisTheme.tableRowSelection.opacity(0.82)
                          : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail

    private var effectiveSelection: String {
        selectedId ?? filtered.first?.id ?? orders.first?.id ?? ""
    }

    @ViewBuilder
    private var detailPane: some View {
        if let order = orders.first(where: { $0.id == effectiveSelection }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(order.id) · \(string(order.fields["customer"]) ?? "—")")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(MercantisTheme.textPrimary)
                            if let date = dateText(order.fields["transaction_date"]) {
                                Text(date).font(.callout).foregroundStyle(MercantisTheme.textSecondary)
                            }
                        }
                        Spacer()
                        statusBadge(order.docStatus)
                    }

                    overview(order)

                    Text("Items")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(MercantisTheme.textPrimary)
                    itemsTable(order)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("Order not found")
                .foregroundStyle(MercantisTheme.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func overview(_ order: Document) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            kv("Customer", string(order.fields["customer"]) ?? "—")
            kv("Order date", dateText(order.fields["transaction_date"]) ?? "—")
            kv("Delivery date", dateText(order.fields["delivery_date"]) ?? "—")
            kv("Currency", string(order.fields["currency"]) ?? "—")
            Divider().padding(.vertical, 4)
            kv("Grand total", money(double(order.fields["grand_total"])), bold: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(MercantisTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(MercantisTheme.hairline, lineWidth: 1))
    }

    private func itemsTable(_ order: Document) -> some View {
        let items = order.children["items"] ?? []
        return VStack(spacing: 0) {
            if items.isEmpty {
                Text("No line items")
                    .font(.callout)
                    .foregroundStyle(MercantisTheme.textSecondary)
                    .padding(16)
            } else {
                HStack {
                    Text("Qty").frame(width: 60, alignment: .trailing)
                    Text("Item").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Rate").frame(width: 90, alignment: .trailing)
                    Text("Amount").frame(width: 100, alignment: .trailing)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(MercantisTheme.textSecondary)
                .padding(.vertical, 8).padding(.horizontal, 12)
                Divider()
                ForEach(Array(items.enumerated()), id: \.offset) { _, row in
                    HStack {
                        Text(qtyText(double(row.fields["qty"]))).monospacedDigit().frame(width: 60, alignment: .trailing)
                        Text(string(row.fields["item"]) ?? "—").frame(maxWidth: .infinity, alignment: .leading)
                        Text(money(double(row.fields["rate"]))).monospacedDigit().frame(width: 90, alignment: .trailing)
                        Text(money(double(row.fields["amount"]))).monospacedDigit().frame(width: 100, alignment: .trailing)
                    }
                    .font(.callout)
                    .foregroundStyle(MercantisTheme.textPrimary)
                    .padding(.vertical, 8).padding(.horizontal, 12)
                    Divider()
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(MercantisTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(MercantisTheme.hairline, lineWidth: 1))
    }

    // MARK: - Shared

    private func kv(_ key: String, _ value: String, bold: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key).font(.callout).foregroundStyle(MercantisTheme.textSecondary).frame(width: 140, alignment: .leading)
            Text(value)
                .font(.callout.weight(bold ? .semibold : .regular))
                .foregroundStyle(MercantisTheme.textPrimary)
            Spacer()
        }
    }

    private func statusBadge(_ docStatus: Int) -> some View {
        let label: String
        let color: Color
        switch docStatus {
        case 0: label = "Draft";     color = MercantisTheme.textSecondary
        case 1: label = "Submitted"; color = MercantisTheme.success
        case 2: label = "Cancelled"; color = MercantisTheme.danger
        default: label = "Unknown";  color = MercantisTheme.textTertiary
        }
        return Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "cart")
                .font(.system(size: 28))
                .foregroundStyle(MercantisTheme.textTertiary)
            Text(loaded ? "No sales orders yet" : "Loading…")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(MercantisTheme.textPrimary)
            Text("Create a Sales Order in the Selling module to see it here.")
                .font(.callout)
                .foregroundStyle(MercantisTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data

    private func reload() {
        do {
            orders = try engine.list(
                docType: "SalesOrder",
                filters: nil,
                sortBy: [ListSort(fieldKey: "createdAt", direction: .descending)],
                applyRowAccess: false
            )
            loaded = true
        } catch {
            orders = []
            loaded = true
        }
    }

    private func string(_ v: FieldValue?) -> String? {
        if case .string(let s) = v { return s.isEmpty ? nil : s }
        return nil
    }

    private func double(_ v: FieldValue?) -> Double {
        switch v {
        case .double(let d): return d
        case .int(let i):    return Double(i)
        default:             return 0
        }
    }

    private func dateText(_ v: FieldValue?) -> String? {
        switch v {
        case .date(let d), .dateTime(let d):
            let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none
            return f.string(from: d)
        case .string(let s): return s.isEmpty ? nil : s
        default: return nil
        }
    }

    private func money(_ v: Double) -> String { String(format: "%.2f", v) }
    private func qtyText(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(v) }
}
