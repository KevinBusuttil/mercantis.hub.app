import SwiftUI
import MercantisCore
import MercantisCoreUI

/// Phase 2 — guided opening balances. A micro-business moving from Excel /
/// QuickBooks / Xero types in plain figures (money in the bank, what customers
/// owe, what they owe suppliers, stock value, loans) and the app posts one
/// balanced opening Journal Entry — the owner never computes a balancing figure
/// or touches a debit/credit.
struct HubOpeningBalanceView: View {

    let engine: DocumentEngine
    let workflowEngine: WorkflowEngine
    @Environment(\.postingCoordinator) private var posting

    private struct Category: Identifiable {
        let id: String
        let label: String
        let help: String
        let account: String
        let isDebit: Bool
    }

    private let categories: [Category] = [
        .init(id: "bank",    label: "Money in the bank",        help: "Your current bank balance.",                account: "Bank",         isDebit: true),
        .init(id: "cash",    label: "Cash on hand",             help: "Notes and coins / petty cash.",             account: "Cash",         isDebit: true),
        .init(id: "ar",      label: "Money customers owe me",   help: "Total of unpaid customer invoices.",        account: "Debtors",      isDebit: true),
        .init(id: "stock",   label: "Stock / inventory value",  help: "Value of goods on hand.",                   account: "Stock",        isDebit: true),
        .init(id: "assets",  label: "Equipment & fixed assets", help: "Vehicles, machinery, fit-out.",             account: "FixedAssets",  isDebit: true),
        .init(id: "ap",      label: "Money I owe suppliers",    help: "Total of unpaid supplier bills.",           account: "Creditors",    isDebit: false),
        .init(id: "loans",   label: "Loans to repay",           help: "Outstanding business loans.",               account: "Loans",        isDebit: false),
        .init(id: "tax",     label: "Tax I owe",                help: "VAT / GST / sales tax owed at the start.",  account: "VAT",          isDebit: false),
    ]

    @State private var amounts: [String: String] = [:]
    @State private var openingDate = Date()
    @State private var currency: String?
    @State private var posted: String?
    @State private var error: String?
    @State private var loaded = false

