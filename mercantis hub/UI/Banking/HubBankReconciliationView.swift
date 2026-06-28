import SwiftUI
import MercantisCore
import MercantisCoreUI

/// Phase 2 — minimal bank reconciliation for a micro business. Pick a bank
/// account, paste/import the bank's CSV, then for each line either match it to a
/// payment already recorded, categorise it (which posts a balanced Journal Entry
/// so the owner never touches debits/credits), or ignore it. A running summary
/// shows what's still to clear.
struct HubBankReconciliationView: View {

    let engine: DocumentEngine
    let workflowEngine: WorkflowEngine
    @Environment(\.postingCoordinator) private var posting

    /// Common categories a bank line is coded to.
    private struct CategoryOption: Identifiable {
        let label: String
        let account: String
        var id: String { account }
    }
    private let categories: [CategoryOption] = [
        .init(label: "Sales", account: "Sales"),
        .init(label: "Other Income", account: "OtherIncome"),
        .init(label: "Bank Charges", account: "BankCharges"),
        .init(label: "Merchant / Processor Fees", account: "MerchantFees"),
        .init(label: "Rent", account: "Rent"),
        .init(label: "Utilities", account: "Utilities"),
        .init(label: "Office Expenses", account: "OfficeExpenses"),
        .init(label: "Professional Fees", account: "ProfessionalFees"),
        .init(label: "Owner Drawings", account: "OwnerDrawings"),
        .init(label: "Owner Capital", account: "OwnerCapital"),
    ]

    @State private var bankAccounts: [Document] = []
    @State private var selectedBankAccountId = ""
    @State private var lines: [Document] = []
    @State private var payments: [Document] = []
    @State private var csvText = ""
    @State private var message: String?
    @State private var error: String?
    @State private var companyCurrency: String?
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if bankAccounts.isEmpty {
                    emptyBankAccounts
                } else {
                    bankAccountPicker
                    importCard
                    summaryCard
                    linesList
                }
                if let message { banner(message, "checkmark.circle.fill", MercantisTheme.success) }
                if let error { banner(error, "exclamationmark.triangle.fill", MercantisTheme.danger) }
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .navigationTitle("Bank Reconciliation")
        .onAppear(perform: load)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Reconcile your bank").font(.title2).bold()
            Text("Import your bank's CSV, then tick off each transaction — match it to a payment you've recorded, or categorise it. We post the accounting for you.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var emptyBankAccounts: some View {
        MercantisInspectorCard("No bank accounts yet", systemImage: "building.columns") {
            Text("Add your bank and cash accounts so you can reconcile them.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Set up bank & cash accounts") { seedBankAccountsFromChart() }
                .buttonStyle(.borderedProminent)
        }
    }

    private var bankAccountPicker: some View {
        MercantisInspectorCard("Bank account", systemImage: "building.columns") {
            Picker("", selection: $selectedBankAccountId) {
                ForEach(bankAccounts, id: \.id) { acc in
                    Text(name(acc)).tag(acc.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 320)
            .onChange(of: selectedBankAccountId) { _, _ in reloadLines() }
        }
    }

    private var importCard: some View {
        MercantisInspectorCard("Import statement (CSV)", systemImage: "square.and.arrow.down") {
            Text("Paste the CSV your bank exports (with a header row: Date, Description, Amount or Money In / Money Out).")
                .font(.caption2).foregroundStyle(.secondary)
            TextEditor(text: $csvText)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 90)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(MercantisTheme.border, lineWidth: 1))
            HStack {
                Spacer()
                Button("Import lines") { importCSV() }
                    .buttonStyle(.bordered)
                    .disabled(csvText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedBankAccountId.isEmpty)
            }
        }
    }

    private var summaryCard: some View {
        let unmatched = lines.filter { status($0) == "Unmatched" }.count
        let cleared = lines.count - unmatched
        return MercantisInspectorCard("Progress", systemImage: "checklist") {
            HStack(spacing: 20) {
                stat("\(lines.count)", "lines")
                stat("\(cleared)", "cleared")
                stat("\(unmatched)", "to do")
                Spacer()
                Text(money(clearedTotal)).font(.system(size: 15, weight: .semibold))
            }
        }
    }

    @ViewBuilder
    private var linesList: some View {
        if lines.isEmpty {
            Text("No statement lines yet — import a CSV above.")
                .font(.callout).foregroundStyle(.secondary)
        } else {
            VStack(spacing: 0) {
                ForEach(lines, id: \.id) { line in
                    lineRow(line)
                    Divider()
                }
            }
            .background(MercantisTheme.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(MercantisTheme.border, lineWidth: 1))
        }
    }

