import SwiftUI
import MercantisCore
import MercantisCoreUI

/// Phase 6 — POS v1. The real, wired point-of-sale till (the old
/// `HubPOSView` remains a preview-only design shell). It uses real `Item`
/// records, prices from the profile's price list, calculates VAT through
/// the shared `HubTaxEngine`, captures a tender, and posts a `POSInvoice`
/// that decrements stock and books the cash sale + output VAT via
/// `LedgerDerivationService`.
struct HubPOSCheckoutView: View {

    let engine: DocumentEngine
    let workflowEngine: WorkflowEngine

    @State private var items: [Document] = []
    @State private var taxRates: [String: HubTaxEngine.TaxRateInfo] = [:]
    @State private var profile: Document?
    @State private var priceList: Document?
    @State private var businessProfile: Document?
    @State private var session: Document?

    @State private var query = ""
    @State private var cart: [CartLine] = []
    @State private var tenderType = "Cash"
    @State private var tenderText = ""

    @State private var errorMessage: String?
    @State private var receipt: String?

    private let evaluator = ExpressionEvaluator()

    private struct CartLine: Identifiable {
        let id: String           // item id
        let name: String
        let rate: Double
        let taxCode: String?
        var qty: Double
    }

    var body: some View {
        Group {
            if profile == nil {
                setupPrompt
            } else {
                HStack(spacing: 0) {
                    catalogue
                    Divider()
                    cartPanel.frame(width: 340)
                }
            }
        }
        .navigationTitle("Point of Sale")
        .onAppear(perform: loadData)
        .sheet(isPresented: Binding(get: { receipt != nil }, set: { if !$0 { receipt = nil } })) {
            receiptSheet
        }
    }

    // MARK: - Setup prompt

