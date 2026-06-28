import SwiftUI
import MercantisCore
import MercantisCoreUI

/// Phase 3 — guided year-end close. At the end of a financial year the owner
/// clicks one button; the app totals the year's income and expenses, shows the
/// profit (or loss), and — on confirm — posts the closing entry that carries
/// that result into Retained Earnings and marks the year closed. No journals to
/// write, no accounts to pick.
struct HubYearEndCloseView: View {

    let engine: DocumentEngine
    let workflowEngine: WorkflowEngine
    @Environment(\.postingCoordinator) private var posting

    private let retainedEarningsAccount = "RetainedEarnings"

    @State private var fiscalYear: Document?
    @State private var plBalances: [YearEndCloseBuilder.AccountBalance] = []
    @State private var accountNames: [String: String] = [:]
    @State private var incomeTotal = 0.0
    @State private var expenseTotal = 0.0
    @State private var currency: String?
    @State private var posted = false
    @State private var message: String?
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let fiscalYear {
                    if isClosed(fiscalYear) {
                        closedCard(fiscalYear)
                    } else {
                        yearCard(fiscalYear)
                        resultCard
                        breakdownCard
                        actions
                    }
                } else {
                    MercantisInspectorCard("No active year", systemImage: "calendar.badge.exclamationmark") {
                        Text("Set up and activate a fiscal year first (Setup ▸ Fiscal Year).")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                if let message { banner(message, "checkmark.seal.fill", MercantisTheme.success) }
                if let error { banner(error, "exclamationmark.triangle.fill", MercantisTheme.danger) }
            }
            .padding(24)
            .frame(maxWidth: 680, alignment: .leading)
        }
        .navigationTitle("Year-End Close")
        .onAppear(perform: load)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Close off your year").font(.title2).bold()
            Text("When a financial year is done, we tally up your profit and carry it forward, so the new year starts fresh. We record the bookkeeping for you.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func yearCard(_ fy: Document) -> some View {
        MercantisInspectorCard("Year to close", systemImage: "calendar") {
            HStack {
                Text(stringField(fy.fields["year_name"]) ?? fy.id).font(.system(size: 15, weight: .semibold))
                Spacer()
                if let end = dateField(fy.fields["year_end_date"]) {
                    Text("ends \(end.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var resultCard: some View {
        let net = YearEndCloseBuilder.netIncome(plBalances)
        let profit = net >= 0
        return MercantisInspectorCard(profit ? "Profit for the year" : "Loss for the year",
                                      systemImage: profit ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis") {
            Text(money(abs(net)))
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(profit ? MercantisTheme.success : MercantisTheme.danger)
            Text(profit
                 ? "This profit will be added to Retained Earnings (your accumulated equity)."
                 : "This loss will be taken from Retained Earnings.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var breakdownCard: some View {
        MercantisInspectorCard("What's included", systemImage: "list.bullet.rectangle") {
            line("Total income", incomeTotal)
            line("Total expenses", expenseTotal)
            Text("\(plBalances.count) profit-and-loss account\(plBalances.count == 1 ? "" : "s") will be reset to zero for the new year.")
                .font(.caption2).foregroundStyle(.secondary).padding(.top, 4)
        }
    }

    private var actions: some View {
        HStack {
            Spacer()
            Button {
                close()
            } label: {
                Text("Close the year").frame(minWidth: 160)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!YearEndCloseBuilder.hasActivity(plBalances) || posted)
        }
    }

    private func closedCard(_ fy: Document) -> some View {
        MercantisInspectorCard("Year closed", systemImage: "lock.fill") {
            Text("\(stringField(fy.fields["year_name"]) ?? fy.id) has been closed off.")
                .font(.callout)
            if let date = dateField(fy.fields["closed_date"]) {
                Text("Closed on \(date.formatted(date: .abbreviated, time: .omitted)).")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Data

    private func load() {
        guard !loaded else { return }
        loaded = true
        let company = (try? engine.list(docType: "Company"))?.first
        currency = stringField(company?.fields["default_currency"])
        fiscalYear = (try? engine.list(docType: "FiscalYear"))?.first(where: { isActive($0) })
        recomputeBalances()
    }

    private func recomputeBalances() {
        guard let fy = fiscalYear else { plBalances = []; return }
        let start = dateField(fy.fields["year_start_date"])
        let end = dateField(fy.fields["year_end_date"])

        // Map accounts to their root type and name; keep only Income / Expense.
        var rootType: [String: String] = [:]
        for account in (try? engine.list(docType: "Account")) ?? [] {
            rootType[account.id] = stringField(account.fields["root_type"])
            accountNames[account.id] = stringField(account.fields["account_name"]) ?? account.id
        }

        var totals: [String: (debit: Double, credit: Double)] = [:]
        for entry in (try? engine.list(docType: "GLEntry")) ?? [] {
            guard let account = stringField(entry.fields["account"]),
                  let root = rootType[account], root == "Income" || root == "Expense" else { continue }
            if let date = dateField(entry.fields["posting_date"]) {
                if let start, date < start { continue }
                if let end, date > end { continue }
            }
            var t = totals[account] ?? (0, 0)
            t.debit  += doubleField(entry.fields["base_debit"])  ?? doubleField(entry.fields["debit"])  ?? 0
            t.credit += doubleField(entry.fields["base_credit"]) ?? doubleField(entry.fields["credit"]) ?? 0
            totals[account] = t
        }

        var income = 0.0, expense = 0.0
        for (account, t) in totals {
            switch rootType[account] {
            case "Income":  income  += t.credit - t.debit
            case "Expense": expense += t.debit - t.credit
            default: break
            }
        }
        incomeTotal = income
        expenseTotal = expense
        plBalances = totals.map { account, t in
            YearEndCloseBuilder.AccountBalance(account: account, debit: t.debit, credit: t.credit)
        }
        .sorted { (accountNames[$0.account] ?? $0.account) < (accountNames[$1.account] ?? $1.account) }
    }

    private func close() {
        error = nil; message = nil
        guard let fy = fiscalYear else { return }
        let endDate = dateField(fy.fields["year_end_date"]) ?? Date()
        let yearName = stringField(fy.fields["year_name"]) ?? fy.id

        ensureAccount(retainedEarningsAccount)
        guard let entry = YearEndCloseBuilder.closingEntry(
            plBalances: plBalances, retainedEarningsAccount: retainedEarningsAccount,
            date: endDate, yearName: yearName, currency: currency
        ) else {
            error = "There's no profit-and-loss activity to close for this year."
            return
        }

        do {
            let jeId = try HubPostingFlow.saveSubmit(
                entry, docType: "JournalEntry",
                engine: engine, workflowEngine: workflowEngine, posting: posting
            )
            // Mark the year closed after the closing entry has posted, so the
            // period guard never blocks our own entry. Activate the next year if
            // one already exists.
            if var year = try? engine.fetch(docType: "FiscalYear", id: fy.id) {
                year.fields["is_closed"] = .bool(true)
                year.fields["is_active"] = .bool(false)
                year.fields["closed_date"] = .date(Date())
                year.fields["closing_entry"] = .string(jeId)
                year.fields["retained_earnings_account"] = .string(retainedEarningsAccount)
                _ = try? engine.save(year)
                fiscalYear = year
            }
            posted = true
            message = "Year closed. The closing entry (\(jeId)) carried the result into Retained Earnings."
        } catch {
            self.error = (error as NSError).localizedDescription
        }
    }

    /// Create the Retained Earnings account from the chart template if missing
    /// (legacy installs). Parent link omitted so the create never fails.
    private func ensureAccount(_ id: String) {
        guard (try? engine.fetch(docType: "Account", id: id)) == nil else { return }
        guard let acc = HubCOATemplateLibrary.accounts(taxStyle: .vat).first(where: { $0.id == id }) else { return }
        let doc = Document(id: id, docType: "Account", company: "", status: "",
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
        _ = try? engine.save(doc)
    }

    // MARK: - Small views / helpers

    private func line(_ label: String, _ value: Double) -> some View {
        HStack {
            Text(label).font(.callout)
            Spacer()
            Text(money(value)).font(.system(size: 14, weight: .medium))
        }
        .padding(.vertical, 2)
    }

    private func banner(_ text: String, _ system: String, _ tone: Color) -> some View {
        Label(text, systemImage: system)
            .font(.callout).foregroundStyle(tone)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(tone.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private func money(_ value: Double) -> String {
        let symbol = currency.flatMap(currencySymbol) ?? ""
        return "\(symbol)\(String(format: "%.2f", value))"
    }
    private func currencySymbol(_ code: String) -> String? {
        switch code { case "EUR": return "€"; case "USD", "CAD": return "$"; case "GBP": return "£"; default: return nil }
    }

    private func isActive(_ doc: Document) -> Bool {
        if case .bool(let b)? = doc.fields["is_active"] { return b }
        return false
    }
    private func isClosed(_ doc: Document) -> Bool {
        if case .bool(let b)? = doc.fields["is_closed"] { return b }
        return false
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