    private let equityAccount = "OpeningBalanceEquity"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                MercantisInspectorCard("Your starting figures", systemImage: "list.bullet.rectangle") {
                    VStack(spacing: 0) {
                        ForEach(categories) { category in
                            categoryRow(category)
                            if category.id != categories.last?.id { Divider() }
                        }
                    }
                }
                summaryCard
                if let posted {
                    banner(text: "Opening balances posted (\(posted)). Your books now reflect your starting position.",
                           system: "checkmark.seal.fill", tone: MercantisTheme.success)
                }
                if let error {
                    banner(text: error, system: "exclamationmark.triangle.fill", tone: MercantisTheme.danger)
                }
                actions
            }
            .padding(24)
            .frame(maxWidth: 680, alignment: .leading)
        }
        .navigationTitle("Opening Balances")
        .onAppear(perform: load)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Enter your opening balances").font(.title2).bold()
            Text("Type in where your business stood when you started using Mercantis. We'll record it correctly for you — no accounting needed. The difference becomes your starting capital automatically.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func categoryRow(_ category: Category) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(category.label).font(.system(size: 14, weight: .medium))
                Text(category.help).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            TextField("0.00", text: amountBinding(category.id))
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(width: 130)
        }
        .padding(.vertical, 8)
    }

    private var summaryCard: some View {
        let capital = startingCapital
        return MercantisInspectorCard("Starting capital", systemImage: "equal.circle") {
            HStack {
                Text(capital >= 0 ? "Your business's starting capital" : "Starting position (negative)")
                    .font(.callout)
                Spacer()
                Text(money(abs(capital)))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(capital >= 0 ? MercantisTheme.success : MercantisTheme.danger)
            }
            Text("Recorded automatically as Opening Balance Equity so your books balance.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        HStack {
            Spacer()
            Button {
                post()
            } label: {
                Text("Post opening balances").frame(minWidth: 160)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!OpeningBalanceBuilder.hasFigures(lines) || posted != nil)
        }
    }

    // MARK: - Derived

    private var lines: [OpeningBalanceBuilder.Line] {
        categories.compactMap { category in
            guard let amount = parse(amounts[category.id]), abs(amount) > 0.0001 else { return nil }
            return OpeningBalanceBuilder.Line(account: category.account, amount: amount, isDebit: category.isDebit)
        }
    }

    /// Assets minus liabilities = the owner's starting capital (the balancing figure).
    private var startingCapital: Double {
        lines.reduce(0) { $0 + ($1.isDebit ? $1.amount : -$1.amount) }
    }

    // MARK: - Actions

    private func load() {
        guard !loaded else { return }
        loaded = true
        let company = (try? engine.list(docType: "Company"))?.first
        if case .string(let c)? = company?.fields["default_currency"] { currency = c }
        // Opening date = active fiscal year start, else today.
        if let fy = (try? engine.list(docType: "FiscalYear"))?.first(where: { isActive($0) }),
           case .date(let start)? = fy.fields["year_start_date"] {
            openingDate = start
        }
    }

    private func post() {
        error = nil
        guard OpeningBalanceBuilder.hasFigures(lines) else {
            error = "Enter at least one opening figure."
            return
        }
        ensureAccount(equityAccount)
        for line in lines { ensureAccount(line.account) }

        let journal = OpeningBalanceBuilder.journalEntry(
            lines: lines, equityAccount: equityAccount, date: openingDate, currency: currency
        )
        do {
            posted = try HubPostingFlow.saveSubmit(
                journal, docType: "JournalEntry",
                engine: engine, workflowEngine: workflowEngine, posting: posting
            )
        } catch {
            self.error = (error as NSError).localizedDescription
        }
    }

    /// Create a needed account from the Phase 1 chart template if it's missing
    /// (legacy installs onboarded before the full chart shipped). Parent links
    /// are omitted so the create never fails on a missing group.
    private func ensureAccount(_ id: String) {
        guard (try? engine.fetch(docType: "Account", id: id)) == nil else { return }
        guard let acc = HubCOATemplateLibrary.accounts(taxStyle: .vat).first(where: { $0.id == id }) else { return }
        let doc = Document(
            id: "", docType: "Account", company: "", status: "",
            createdAt: Date(), updatedAt: Date(), syncVersion: 0, syncState: .local,
            fields: [
                "account_name": .string(acc.name),
                "account_number": .string(acc.code),
                "root_type": .string(acc.rootType),
                "account_type": .string(acc.accountType),
                "is_group": .bool(false),
                "normal_balance": .string(acc.normalBalance),
                "disabled": .bool(false),
            ],
            children: [:]
        )
        _ = try? engine.save(doc, userSuppliedName: id)
    }

    // MARK: - Helpers

    private func amountBinding(_ id: String) -> Binding<String> {
        Binding(get: { amounts[id] ?? "" }, set: { amounts[id] = $0; posted = nil })
    }

    private func banner(text: String, system: String, tone: Color) -> some View {
        Label(text, systemImage: system)
            .font(.callout).foregroundStyle(tone)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tone.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private func isActive(_ doc: Document) -> Bool {
        if case .bool(let b)? = doc.fields["is_active"] { return b }
        return false
    }

    private func parse(_ raw: String?) -> Double? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        return Double(raw.replacingOccurrences(of: ",", with: ""))
    }

    private func money(_ value: Double) -> String {
        let symbol = currency.flatMap(currencySymbol) ?? ""
        return "\(symbol)\(String(format: "%.2f", value))"
    }

    private func currencySymbol(_ code: String) -> String? {
        switch code { case "EUR": return "€"; case "USD", "CAD": return "$"; case "GBP": return "£"; default: return nil }
    }
}