    private var setupPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "creditcard.and.123").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("No POS Profile yet").font(.title3).bold()
            Text("Create a POS Profile under POS ▸ Setup (choose a warehouse, price list, and cash account) to start selling.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Catalogue

    private var catalogue: some View {
        VStack(spacing: 0) {
            TextField("Search name, code, or scan barcode", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(12)
            Divider()
            ScrollView {
                if filteredItems.isEmpty {
                    Text("No matching items.")
                        .foregroundStyle(.secondary).padding(.top, 40)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130, maximum: 180), spacing: 12)], spacing: 12) {
                        ForEach(filteredItems, id: \.id) { item in
                            productTile(item)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(minWidth: 360, maxWidth: .infinity)
    }

    private func productTile(_ item: Document) -> some View {
        Button {
            add(item)
        } label: {
            MercantisCard(padding: .compact) {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "cube.box")
                        .font(.system(size: 20))
                        .frame(maxWidth: .infinity).frame(height: 36)
                    Text(itemName(item)).font(.system(size: 12, weight: .medium)).lineLimit(2)
                    Text(money(price(of: item))).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Cart + payment

    private var cartPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Current Sale").font(.headline)
                Spacer()
                if !cart.isEmpty {
                    Button("Clear") { cart.removeAll(); errorMessage = nil }
                        .buttonStyle(.link)
                }
            }
            .padding(12)
            Divider()

            if cart.isEmpty {
                Text("Tap a product to start a sale.")
                    .foregroundStyle(.secondary).frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach($cart) { $line in
                            cartRow($line)
                            Divider()
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }

            paymentPanel
        }
    }

    private func cartRow(_ line: Binding<CartLine>) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.wrappedValue.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text("\(money(line.wrappedValue.rate)) each").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Stepper(value: line.qty, in: 0...9999, step: 1) {
                Text(qtyText(line.wrappedValue.qty)).font(.system(size: 12, weight: .semibold)).monospacedDigit()
            }
            .labelsHidden()
            .onChange(of: line.wrappedValue.qty) { _, newValue in
                if newValue <= 0 { cart.removeAll { $0.id == line.wrappedValue.id } }
            }
            Text(money(line.wrappedValue.qty * line.wrappedValue.rate))
                .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 8)
    }

    private var paymentPanel: some View {
        VStack(spacing: 10) {
            Divider()
            summaryLine("Subtotal", computation.netTotal)
            summaryLine("VAT", computation.totalTax)
            HStack {
                Text("Total").font(.headline)
                Spacer()
                Text(money(computation.grandTotal)).font(.system(size: 24, weight: .bold)).monospacedDigit()
            }
            Picker("Tender", selection: $tenderType) {
                Text("Cash").tag("Cash")
                Text("Card").tag("Card")
                Text("Other").tag("Other")
            }
            .pickerStyle(.segmented)
            HStack {
                Text("Tendered")
                TextField(money(computation.grandTotal), text: $tenderText)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            if changeDue > 0 {
                summaryLine("Change", changeDue)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(action: completeSale) {
                Text("Complete Sale · \(money(computation.grandTotal))").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(cart.isEmpty)
        }
        .padding(14)
    }

    private func summaryLine(_ label: String, _ value: Double) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
            Text(money(value)).font(.system(size: 12, weight: .medium)).monospacedDigit()
        }
    }

    private var receiptSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Receipt").font(.title3).bold()
            ScrollView {
                Text(receipt ?? "")
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Print / email receipt — coming soon.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Done") { receipt = nil }.buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 380, height: 460)
    }

    // MARK: - Derived

    private var filteredItems: [Document] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return items.filter { item in
            guard boolValue(item.fields["is_sales_item"], default: true) else { return false }
            guard !q.isEmpty else { return true }
            for key in ["item_name", "item_code", "barcode"] {
                if let v = stringValue(item.fields[key])?.lowercased(), v.contains(q) { return true }
            }
            return false
        }
    }

    private var computation: HubTaxEngine.TaxComputation {
        let profileTaxCode = stringValue(profile?.fields["tax_code"])
        let lines = cart.map { line in
            HubTaxEngine.TaxLine(netAmount: line.qty * line.rate,
                                 taxCodeId: line.taxCode ?? profileTaxCode)
        }
        return HubTaxEngine.compute(lines: lines, rates: taxRates)
    }

    private var tenderedAmount: Double {
        let trimmed = tenderText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return computation.grandTotal }
        return Double(trimmed) ?? computation.grandTotal
    }

    private var changeDue: Double {
        max(0, ((tenderedAmount - computation.grandTotal) * 100).rounded() / 100)
    }

    // MARK: - Cart mutation

    private func add(_ item: Document) {
        errorMessage = nil
        if let idx = cart.firstIndex(where: { $0.id == item.id }) {
            cart[idx].qty += 1
        } else {
            cart.append(CartLine(
                id: item.id,
                name: itemName(item),
                rate: price(of: item),
                taxCode: stringValue(item.fields["tax_code"]),
                qty: 1
            ))
        }
    }

    // MARK: - Loading

    private func loadData() {
        items = (try? engine.list(docType: "Item")) ?? []
        businessProfile = (try? engine.list(docType: "Company"))?.first
        profile = (try? engine.list(docType: "POSProfile"))?
            .first { boolValue($0.fields["enabled"], default: true) }
        if let priceListId = stringValue(profile?.fields["price_list"]) {
            priceList = try? engine.fetch(docType: "PriceList", id: priceListId)
        }
        loadTaxRates()
        ensureSession()
    }

    private func loadTaxRates() {
        let defaultVat = stringValue(businessProfile?.fields["default_vat_account"])
        var map: [String: HubTaxEngine.TaxRateInfo] = [:]
        for code in (try? engine.list(docType: "TaxCode")) ?? [] {
            guard boolValue(code.fields["enabled"], default: true) else { continue }
            map[code.id] = HubTaxEngine.TaxRateInfo(
                codeId: code.id,
                description: stringValue(code.fields["tax_code_name"]) ?? code.id,
                rate: doubleValue(code.fields["rate"]) ?? 0,
                account: stringValue(code.fields["tax_account"]) ?? defaultVat,
                taxType: stringValue(code.fields["tax_type"]) ?? "VAT"
            )
        }
        taxRates = map
    }

    /// Reuse an open session for this profile, or open a new one.
    private func ensureSession() {
        guard let profile else { return }
        let existing = (try? engine.list(
            docType: "POSSession",
            filters: ["pos_profile": .string(profile.id), "status": .string("Open")],
            applyRowAccess: false
        ))?.first
        if let existing {
            session = existing
            return
        }
        let new = Document(
            id: "", docType: "POSSession", company: "", status: "",
            createdAt: Date(), updatedAt: Date(), syncVersion: 0, syncState: .local,
            fields: [
                "pos_profile": .string(profile.id),
                "status": .string("Open"),
                "opening_date": .dateTime(Date()),
                "total_sales": .double(0),
                "total_qty": .double(0),
            ],
            children: [:]
        )
        session = try? engine.save(new)
    }

    // MARK: - Pricing

    private func price(of item: Document) -> Double {
        POSCheckoutBuilder.price(
            forItem: item.id,
            in: priceList,
            standardRate: doubleValue(item.fields["standard_rate"]) ?? 0
        )
    }

    // MARK: - Checkout

    private func completeSale() {
        errorMessage = nil
        guard !cart.isEmpty else { return }

        let warehouse = stringValue(profile?.fields["warehouse"])
            ?? stringValue(businessProfile?.fields["default_warehouse"])
        guard let warehouse else {
            errorMessage = "Set a warehouse on the POS Profile (or a default warehouse in Business Profile) so stock can be reduced."
            return
        }
        let cashAccount = stringValue(profile?.fields["cash_account"])
            ?? stringValue(businessProfile?.fields["default_cash_bank_account"])
        let incomeAccount = stringValue(profile?.fields["income_account"])
            ?? stringValue(businessProfile?.fields["default_income_account"])
        let currency = stringValue(profile?.fields["currency"])
            ?? stringValue(businessProfile?.fields["default_currency"])

        let lines = cart.map {
            POSCheckoutBuilder.CartLine(itemId: $0.id, qty: $0.qty, rate: $0.rate,
                                        taxCode: $0.taxCode, warehouse: warehouse)
        }
        let tenders = [POSCheckoutBuilder.Tender(type: tenderType, amount: tenderedAmount, reference: nil)]

        let draft = POSCheckoutBuilder.buildPOSInvoice(
            profileId: profile?.id,
            sessionId: session?.id,
            customer: stringValue(profile?.fields["customer"]),
            postingDate: Date(),
            currency: currency,
            warehouse: warehouse,
            cashAccount: cashAccount,
            incomeAccount: incomeAccount,
            defaultTaxCode: stringValue(profile?.fields["tax_code"]),
            lines: lines,
            tenders: tenders
        )

        guard let docType = HubManifest.docType(for: "POSInvoice") else {
            errorMessage = "POS is not configured."
            return
        }
        // Stamp taxes + totals with the shared engine, then record change.
        var sale = HubTaxCalculationPolicy.applied(to: draft, docType: docType, engine: engine)
        let grand = doubleValue(sale.fields["grand_total"]) ?? 0
        guard POSCheckoutBuilder.isFullyPaid(tenders: tenders, grandTotal: grand) else {
            errorMessage = "Tendered amount must cover the sale total."
            return
        }
        sale.fields["change_amount"] = .double(max(0, ((tenderedAmount - grand) * 100).rounded() / 100))

        do {
            let saleId = try saveSubmit(sale)
            updateSession(addingSales: grand, qty: cart.reduce(0) { $0 + $1.qty })
            receipt = makeReceipt(id: saleId, grand: grand, currency: currency)
            cart.removeAll()
            tenderText = ""
        } catch {
            errorMessage = humanReadable(error)
        }
    }

    private func saveSubmit(_ sale: Document) throws -> String {
        var doc = try engine.save(sale)
        if let refreshed = try engine.fetch(docType: "POSInvoice", id: doc.id) { doc = refreshed }
        try engine.submit(&doc)
        if let refreshed = try engine.fetch(docType: "POSInvoice", id: doc.id) { doc = refreshed }
        if let workflow = HubWorkflows.workflow(forDocTypeId: "POSInvoice"),
           let transition = (try? workflowEngine.availableTransitions(
                workflow: workflow, currentState: "Draft", userRoles: ["System Manager"],
                document: doc, expressionEvaluator: evaluator))?.first(where: { $0.action == "Submit" }) {
            _ = try workflowEngine.transition(
                document: &doc, workflow: workflow, action: transition.action,
                userRoles: ["System Manager"], expressionEvaluator: evaluator,
                userId: HubIdentity.userId())
            _ = try engine.save(doc)
        }
        return doc.id
    }

    private func updateSession(addingSales sales: Double, qty: Double) {
        guard let current = session,
              var fresh = try? engine.fetch(docType: "POSSession", id: current.id) else { return }
        let newSales = (doubleValue(fresh.fields["total_sales"]) ?? 0) + sales
        let newQty = (doubleValue(fresh.fields["total_qty"]) ?? 0) + qty
        fresh.fields["total_sales"] = .double((newSales * 100).rounded() / 100)
        fresh.fields["total_qty"] = .double(newQty)
        session = try? engine.save(fresh)
    }

    // MARK: - Receipt

    private func makeReceipt(id: String, grand: Double, currency: String?) -> String {
        let store = stringValue(businessProfile?.fields["business_name"]) ?? "Mercantis Hub"
        var lines = [store, "Sale \(id)", "", ]
        for line in cart {
            let amt = money(line.qty * line.rate)
            lines.append("\(qtyText(line.qty)) x \(line.name)".padding(toLength: 26, withPad: " ", startingAt: 0) + amt)
        }
        lines.append("")
        lines.append("Subtotal".padding(toLength: 26, withPad: " ", startingAt: 0) + money(computation.netTotal))
        lines.append("VAT".padding(toLength: 26, withPad: " ", startingAt: 0) + money(computation.totalTax))
        lines.append("TOTAL".padding(toLength: 26, withPad: " ", startingAt: 0) + money(grand))
        lines.append("\(tenderType)".padding(toLength: 26, withPad: " ", startingAt: 0) + money(tenderedAmount))
        if changeDue > 0 {
            lines.append("Change".padding(toLength: 26, withPad: " ", startingAt: 0) + money(changeDue))
        }
        if let currency { lines.append("\nCurrency: \(currency)") }
        return lines.joined(separator: "\n")
    }

    // MARK: - Formatting / coercion

    private func itemName(_ item: Document) -> String {
        stringValue(item.fields["item_name"]) ?? stringValue(item.fields["item_code"]) ?? item.id
    }

    private func money(_ value: Double) -> String { String(format: "%.2f", value) }

    private func qtyText(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }

    private func stringValue(_ value: FieldValue?) -> String? {
        guard case .string(let s) = value else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func doubleValue(_ value: FieldValue?) -> Double? {
        switch value {
        case .double(let d): return d
        case .int(let i):    return Double(i)
        default:             return nil
        }
    }

    private func boolValue(_ value: FieldValue?, default fallback: Bool) -> Bool {
        guard case .bool(let b) = value else { return fallback }
        return b
    }

    private func humanReadable(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "\(error)"
    }
}
