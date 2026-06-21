import SwiftUI
import MercantisCore
import MercantisCoreUI

/// Customer-accounts overview: every customer with their open receivable
/// balance, summed live from submitted Sales Invoices' `outstanding_amount`.
/// A KPI strip totals the receivable book; the table lists per-customer
/// balances with a Due / Clear indicator.
///
/// Ported from the Flutter `CustomerAccountScreen`. Wired to real data: it
/// reads `Customer` masters and submitted `SalesInvoice` outstanding balances
/// directly from the engine.
struct CustomerAccountView: View {
    let engine: DocumentEngine

    private struct Row: Identifiable {
        let customerId: String
        let customerName: String
        let openInvoices: Int
        let outstanding: Double
        var id: String { customerId }
    }

    @State private var rows: [Row] = []
    @State private var loaded = false

    private var totalReceivable: Double { rows.reduce(0) { $0 + $1.outstanding } }
    private var withBalance: Int { rows.filter { $0.outstanding > 0 }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MercantisPanelHeader("Customer accounts", systemImage: "person.2")
                Text("Receivables by customer")
                    .font(.callout)
                    .foregroundStyle(MercantisTheme.textSecondary)

                if rows.isEmpty {
                    emptyState
                } else {
                    kpiStrip
                    Text("Balances")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(MercantisTheme.textPrimary)
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

    private var kpiStrip: some View {
        HStack(spacing: 12) {
            kpiCard(title: "Total receivable", value: money(totalReceivable),
                    subtitle: "\(withBalance) customer(s) with balance",
                    systemImage: "creditcard")
            kpiCard(title: "Customers", value: "\(rows.count)",
                    subtitle: "on file", systemImage: "person.2")
        }
    }

    private func kpiCard(title: String, value: String, subtitle: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MercantisTheme.textSecondary)
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(MercantisTheme.textPrimary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(MercantisTheme.textTertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(MercantisTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(MercantisTheme.hairline, lineWidth: 1)
        )
    }

    private var table: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Customer").frame(maxWidth: .infinity, alignment: .leading)
                Text("Open").frame(width: 70, alignment: .trailing)
                Text("Outstanding").frame(width: 120, alignment: .trailing)
                Text("").frame(width: 70, alignment: .trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(MercantisTheme.textSecondary)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            Divider()
            ForEach(rows) { row in
                HStack {
                    Text(row.customerName)
                        .foregroundStyle(MercantisTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(row.openInvoices)")
                        .monospacedDigit()
                        .frame(width: 70, alignment: .trailing)
                    Text(money(row.outstanding))
                        .monospacedDigit()
                        .frame(width: 120, alignment: .trailing)
                    Text(row.outstanding > 0 ? "Due" : "Clear")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(row.outstanding > 0 ? MercantisTheme.warning : MercantisTheme.success)
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
            Image(systemName: "person.2")
                .font(.system(size: 28))
                .foregroundStyle(MercantisTheme.textTertiary)
            Text(loaded ? "No customers yet" : "Loading…")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(MercantisTheme.textPrimary)
            Text("Add a customer to start tracking receivables.")
                .font(.callout)
                .foregroundStyle(MercantisTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Data

    private func reload() {
        do {
            let customers = try engine.list(docType: "Customer", applyRowAccess: false)
            let invoices = try engine.list(docType: "SalesInvoice", applyRowAccess: false)

            var outstanding: [String: Double] = [:]
            var openCount: [String: Int] = [:]
            for inv in invoices where inv.docStatus == 1 {
                let amount = double(inv.fields["outstanding_amount"])
                guard amount > 0, let customer = string(inv.fields["customer"]) else { continue }
                outstanding[customer, default: 0] += amount
                openCount[customer, default: 0] += 1
            }

            rows = customers.map { customer in
                Row(
                    customerId: customer.id,
                    customerName: string(customer.fields["customer_name"]) ?? customer.id,
                    openInvoices: openCount[customer.id] ?? 0,
                    outstanding: outstanding[customer.id] ?? 0
                )
            }
            .sorted { $0.outstanding > $1.outstanding }
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

    private func money(_ v: Double) -> String {
        String(format: "%.2f", v)
    }
}
