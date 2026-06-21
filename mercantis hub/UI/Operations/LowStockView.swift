import SwiftUI
import MercantisCore
import MercantisCoreUI

/// Items whose on-hand quantity has dropped to or below their reorder level.
/// On-hand quantities are the materialised `Bin` (Stock Balance) rows that
/// `StockBalanceService` maintains from the Stock Ledger, so the figures match
/// the Stock on Hand report and POS/Delivery availability lookups.
///
/// Ported from the Flutter `LowStockScreen`. Wired to the real stock-balance
/// spine via `StockBalanceService`.
///
/// ### Reorder-threshold note
/// The Swift Hub `Item` DocType does not (yet) declare a `reorder_level`
/// field, whereas the Flutter `Item` does. This view reads `reorder_level`
/// from the Item document when present (e.g. added as an end-user custom
/// field) and otherwise treats the threshold as 0 — i.e. it flags items that
/// have gone to zero / negative on-hand. Add a `reorder_level` field (or the
/// custom field) to the Item to get a true below-reorder list.
struct LowStockView: View {
    let engine: DocumentEngine

    private struct Row: Identifiable {
        let itemCode: String
        let itemName: String
        let warehouse: String
        let qty: Double
        let reorderLevel: Double
        let uom: String
        var id: String { "\(itemCode)\u{1}\(warehouse)" }
    }

    @State private var rows: [Row] = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MercantisPanelHeader("Low stock", systemImage: "exclamationmark.triangle")
                Text(loaded ? "\(rows.count) item(s) at or below reorder level" : "Loading…")
                    .font(.callout)
                    .foregroundStyle(MercantisTheme.textSecondary)

                if rows.isEmpty {
                    emptyState
                } else {
                    table
                }
            }
            .padding(20)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(MercantisTheme.appBackground)
        .onAppear(perform: reload)
    }

    private var table: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Item").frame(maxWidth: .infinity, alignment: .leading)
                Text("Warehouse").frame(width: 140, alignment: .leading)
                Text("On hand").frame(width: 90, alignment: .trailing)
                Text("Reorder").frame(width: 80, alignment: .trailing)
                Text("").frame(width: 70, alignment: .trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(MercantisTheme.textSecondary)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            Divider()
            ForEach(rows) { row in
                HStack {
                    Text(row.itemName.isEmpty ? row.itemCode : "\(row.itemCode) · \(row.itemName)")
                        .foregroundStyle(MercantisTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.warehouse).frame(width: 140, alignment: .leading)
                        .foregroundStyle(MercantisTheme.textSecondary)
                    Text("\(qtyText(row.qty)) \(row.uom)")
                        .monospacedDigit().frame(width: 90, alignment: .trailing)
                    Text(qtyText(row.reorderLevel))
                        .monospacedDigit().frame(width: 80, alignment: .trailing)
                    Text("Below")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MercantisTheme.danger)
                        .frame(width: 70, alignment: .trailing)
                }
                .font(.callout)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                Divider()
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(MercantisTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(MercantisTheme.hairline, lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 28))
                .foregroundStyle(MercantisTheme.success)
            Text(loaded ? "Nothing below reorder" : "Loading…")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(MercantisTheme.textPrimary)
            Text("Items show here once on-hand qty drops to or below their reorder level.")
                .font(.callout)
                .foregroundStyle(MercantisTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Data

    private func reload() {
        do {
            let items = try engine.list(docType: "Item", applyRowAccess: false)
            // Build item metadata: code, name, uom, reorder threshold.
            var meta: [String: (code: String, name: String, uom: String, reorder: Double)] = [:]
            for item in items {
                meta[item.id] = (
                    code: string(item.fields["item_code"]) ?? item.id,
                    name: string(item.fields["item_name"]) ?? "",
                    uom: string(item.fields["stock_uom"]) ?? "",
                    reorder: double(item.fields["reorder_level"]) // 0 when absent
                )
            }

            // All materialised Bin rows; flag those at/below the item's reorder.
            let bins = try engine.list(docType: "Bin", applyRowAccess: false)
            rows = bins.compactMap { bin -> Row? in
                guard let itemId = string(bin.fields["item"]) else { return nil }
                let qty = double(bin.fields["actual_qty"])
                let info = meta[itemId]
                let reorder = info?.reorder ?? 0
                guard qty <= reorder else { return nil }
                return Row(
                    itemCode: info?.code ?? itemId,
                    itemName: info?.name ?? "",
                    warehouse: string(bin.fields["warehouse"]) ?? "—",
                    qty: qty,
                    reorderLevel: reorder,
                    uom: info?.uom ?? ""
                )
            }
            .sorted { $0.qty < $1.qty }
            loaded = true
        } catch {
            rows = []
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

    private func qtyText(_ value: Double) -> String {
        String(format: "%.0f", value)
    }
}
