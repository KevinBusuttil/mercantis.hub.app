import SwiftUI
import MercantisCore
import MercantisCoreUI

/// Default landing page for Mercantis Hub.
///
/// Shown when no sidebar item is selected. This is the first-run experience,
/// so it is written for a business user evaluating the app — not as an
/// engineering status board. It stays honest (incomplete areas are shown as
/// secondary "coming soon" rows, never as the headline) and it never
/// fabricates metrics: every number comes from a real `DocumentEngine.list`
/// count, and the only data the app ever creates is the clearly-labelled
/// sample business the user explicitly opts into.
///
/// Sections, top to bottom:
/// 1. Welcome / value proposition
/// 2. Load sample business (only when the database is empty)
/// 3. Getting Started checklist (real record counts → Ready / Needs setup)
/// 4. Quick start actions (only DocTypes that actually exist)
/// 5. Business snapshot (real counts, with an empty-state when there's no data)
/// 6. Recent activity
/// 7. What you can do today (plain-language capabilities)
struct HubHomeView: View {
    let engine: DocumentEngine
    let onSelect: (HubMenuItem) -> Void

    @State private var recentRecords: [RecentRecord] = []
    @State private var counts: [String: Int] = [:]
    @State private var openInvoiceCount: Int = 0
    @State private var hasLoaded = false
    @State private var showSampleConfirm = false
    @State private var sampleMessage: String?

    /// DocTypes whose record counts the home screen reads. Kept small and
    /// explicit so a fresh database does only a handful of cheap list calls.
    private let countedDocTypeIDs = [
        "Customer", "Supplier", "Item", "Warehouse",
        "Currency", "Account", "StockEntry", "PaymentEntry", "SalesInvoice"
    ]

