import SwiftUI
import MercantisCore
import MercantisCoreUI

/// Phase 5 — Guided Payments. A customer- (Receive) or supplier-focused
/// (Pay) flow that lets the user pick a party, see outstanding
/// invoices/bills, tick what is being paid, and post — without typing
/// document references or posting accounts. It assembles an ordinary
/// Payment Entry via `GuidedPaymentBuilder` and runs it through the same
/// save → submit → workflow path the manual editor uses, so the GL /
/// CustTrans / VendTrans / Settlement derivation is untouched.
struct GuidedPaymentFlowView: View {

    let mode: GuidedPaymentMode
    let engine: DocumentEngine
    let workflowEngine: WorkflowEngine

    /// Phase 1 — posts Payment Entry inside the submit transaction. Injected at
    /// app scope; nil in previews.
    @Environment(\.postingCoordinator) private var posting

    @State private var parties: [Document] = []
    @State private var accounts: [Document] = []
    @State private var businessProfile: Document?

    @State private var selectedParty = ""
    @State private var bankAccount = ""
    @State private var postingDate = Date()
    @State private var rows: [AllocRow] = []

    @State private var errorMessage: String?
    @State private var successMessage: String?

    private let evaluator = ExpressionEvaluator()

    /// One selectable outstanding invoice/bill row with its editable
    /// allocation amount.
    private struct AllocRow: Identifiable {
        let id: String
        let docType: String
        let label: String
        let dateText: String
        let total: Double
        let outstanding: Double
        let currency: String?
        var selected: Bool
        var amountText: String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                partySection
                if !selectedParty.isEmpty {
                    accountSection
                    outstandingSection
                    summarySection
                }
                if let errorMessage {
                    banner(errorMessage, color: .red, icon: "exclamationmark.triangle")
                }
                if let successMessage {
                    banner(successMessage, color: .green, icon: "checkmark.circle")
                }
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear(perform: loadReferenceData)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(mode.title).font(.title2).bold()
            Text(mode == .receive
                 ? "Record money received from a customer against their open invoices."
                 : "Record a payment to a supplier against their open bills.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var partySection: some View {
        MercantisInspectorCard(mode == .receive ? "Customer" : "Supplier",
                               systemImage: mode == .receive ? "person.crop.circle" : "shippingbox") {
            Picker("", selection: $selectedParty) {
                Text(mode == .receive ? "Select a customer…" : "Select a supplier…").tag("")
                ForEach(parties, id: \.id) { party in
                    Text(partyName(party)).tag(party.id)
                }
            }
            .labelsHidden()
            .onChange(of: selectedParty) { _, _ in loadOutstanding() }
        }
    }

