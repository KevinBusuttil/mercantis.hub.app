import SwiftUI
import MercantisCore
import MercantisCoreUI

/// Phase 3 — the accountant export pack. The owner ticks the statements their
/// accountant asked for and exports them as a folder of CSVs to hand over. No
/// accounting knowledge needed — just "here's everything, in one place".
struct HubAccountantExportView: View {

    let engine: DocumentEngine

    private struct ReportChoice: Identifiable {
        let id: String      // HubReports report id
        let name: String
        let detail: String
    }

    private let choices: [ReportChoice] = [
        .init(id: "trial-balance",   name: "Trial Balance",   detail: "Every account's debit/credit totals — the accountant's starting point."),
        .init(id: "income-statement", name: "Profit & Loss",  detail: "Income and expenses for the period, with net profit."),
        .init(id: "balance-sheet",   name: "Balance Sheet",   detail: "What you own and owe, and your equity."),
        .init(id: "general-ledger",  name: "General Ledger",  detail: "Every posted transaction, grouped by account."),
        .init(id: "vat-summary",     name: "Tax Summary",     detail: "Tax collected and paid, by code."),
    ]

    @State private var selected: Set<String> = ["trial-balance", "income-statement", "balance-sheet", "general-ledger", "vat-summary"]
    @State private var message: String?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                MercantisInspectorCard("Choose what to include", systemImage: "checklist") {
                    VStack(spacing: 0) {
                        ForEach(choices) { choice in
                            choiceRow(choice)
                            if choice.id != choices.last?.id { Divider() }
                        }
                    }
                }
                actions
                if let message { banner(message, "checkmark.seal.fill", MercantisTheme.success) }
                if let error { banner(error, "exclamationmark.triangle.fill", MercantisTheme.danger) }
            }
            .padding(24)
            .frame(maxWidth: 680, alignment: .leading)
        }
        .navigationTitle("Accountant Export")
        .onAppear { error = nil; message = nil }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pack for your accountant").font(.title2).bold()
            Text("Export your books as a tidy set of spreadsheets your accountant can open anywhere. Pick what to include and we'll save them together in one folder.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func choiceRow(_ choice: ReportChoice) -> some View {
        Toggle(isOn: binding(for: choice.id)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(choice.name).font(.system(size: 14, weight: .medium))
                Text(choice.detail).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .padding(.vertical, 8)
    }

    private var actions: some View {
        HStack {
            Spacer()
            Button {
                exportPack()
            } label: {
                Text("Export pack").frame(minWidth: 150)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(selected.isEmpty)
        }
    }

    // MARK: - Actions

    private func exportPack() {
        message = nil; error = nil
        var named: [HubReportPackExporter.NamedReport] = []
        for choice in choices where selected.contains(choice.id) {
            if let result = try? HubReports.runResult(reportId: choice.id, engine: engine) {
                named.append(.init(name: choice.name, result: result))
            }
        }
        guard !named.isEmpty else {
            error = "Couldn't build any of the selected reports."
            return
        }
        #if os(macOS)
        do {
            switch try HubReportPackExporter.export(named, suggestedName: suggestedFolderName) {
            case .saved(_, let count):
                message = "Saved \(count) report\(count == 1 ? "" : "s") to your chosen folder."
            case .cancelled:
                break
            }
        } catch {
            self.error = (error as NSError).localizedDescription
        }
        #else
        message = "Export is available on macOS."
        #endif
    }

    private var suggestedFolderName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "Accountant Pack \(formatter.string(from: Date()))"
    }

    // MARK: - Helpers

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selected.contains(id) },
            set: { isOn in
                if isOn { selected.insert(id) } else { selected.remove(id) }
                message = nil
            }
        )
    }

    private func banner(_ text: String, _ system: String, _ tone: Color) -> some View {
        Label(text, systemImage: system)
            .font(.callout).foregroundStyle(tone)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(tone.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }
}