    private let sampleNote = "Sample / demo data — safe to delete."

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                welcomeHeader
                if isDatabaseEmpty {
                    sampleBusinessCard
                }
                if let sampleMessage {
                    sampleResultBanner(sampleMessage)
                }
                gettingStartedSection
                quickStartSection
                snapshotSection
                recentSection
                businessAreasSection
            }
            .padding(28)
            .frame(maxWidth: 1000, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: reloadIfNeeded)
        .confirmationDialog(
            "Load a sample business?",
            isPresented: $showSampleConfirm,
            titleVisibility: .visible
        ) {
            Button("Load Sample Data") { loadSampleBusiness() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This adds a few clearly-labelled demo records (customers, suppliers, and items) so you can explore Mercantis Hub with realistic content. Every sample record is tagged “(Sample)” and is safe to delete. Only do this on an empty or test database.")
        }
    }

    // MARK: - Welcome

    private var welcomeHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(MercantisTheme.brandPrimary)
                Text(HubManifest.appName)
                    .font(.largeTitle.weight(.semibold))
            }
            Text("Run quotes, orders, invoices, stock, payments, and ledgers from a native, offline-first business workspace.")
                .font(.title3)
                .foregroundStyle(.primary)
                .frame(maxWidth: 780, alignment: .leading)
            Text("Everything is stored locally on your Mac. Start by setting up your business below, or add a few records to see how it works.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 780, alignment: .leading)
        }
    }

    // MARK: - Sample business

    private var sampleBusinessCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(MercantisTheme.brandPrimary)
            VStack(alignment: .leading, spacing: 4) {
                Text("Explore with a sample business")
                    .font(.headline)
                Text("Your database is empty. Load a small set of demo customers, suppliers, and items — all clearly tagged “(Sample)” — to see Mercantis Hub in action. You can delete them any time.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Load Sample Business…") { showSampleConfirm = true }
                    .buttonStyle(MercantisPrimaryButtonStyle())
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .hubCardSurface(tinted: true)
    }

    private func sampleResultBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(MercantisTheme.success)
            Text(message)
                .font(.callout)
            Spacer(minLength: 0)
            Button("Dismiss") { sampleMessage = nil }
                .buttonStyle(.borderless)
        }
        .hubCardSurface()
    }

    // MARK: - Getting Started checklist

    private var gettingStartedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading("Getting Started")
            VStack(spacing: 0) {
                let items = checklistItems
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    checklistRow(item)
                    if index < items.count - 1 { Divider() }
                }
            }
            .hubCardSurface(padding: 0)
        }
    }

    private enum ChecklistStatus {
        case ready          // record(s) exist
        case needsSetup     // DocType exists but has no records yet
        case comingSoon     // capability is planned, DocType not in this build

        var label: String {
            switch self {
            case .ready:      return "Ready"
            case .needsSetup: return "Needs setup"
            case .comingSoon: return "Coming soon"
            }
        }
        var color: Color {
            switch self {
            case .ready:      return MercantisTheme.success
            case .needsSetup: return MercantisTheme.warning
            case .comingSoon: return MercantisTheme.textMuted
            }
        }
        var systemImage: String {
            switch self {
            case .ready:      return "checkmark.circle.fill"
            case .needsSetup: return "circle"
            case .comingSoon: return "clock"
            }
        }
    }

    private struct ChecklistItem: Identifiable {
        let id: String
        let title: String
        let explanation: String
        let status: ChecklistStatus
        /// DocType to open when the user taps the action button. `nil` for
        /// planned items so no action is offered.
        let docTypeID: String?
    }

    /// Builds the checklist from the DocTypes actually present in
    /// `HubManifest`. Statuses come from real record counts — never faked.
    private var checklistItems: [ChecklistItem] {
        func item(_ id: String,
                  _ title: String,
                  _ explanation: String,
                  docTypeID: String?,
                  planned: Bool = false) -> ChecklistItem {
            // A capability is "coming soon" if it's explicitly planned, or if
            // its backing DocType isn't part of this build.
            if planned || docTypeID == nil || HubManifest.docType(for: docTypeID!) == nil {
                return ChecklistItem(id: id, title: title, explanation: explanation,
                                     status: .comingSoon, docTypeID: nil)
            }
            let ready = count(docTypeID!) > 0
            return ChecklistItem(id: id, title: title, explanation: explanation,
                                 status: ready ? .ready : .needsSetup,
                                 docTypeID: docTypeID!)
        }

        return [
            // Business profile has no dedicated Company DocType yet, so it is
            // shown as planned rather than pretending it's configurable.
            item("profile", "Business profile",
                 "Company name, registration, and defaults.",
                 docTypeID: HubManifest.docType(for: "Company") != nil ? "Company" : nil,
                 planned: HubManifest.docType(for: "Company") == nil),
            item("currency", "Currency",
                 "The currencies you trade and report in.",
                 docTypeID: "Currency"),
            item("fiscalyear", "Fiscal Year",
                 "Accounting periods for reporting.",
                 docTypeID: HubManifest.docType(for: "FiscalYear") != nil ? "FiscalYear" : nil,
                 planned: HubManifest.docType(for: "FiscalYear") == nil),
            item("accounts", "Chart of Accounts",
                 "The ledger accounts your transactions post to.",
                 docTypeID: "Account"),
            item("tax", "Tax setup",
                 "Sales/purchase tax rates and templates.",
                 docTypeID: HubManifest.docType(for: "Tax") != nil ? "Tax" : nil,
                 planned: HubManifest.docType(for: "Tax") == nil),
            item("customers", "Customers",
                 "The businesses and people you sell to.",
                 docTypeID: "Customer"),
            item("suppliers", "Suppliers",
                 "The vendors you buy from.",
                 docTypeID: "Supplier"),
            item("items", "Items",
                 "The products and services you trade.",
                 docTypeID: "Item"),
            item("warehouses", "Warehouses",
                 "Locations where you hold stock.",
                 docTypeID: "Warehouse")
        ]
    }

    private func checklistRow(_ item: ChecklistItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.status.systemImage)
                .font(.system(size: 16))
                .foregroundStyle(item.status.color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                Text(item.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(item.status.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(item.status.color)
            if let id = item.docTypeID, let docType = HubManifest.docType(for: id) {
                Button(count(id) > 0 ? "Open" : "Set up") {
                    onSelect(.docType(docType))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Quick start

    private struct QuickAction: Identifiable {
        let docTypeID: String
        let title: String
        var id: String { docTypeID }
    }

    private struct QuickActionGroup: Identifiable {
        let label: String
        let actions: [QuickAction]
        var id: String { label }
    }

    /// Business-flow-oriented quick actions, grouped logically. Only actions
    /// whose DocType actually exists in `HubManifest` are shown.
    private var quickStartGroups: [QuickActionGroup] {
        let raw: [(String, [QuickAction])] = [
            ("Masters", [
                QuickAction(docTypeID: "Customer", title: "Customer"),
                QuickAction(docTypeID: "Supplier", title: "Supplier"),
                QuickAction(docTypeID: "Item", title: "Item")
            ]),
            ("Sell", [
                QuickAction(docTypeID: "Quotation", title: "Quotation"),
                QuickAction(docTypeID: "SalesOrder", title: "Sales Order"),
                QuickAction(docTypeID: "SalesInvoice", title: "Sales Invoice")
            ]),
            ("Buy & Pay", [
                QuickAction(docTypeID: "PurchaseOrder", title: "Purchase Order"),
                QuickAction(docTypeID: "PaymentEntry", title: "Payment Entry")
            ])
        ]
        return raw.compactMap { label, actions in
            let available = actions.filter { HubManifest.docType(for: $0.docTypeID) != nil }
            return available.isEmpty ? nil : QuickActionGroup(label: label, actions: available)
        }
    }

    private var quickStartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading("Quick Start")
            ForEach(quickStartGroups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                        ForEach(group.actions) { action in
                            quickActionButton(action)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func quickActionButton(_ action: QuickAction) -> some View {
        if let docType = HubManifest.docType(for: action.docTypeID) {
            Button {
                onSelect(.docType(docType))
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.tint)
                    Text("New \(action.title)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .padding(12)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.separator, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Business snapshot

    private struct Metric: Identifiable {
        let id: String
        let title: String
        let value: Int
        let systemImage: String
        let docTypeID: String?
    }

    private var metrics: [Metric] {
        var result: [Metric] = []
        func add(_ id: String, _ title: String, _ value: Int, _ symbol: String, docTypeID: String?) {
            result.append(Metric(id: id, title: title, value: value, systemImage: symbol, docTypeID: docTypeID))
        }
        if HubManifest.docType(for: "Customer") != nil {
            add("customers", "Customers", count("Customer"), "person.2", docTypeID: "Customer")
        }
        if HubManifest.docType(for: "Item") != nil {
            add("items", "Items", count("Item"), "cube.box", docTypeID: "Item")
        }
        if HubManifest.docType(for: "SalesInvoice") != nil {
            add("openinv", "Open Invoices", openInvoiceCount, "doc.text", docTypeID: "SalesInvoice")
        }
        if HubManifest.docType(for: "Supplier") != nil {
            add("suppliers", "Suppliers", count("Supplier"), "shippingbox", docTypeID: "Supplier")
        }
        if HubManifest.docType(for: "StockEntry") != nil {
            add("stock", "Stock Entries", count("StockEntry"), "tray.full", docTypeID: "StockEntry")
        }
        if HubManifest.docType(for: "PaymentEntry") != nil {
            add("payments", "Payments", count("PaymentEntry"), "creditcard", docTypeID: "PaymentEntry")
        }
        return result
    }

    private var snapshotSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading("Business Snapshot")
            // Don't show a wall of zeros to a brand-new user — guide them instead.
            if metrics.allSatisfy({ $0.value == 0 }) {
                snapshotEmptyState
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(metrics) { metric in
                        metricTile(metric)
                    }
                }
            }
        }
    }

    private var snapshotEmptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("No business data yet", systemImage: "chart.bar.doc.horizontal")
                .font(.headline)
            Text("Once you add customers, items, and start raising documents, live figures — open invoices, stock, payments — appear here. Use Quick Start above, or load the sample business to see it populated.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .hubCardSurface()
    }

    private func metricTile(_ metric: Metric) -> some View {
        Button {
            if let id = metric.docTypeID, let docType = HubManifest.docType(for: id) {
                onSelect(.docType(docType))
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Label(metric.title, systemImage: metric.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                Text("\(metric.value)")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.separator, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recent activity

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading("Recent Activity")
            if recentRecords.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Nothing here yet", systemImage: "clock")
                        .font(.headline)
                    Text("Records you create show up here, newest first, so you can jump straight back into what you were working on.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .hubCardSurface()
            } else {
                VStack(spacing: 0) {
                    ForEach(recentRecords) { entry in
                        Button {
                            if let docType = HubManifest.docType(for: entry.docTypeID) {
                                onSelect(.docType(docType))
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "doc.text")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.title)
                                        .font(.system(size: 13, weight: .medium))
                                    Text(entry.docTypeName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(entry.updatedAt, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                .hubCardSurface(padding: 0)
            }
        }
    }

    // MARK: - What you can do today

    private struct BusinessArea: Identifiable {
        let id: String
        let title: String
        let detail: String
        let systemImage: String
    }

    private let businessAreas: [BusinessArea] = [
        BusinessArea(id: "crm", title: "Manage customers and contacts",
                     detail: "Keep customer details, contacts, and addresses in one place.",
                     systemImage: "person.2"),
        BusinessArea(id: "sell", title: "Create quotes, orders, and invoices",
                     detail: "Take a deal from quotation to sales order to invoice.",
                     systemImage: "cart"),
        BusinessArea(id: "buy", title: "Track suppliers and purchases",
                     detail: "Raise purchase orders and record what you owe.",
                     systemImage: "bag"),
        BusinessArea(id: "stock", title: "Record stock movements",
                     detail: "Receive, issue, and transfer inventory between warehouses.",
                     systemImage: "tray.full"),
        BusinessArea(id: "accounts", title: "Maintain accounts and payments",
                     detail: "Post journals, record payments, and keep your ledger straight.",
                     systemImage: "creditcard"),
        BusinessArea(id: "reports", title: "Review reports and dashboards",
                     detail: "See where the business stands as your data grows.",
                     systemImage: "chart.bar")
    ]

    private var businessAreasSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading("What You Can Do Today")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], spacing: 12) {
                ForEach(businessAreas) { area in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: area.systemImage)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.tint)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(area.title)
                                .font(.system(size: 14, weight: .semibold))
                            Text(area.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .hubCardSurface()
                }
            }
            // Incomplete areas are acknowledged honestly, but kept secondary.
            Text("Advanced areas such as manufacturing, tax, and multi-company support are still being refined and may feel less polished than the core trade workflow above.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: 780, alignment: .leading)
                .padding(.top, 2)
        }
    }

    // MARK: - Helpers

    private func sectionHeading(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    private func count(_ docTypeID: String) -> Int {
        counts[docTypeID] ?? 0
    }

    /// A database is "empty" for first-run purposes when none of the primary
    /// master DocTypes have any records. (Reference / derived tables are
    /// ignored — they only ever appear as a side effect of real records.)
    private var isDatabaseEmpty: Bool {
        ["Customer", "Supplier", "Item", "Warehouse", "Account"]
            .allSatisfy { count($0) == 0 }
    }

    // MARK: - Data loading

    private func reloadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        reload()
    }

    private func reload() {
        loadCounts()
        loadRecentRecords()
    }

    private func loadCounts() {
        var fresh: [String: Int] = [:]
        for id in countedDocTypeIDs where HubManifest.docType(for: id) != nil {
            fresh[id] = (try? engine.list(docType: id))?.count ?? 0
        }
        counts = fresh

        // "Open" = submitted (docStatus == 1) and not yet settled/cancelled.
        // Uses only top-level Document fields so no FieldValue decoding is
        // needed and no fabricated outstanding figure is implied.
        if HubManifest.docType(for: "SalesInvoice") != nil {
            let invoices = (try? engine.list(docType: "SalesInvoice")) ?? []
            openInvoiceCount = invoices.filter {
                $0.docStatus == 1 && $0.status != "Paid" && $0.status != "Cancelled"
            }.count
        } else {
            openInvoiceCount = 0
        }
    }

    private struct RecentRecord: Identifiable {
        let id: String
        let title: String
        let docTypeID: String
        let docTypeName: String
        let updatedAt: Date
    }

    private func loadRecentRecords() {
        var collected: [RecentRecord] = []
        for docType in HubManifest.allDocTypes {
            let documents = (try? engine.list(docType: docType.id)) ?? []
            for doc in documents {
                collected.append(
                    RecentRecord(
                        id: "\(docType.id):\(doc.id)",
                        title: displayTitle(for: doc, docType: docType),
                        docTypeID: docType.id,
                        docTypeName: docType.name,
                        updatedAt: doc.updatedAt
                    )
                )
            }
        }
        recentRecords = Array(
            collected
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(8)
        )
    }

    private func displayTitle(for document: Document, docType: DocType) -> String {
        if case let .string(value)? = document.fields[docType.titleField], !value.isEmpty {
            return value
        }
        if !document.id.isEmpty {
            return document.id
        }
        return "Untitled \(docType.name)"
    }

    // MARK: - Sample business

    /// Builds an unsaved draft document for `docTypeID` with the given fields.
    /// Mirrors `HubRecordWorkspaceView.makeDraftDocument` so saves go through
    /// the same engine path a real user-created record would.
    private func newDoc(_ docTypeID: String, _ fields: [String: FieldValue]) -> Document {
        let now = Date()
        return Document(
            id: "",
            docType: docTypeID,
            company: "",
            status: "",
            createdAt: now,
            updatedAt: now,
            syncVersion: 0,
            syncState: .local,
            fields: fields,
            children: [:]
        )
    }

    /// Loads a small, clearly-labelled sample business.
    ///
    /// Design notes / limitations:
    /// - Saves run through `DocumentEngine.save` — validation is **not**
    ///   bypassed. Each save is best-effort: if a record can't be created on
    ///   this database (e.g. a required link target is missing) it is skipped
    ///   rather than aborting the whole load, and the final message reflects
    ///   what was actually created.
    /// - Only **master data** is created. Transactional documents
    ///   (Quotation / Sales Order / Sales Invoice) are intentionally omitted:
    ///   they are submittable and require posting accounts plus a configured
    ///   Chart of Accounts that an empty database doesn't have, so generating
    ///   them blindly would either fail validation or post unsafe ledger
    ///   entries. See Docs/HUB-UX-POLISH-PASS.md.
    /// - Every record is tagged "(Sample)" and carries a deletable note, so it
    ///   can never be mistaken for real production data.
    private func loadSampleBusiness() {
        var created: [String: Int] = [:]
        func bump(_ key: String) { created[key, default: 0] += 1 }

        // Customers (autoname naming-series; only simple required fields).
        let customers = [
            ("Aurora Wholesale (Sample)", "Company"),
            ("Bayside Retail (Sample)", "Individual")
        ]
        for (name, type) in customers {
            let doc = newDoc("Customer", [
                "customer_name": .string(name),
                "customer_type": .string(type),
                "notes": .string(sampleNote)
            ])
            if (try? engine.save(doc)) != nil { bump("Customer") }
        }

        // Suppliers (autoname; simple required fields).
        let suppliers = [
            ("Continental Supply Co (Sample)", "Company"),
            ("Delta Components (Sample)", "Company")
        ]
        for (name, type) in suppliers {
            let doc = newDoc("Supplier", [
                "supplier_name": .string(name),
                "supplier_type": .string(type),
                "notes": .string(sampleNote)
            ])
            if (try? engine.save(doc)) != nil { bump("Supplier") }
        }

        // Supporting masters for items. These DocTypes have no naming-series,
        // so we supply the id explicitly via `userSuppliedName`. Best-effort.
        if HubManifest.docType(for: "UOM") != nil {
            _ = try? engine.save(newDoc("UOM", ["uom_name": .string("Unit")]),
                                 userSuppliedName: "Unit")
        }
        if HubManifest.docType(for: "ItemGroup") != nil {
            _ = try? engine.save(newDoc("ItemGroup", ["item_group_name": .string("Sample Products")]),
                                 userSuppliedName: "Sample Products")
        }
        if HubManifest.docType(for: "Warehouse") != nil {
            let doc = newDoc("Warehouse", ["warehouse_name": .string("Main Store (Sample)")])
            if (try? engine.save(doc, userSuppliedName: "Main Store (Sample)")) != nil {
                bump("Warehouse")
            }
        }

        // Items reference the supporting masters above. Required link fields
        // mean these can fail on stricter validation, so each is best-effort.
        let items = [
            ("SAMPLE-001", "Sample Widget"),
            ("SAMPLE-002", "Sample Gadget"),
            ("SAMPLE-003", "Sample Gizmo")
        ]
        for (code, name) in items {
            let doc = newDoc("Item", [
                "item_code": .string(code),
                "item_name": .string(name),
                "item_group": .string("Sample Products"),
                "stock_uom": .string("Unit"),
                "description": .string(sampleNote)
            ])
            if (try? engine.save(doc)) != nil { bump("Item") }
        }

        reload()

        let order = ["Customer", "Supplier", "Item", "Warehouse"]
        let parts = order.compactMap { key -> String? in
            guard let n = created[key], n > 0 else { return nil }
            let noun = n == 1 ? key.lowercased() : "\(key.lowercased())s"
            return "\(n) \(noun)"
        }
        sampleMessage = parts.isEmpty
            ? "No sample records could be created on this database."
            : "Loaded sample data: " + parts.joined(separator: ", ") + ". All records are tagged “(Sample)” and safe to delete."
    }
}

// MARK: - Card chrome

private extension View {
    /// Shared card surface — secondary background, rounded corners, hairline
    /// border. `padding` defaults to a comfortable inset; pass 0 for rows that
    /// manage their own internal padding (lists, checklists).
    func hubCardSurface(padding: CGFloat = 16, tinted: Bool = false) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                tinted ? AnyShapeStyle(MercantisTheme.brandPrimarySoft)
                       : AnyShapeStyle(.background.secondary),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(tinted ? MercantisTheme.brandPrimaryBorder : Color(nsColor: .separatorColor),
                            lineWidth: 1)
            )
    }
}