    private var accountSection: some View {
        MercantisInspectorCard(mode == .receive ? "Deposit Into" : "Pay From",
                               systemImage: "banknote") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("", selection: $bankAccount) {
                    Text("Select a cash / bank account…").tag("")
                    ForEach(bankAccounts, id: \.id) { account in
                        Text(accountName(account)).tag(account.id)
                    }
                }
                .labelsHidden()
                DatePicker("Posting Date", selection: $postingDate, displayedComponents: .date)
            }
        }
    }

    private var outstandingSection: some View {
        MercantisInspectorCard("Outstanding", systemImage: "doc.text") {
            if rows.isEmpty {
                Text(mode == .receive
                     ? "This customer has no open invoices."
                     : "This supplier has no open bills.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach($rows) { $row in
                        HStack(spacing: 12) {
                            Toggle(isOn: $row.selected) { EmptyView() }
                                .labelsHidden()
                                .onChange(of: row.selected) { _, _ in errorMessage = nil }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.label).font(.body)
                                Text("\(row.dateText) · Outstanding \(money(row.outstanding))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            TextField("Amount", text: $row.amountText)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 110)
                                .textFieldStyle(.roundedBorder)
                                .disabled(!row.selected)
                        }
                        Divider()
                    }
                }
            }
        }
    }

    private var summarySection: some View {
        MercantisInspectorCard("Summary", systemImage: "sum") {
            VStack(alignment: .leading, spacing: 12) {
                MercantisInspectorRow("Total Payment", value: money(totalAllocated), isNumeric: true)
                Button {
                    post()
                } label: {
                    Text(mode == .receive ? "Receive \(money(totalAllocated))" : "Pay \(money(totalAllocated))")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canPost)
            }
        }
    }

    private func banner(_ text: String, color: Color, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.callout)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Derived state

    private var bankAccounts: [Document] {
        let cashLike = accounts.filter {
            switch stringValue($0.fields["account_type"]) {
            case "Bank", "Cash": return true
            default: return false
            }
        }
        // Fall back to every account if none are tagged Bank / Cash, so the
        // flow is still usable before the chart of accounts is fully typed.
        return cashLike.isEmpty ? accounts : cashLike
    }

    private var selectedAllocations: [GuidedPaymentBuilder.Allocation] {
        rows.compactMap { row in
            guard row.selected else { return nil }
            let amount = Double(row.amountText.trimmingCharacters(in: .whitespaces)) ?? 0
            guard amount > 0.0001 else { return nil }
            return GuidedPaymentBuilder.Allocation(
                invoiceId: row.id,
                invoiceDocType: row.docType,
                total: row.total,
                outstanding: row.outstanding,
                allocated: amount
            )
        }
    }

    private var totalAllocated: Double {
        GuidedPaymentBuilder.totalAllocated(selectedAllocations)
    }

    private var canPost: Bool {
        !selectedParty.isEmpty && !bankAccount.isEmpty && totalAllocated > 0.0001
    }

    // MARK: - Data loading

    private func loadReferenceData() {
        parties = (try? engine.list(docType: mode.partyDocType)) ?? []
        accounts = (try? engine.list(docType: "Account")) ?? []
        businessProfile = (try? engine.list(docType: "Company"))?.first
        if bankAccount.isEmpty,
           let preferred = stringValue(businessProfile?.fields["default_cash_bank_account"]) {
            bankAccount = preferred
        }
    }

    private func loadOutstanding() {
        errorMessage = nil
        successMessage = nil
        guard !selectedParty.isEmpty else { rows = []; return }
        let invoices = (try? engine.list(
            docType: mode.invoiceDocType,
            filters: [mode.invoicePartyField: .string(selectedParty)],
            applyRowAccess: false
        )) ?? []
        rows = GuidedPaymentBuilder.outstanding(from: invoices, mode: mode).map { item in
            AllocRow(
                id: item.id,
                docType: item.docType,
                label: item.id,
                dateText: dateText(item.date),
                total: item.grandTotal,
                outstanding: item.outstanding,
                currency: item.currency,
                selected: false,
                amountText: trimmedAmount(item.outstanding)
            )
        }
    }

    // MARK: - Posting

    private func post() {
        errorMessage = nil
        successMessage = nil

        let allocations = selectedAllocations
        guard !allocations.isEmpty else {
            errorMessage = "Select at least one \(mode == .receive ? "invoice" : "bill") and enter an amount."
            return
        }
        guard let profile = businessProfile else {
            errorMessage = "Set up your Business Profile in Setup before recording payments."
            return
        }
        let partyAccountKey = mode == .receive ? "default_receivable_account" : "default_payable_account"
        guard let partyAccount = stringValue(profile.fields[partyAccountKey]) else {
            errorMessage = "Set a default \(mode == .receive ? "receivable" : "payable") account in Setup ▸ Business Profile."
            return
        }
        guard !bankAccount.isEmpty else {
            errorMessage = "Choose a cash / bank account."
            return
        }

        let currency = rows.first(where: { $0.selected })?.currency
            ?? stringValue(profile.fields["default_currency"])

        let payment = GuidedPaymentBuilder.buildPaymentEntry(
            mode: mode,
            party: selectedParty,
            postingDate: postingDate,
            currency: currency,
            bankAccount: bankAccount,
            partyAccount: partyAccount,
            allocations: allocations
        )

        do {
            let postedId = try saveSubmit(payment)
            let total = money(totalAllocated)
            successMessage = mode == .receive
                ? "Received \(total). Payment \(postedId) posted."
                : "Paid \(total). Payment \(postedId) posted."
            // Reset the form but keep the party for quick follow-up.
            loadOutstanding()
        } catch {
            errorMessage = humanReadable(error)
        }
    }

    /// Save the draft, run Core's submit (which fires the ledger
    /// derivation), then advance the workflow status to Submitted — the
    /// same three steps `HubDocumentEditor.submit()` performs.
    private func saveSubmit(_ payment: Document) throws -> String {
        var doc = try engine.save(payment)
        if let refreshed = try engine.fetch(docType: "PaymentEntry", id: doc.id) {
            doc = refreshed
        }
        // Phase 1: post the payment atomically inside the submit transaction.
        if let posting, let closure = posting.submitClosure(for: doc) {
            try engine.submit(&doc, inTransaction: closure)
        } else {
            try engine.submit(&doc)
        }
        if let refreshed = try engine.fetch(docType: "PaymentEntry", id: doc.id) {
            doc = refreshed
        }
        if let workflow = HubWorkflows.workflow(forDocTypeId: "PaymentEntry"),
           let transition = (try? workflowEngine.availableTransitions(
                workflow: workflow,
                currentState: "Draft",
                userRoles: ["System Manager"],
                document: doc,
                expressionEvaluator: evaluator
           ))?.first(where: { $0.action == "Submit" }) {
            _ = try workflowEngine.transition(
                document: &doc,
                workflow: workflow,
                action: transition.action,
                userRoles: ["System Manager"],
                expressionEvaluator: evaluator,
                userId: HubIdentity.userId()
            )
            _ = try engine.save(doc)
        }
        return doc.id
    }

    // MARK: - Formatting helpers

    private func partyName(_ doc: Document) -> String {
        stringValue(doc.fields[mode.partyNameField]) ?? doc.id
    }

    private func accountName(_ doc: Document) -> String {
        stringValue(doc.fields["account_name"]) ?? doc.id
    }

    private func money(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func trimmedAmount(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func dateText(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func stringValue(_ value: FieldValue?) -> String? {
        guard case .string(let s) = value else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func humanReadable(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "\(error)"
    }
}