    private func lineRow(_ line: Document) -> some View {
        let amount = doubleField(line.fields["amount"]) ?? 0
        let st = status(line)
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(stringField(line.fields["description"]) ?? "—").font(.system(size: 13)).lineLimit(1)
                HStack(spacing: 6) {
                    if let d = dateField(line.fields["line_date"]) {
                        Text(d.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(.secondary)
                    }
                    statusChip(st)
                }
            }
            Spacer()
            Text(money(amount))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(amount >= 0 ? MercantisTheme.success : MercantisTheme.textPrimary)
                .frame(width: 110, alignment: .trailing)
            if st == "Unmatched" {
                actionMenu(line, amount: amount)
            } else {
                Button { reset(line) } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(.borderless).help("Undo")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }

    private func actionMenu(_ line: Document, amount: Double) -> some View {
        Menu {
            let matches = BankMatchingService.suggestions(forAmount: amount, date: dateField(line.fields["line_date"]), payments: payments)
            if let top = matches.first {
                Button("Match to payment: \(top.label)") { matchToPayment(line, paymentId: top.id) }
                Divider()
            }
            Menu("Categorise as") {
                ForEach(categories) { cat in
                    Button(cat.label) { categorise(line, amount: amount, account: cat.account, label: cat.label) }
                }
            }
            Divider()
            Button("Ignore") { setStatus(line, "Ignored") }
        } label: {
            Text("Resolve").font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Derived

    private var clearedTotal: Double {
        lines.filter { status($0) != "Unmatched" && status($0) != "Ignored" }
            .reduce(0) { $0 + (doubleField($1.fields["amount"]) ?? 0) }
    }

    // MARK: - Data

    private func load() {
        guard !loaded else { return }
        loaded = true
        bankAccounts = (try? engine.list(docType: "BankAccount")) ?? []
        payments = ((try? engine.list(docType: "PaymentEntry")) ?? []).filter { $0.docStatus == 1 }
        companyCurrency = stringField((try? engine.list(docType: "Company"))?.first?.fields["default_currency"])
        if selectedBankAccountId.isEmpty { selectedBankAccountId = bankAccounts.first?.id ?? "" }
        reloadLines()
    }

    private func reloadLines() {
        guard !selectedBankAccountId.isEmpty else { lines = []; return }
        let all = (try? engine.list(docType: "BankStatementLine")) ?? []
        lines = all
            .filter { stringField($0.fields["bank_account"]) == selectedBankAccountId }
            .sorted { (dateField($0.fields["line_date"]) ?? .distantPast) < (dateField($1.fields["line_date"]) ?? .distantPast) }
    }

    private func importCSV() {
        error = nil; message = nil
        guard let result = BankStatementCSVImporter.parseAutodetecting(csvText) else {
            error = "Couldn't read the CSV. Make sure it has a header row with Date, Description, and an Amount (or Money In / Money Out)."
            return
        }
        var created = 0
        for parsed in result.lines {
            var fields: [String: FieldValue] = [
                "bank_account": .string(selectedBankAccountId),
                "description": .string(parsed.description),
                "reference": .string(parsed.reference),
                "amount": .double(parsed.amount),
                "status": .string("Unmatched"),
            ]
            if let d = parsed.date { fields["line_date"] = .date(d) }
            if let b = parsed.balance { fields["running_balance"] = .double(b) }
            let doc = Document(id: "", docType: "BankStatementLine", company: "", status: "",
                               createdAt: Date(), updatedAt: Date(), syncVersion: 0, syncState: .local,
                               fields: fields, children: [:])
            if (try? engine.save(doc)) != nil { created += 1 }
        }
        csvText = ""
        message = "Imported \(created) statement line\(created == 1 ? "" : "s")."
        reloadLines()
    }

    private func matchToPayment(_ line: Document, paymentId: String) {
        var line = line
        line.fields["status"] = .string("Matched")
        line.fields["matched_doctype"] = .string("PaymentEntry")
        line.fields["matched_name"] = .string(paymentId)
        _ = try? engine.save(line)
        reloadLines()
    }

    private func categorise(_ line: Document, amount: Double, account: String, label: String) {
        error = nil
        guard let bankGL = bankGLAccount else {
            error = "This bank account isn't linked to a ledger account."
            return
        }
        ensureAccount(account)
        let date = dateField(line.fields["line_date"]) ?? Date()
        let memo = stringField(line.fields["description"]) ?? label
        let journal = BankMatchingService.categoriseJournalEntry(
            amount: amount, date: date, bankGLAccount: bankGL,
            categoryAccount: account, memo: memo, currency: currencyCode
        )
        do {
            let jeId = try HubPostingFlow.saveSubmit(
                journal, docType: "JournalEntry",
                engine: engine, workflowEngine: workflowEngine, posting: posting
            )
            var updated = line
            updated.fields["status"] = .string("Matched")
            updated.fields["category_account"] = .string(account)
            updated.fields["journal_entry"] = .string(jeId)
            _ = try? engine.save(updated)
            message = "Categorised as \(label)."
            reloadLines()
        } catch {
            self.error = (error as NSError).localizedDescription
        }
    }

    private func setStatus(_ line: Document, _ value: String) {
        var line = line
        line.fields["status"] = .string(value)
        _ = try? engine.save(line)
        reloadLines()
    }

    private func reset(_ line: Document) {
        var line = line
        line.fields["status"] = .string("Unmatched")
        line.fields["matched_doctype"] = .string("")
        line.fields["matched_name"] = .string("")
        line.fields["category_account"] = .string("")
        _ = try? engine.save(line)
        reloadLines()
    }

    private func seedBankAccountsFromChart() {
        for (name, gl, kind) in [("Main Bank Account", "Bank", "Bank"), ("Cash on Hand", "Cash", "Cash")] {
            guard (try? engine.fetch(docType: "Account", id: gl)) != nil else { continue }
            let doc = Document(id: "", docType: "BankAccount", company: "", status: "",
                               createdAt: Date(), updatedAt: Date(), syncVersion: 0, syncState: .local,
                               fields: [
                                "account_name": .string(name),
                                "account_kind": .string(kind),
                                "gl_account": .string(gl),
                                "disabled": .bool(false),
                               ], children: [:])
            _ = try? engine.save(doc, userSuppliedName: "Bank-\(gl)")
        }
        loaded = false
        load()
    }

    private func ensureAccount(_ id: String) {
        guard (try? engine.fetch(docType: "Account", id: id)) == nil else { return }
        guard let acc = HubCOATemplateLibrary.accounts(taxStyle: .vat).first(where: { $0.id == id }) else { return }
        let doc = Document(id: "", docType: "Account", company: "", status: "",
                           createdAt: Date(), updatedAt: Date(), syncVersion: 0, syncState: .local,
                           fields: [
                            "account_name": .string(acc.name),
                            "account_number": .string(acc.code),
                            "root_type": .string(acc.rootType),
                            "account_type": .string(acc.accountType),
                            "is_group": .bool(false),
                            "normal_balance": .string(acc.normalBalance),
                            "disabled": .bool(false),
                           ], children: [:])
        _ = try? engine.save(doc, userSuppliedName: id)
    }

    // MARK: - Lookups

    private var selectedBankAccount: Document? {
        bankAccounts.first { $0.id == selectedBankAccountId }
    }
    private var bankGLAccount: String? {
        stringField(selectedBankAccount?.fields["gl_account"])
    }
    private var currencyCode: String? {
        stringField(selectedBankAccount?.fields["currency"]) ?? companyCurrency
    }

    // MARK: - Small views / formatting

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 16, weight: .semibold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func statusChip(_ st: String) -> some View {
        Text(st)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(chipColor(st).opacity(0.15), in: Capsule())
            .foregroundStyle(chipColor(st))
    }
    private func chipColor(_ st: String) -> Color {
        switch st {
        case "Matched", "Reconciled": return MercantisTheme.success
        case "Ignored":               return MercantisTheme.textMuted
        default:                      return MercantisTheme.warning
        }
    }

    private func banner(_ text: String, _ system: String, _ tone: Color) -> some View {
        Label(text, systemImage: system)
            .font(.callout).foregroundStyle(tone)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(tone.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private func name(_ acc: Document) -> String { stringField(acc.fields["account_name"]) ?? acc.id }
    private func status(_ line: Document) -> String { stringField(line.fields["status"]) ?? "Unmatched" }

    private func money(_ value: Double) -> String {
        let symbol = currencyCode.flatMap(currencySymbol) ?? ""
        return "\(symbol)\(String(format: "%.2f", value))"
    }
    private func currencySymbol(_ code: String) -> String? {
        switch code { case "EUR": return "€"; case "USD", "CAD": return "$"; case "GBP": return "£"; default: return nil }
    }

    private func stringField(_ value: FieldValue?) -> String? {
        guard case .string(let s)? = value else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
    private func doubleField(_ value: FieldValue?) -> Double? {
        switch value { case .double(let d): return d; case .int(let i): return Double(i); default: return nil }
    }
    private func dateField(_ value: FieldValue?) -> Date? {
        switch value { case .date(let d), .dateTime(let d): return d; default: return nil }
    }
}
