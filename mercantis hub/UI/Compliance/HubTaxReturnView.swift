import SwiftUI
import MercantisCore
import MercantisCoreUI

/// Phase 3 — guided tax return. The owner picks a period and sees the few
/// numbers they actually file: tax collected on sales, tax paid on purchases,
/// and the net to pay or reclaim — in plain language, with a per-band breakdown
/// underneath. They can export it and "file" it, which records a `TaxFiling`
/// snapshot and (optionally) locks the books through the period so the figures
/// can't change by accident.
struct HubTaxReturnView: View {

    let engine: DocumentEngine

    /// The filing period presets, kept friendly for a non-accountant.
    private enum PeriodChoice: String, CaseIterable, Identifiable {
        case thisQuarter = "This quarter"
        case lastQuarter = "Last quarter"
        case thisYear = "This year"
        case allTime = "All time"
        var id: String { rawValue }
    }

    @State private var period: PeriodChoice = .thisQuarter
    @State private var taxTrans: [Document] = []
    @State private var codeNames: [String: String] = [:]
    @State private var style: HubTaxStyle = .vat
    @State private var currency: String?
    @State private var fyStart: Date?
    @State private var fyEnd: Date?
    @State private var lockOnFile = true
    @State private var message: String?
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                periodCard
                let ret = currentReturn
                headlineCard(ret)
                boxesCard(ret)
                if !ret.lines.isEmpty { breakdownCard(ret) }
                fileCard(ret)
                if let message { banner(message, "checkmark.seal.fill", MercantisTheme.success) }
                if let error { banner(error, "exclamationmark.triangle.fill", MercantisTheme.danger) }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .navigationTitle("Tax Return")
        .onAppear(perform: load)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your \(vocab.noun) return").font(.title2).bold()
            Text("Pick a period and we'll total your \(vocab.noun.lowercased()) for you — what you collected, what you paid, and the difference. No ledgers, no boxes to puzzle over.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var periodCard: some View {
        MercantisInspectorCard("Period", systemImage: "calendar") {
            Picker("", selection: $period) {
                ForEach(PeriodChoice.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if let label = periodRangeLabel {
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func headlineCard(_ ret: TaxReturnBuilder.Return) -> some View {
        let net = ret.netPayable
        let owes = net >= 0
        return MercantisInspectorCard(owes ? vocab.netDueLabel : vocab.netReclaimLabel,
                                      systemImage: owes ? "arrow.up.circle.fill" : "arrow.down.circle.fill") {
            HStack(alignment: .firstTextBaseline) {
                Text(money(abs(net)))
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(owes ? MercantisTheme.textPrimary : MercantisTheme.success)
                Spacer()
            }
            Text(ret.isEmpty
                 ? "No taxable activity in this period yet."
                 : (owes
                    ? "This is what you owe the tax authority for the period."
                    : "You paid more \(vocab.noun.lowercased()) than you collected — you're due this back."))
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func boxesCard(_ ret: TaxReturnBuilder.Return) -> some View {
        MercantisInspectorCard("The numbers", systemImage: "number.square") {
            boxRow(vocab.outputLabel, ret.totalOutputTax)
            boxRow(vocab.inputLabel, ret.totalInputTax)
            Divider()
            boxRow(ret.netPayable >= 0 ? vocab.netDueLabel : vocab.netReclaimLabel,
                   abs(ret.netPayable), bold: true)
            Divider().padding(.vertical, 2)
            boxRow("Taxable sales", ret.totalOutputBase, muted: true)
            boxRow("Taxable purchases", ret.totalInputBase, muted: true)
        }
    }

    private func breakdownCard(_ ret: TaxReturnBuilder.Return) -> some View {
        MercantisInspectorCard("By rate", systemImage: "list.bullet") {
            VStack(spacing: 0) {
                HStack {
                    Text("Band").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text("Collected").font(.caption2).foregroundStyle(.secondary).frame(width: 90, alignment: .trailing)
                    Text("Paid").font(.caption2).foregroundStyle(.secondary).frame(width: 90, alignment: .trailing)
                }
                .padding(.bottom, 4)
                ForEach(ret.lines, id: \.code) { line in
                    Divider()
                    HStack {
                        Text("\(line.name) · \(rateText(line.rate))").font(.system(size: 13))
                        Spacer()
                        Text(money(line.outputTax)).font(.system(size: 13)).frame(width: 90, alignment: .trailing)
                        Text(money(line.inputTax)).font(.system(size: 13)).frame(width: 90, alignment: .trailing)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private func fileCard(_ ret: TaxReturnBuilder.Return) -> some View {
        MercantisInspectorCard("File this return", systemImage: "tray.and.arrow.up") {
            Toggle(isOn: $lockOnFile) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lock the books for this period").font(.callout)
                    Text("Stops anything dated up to the period end from changing after you file.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .disabled(periodEnd == nil)
            HStack {
                Button("Export CSV") { exportCSV(ret) }
                    .buttonStyle(.bordered)
                    .disabled(ret.isEmpty)
                Spacer()
                Button("Mark as filed") { file(ret) }
                    .buttonStyle(.borderedProminent)
                    .disabled(ret.isEmpty)
            }
        }
    }

    // MARK: - Derived

    private var vocab: TaxReturnBuilder.Vocabulary { TaxReturnBuilder.vocabulary(for: style) }

    private var currentReturn: TaxReturnBuilder.Return {
        TaxReturnBuilder.build(taxTrans: taxTrans, codeNames: codeNames, style: style,
                               from: periodStart, to: periodEnd)
    }

    private var periodStart: Date? { periodRange.start }
    private var periodEnd: Date? { periodRange.end }

    private var periodRange: (start: Date?, end: Date?) {
        let calendar = Calendar.current
        let today = Date()
        switch period {
        case .allTime:
            return (nil, nil)
        case .thisYear:
            if let fyStart, let fyEnd { return (fyStart, fyEnd) }
            let year = calendar.component(.year, from: today)
            let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1))
            return (start, today)
        case .thisQuarter:
            let q = quarterStart(of: today, calendar: calendar)
            return (q, calendar.date(byAdding: DateComponents(month: 3, day: -1), to: q))
        case .lastQuarter:
            let thisQ = quarterStart(of: today, calendar: calendar)
            let lastQ = calendar.date(byAdding: DateComponents(month: -3), to: thisQ) ?? thisQ
            return (lastQ, calendar.date(byAdding: DateComponents(month: 3, day: -1), to: lastQ))
        }
    }

    private var periodRangeLabel: String? {
        guard let s = periodStart, let e = periodEnd else {
            return period == .allTime ? "All transactions to date." : nil
        }
        return "\(s.formatted(date: .abbreviated, time: .omitted)) – \(e.formatted(date: .abbreviated, time: .omitted))"
    }

    private var periodLabelText: String {
        switch period {
        case .allTime: return "All time"
        case .thisYear, .thisQuarter, .lastQuarter:
            guard let s = periodStart, let e = periodEnd else { return period.rawValue }
            return "\(s.formatted(date: .abbreviated, time: .omitted)) – \(e.formatted(date: .abbreviated, time: .omitted))"
        }
    }

    private func quarterStart(of date: Date, calendar: Calendar) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: date)
        let month = comps.month ?? 1
        let qMonth = ((month - 1) / 3) * 3 + 1
        return calendar.date(from: DateComponents(year: comps.year, month: qMonth, day: 1)) ?? date
    }

    // MARK: - Data

    private func load() {
        guard !loaded else { return }
        loaded = true
        let company = (try? engine.list(docType: "Company"))?.first
        style = TaxReturnBuilder.style(forRegime: stringField(company?.fields["tax_regime"]))
        currency = stringField(company?.fields["default_currency"])
        taxTrans = (try? engine.list(docType: "TaxTrans")) ?? []
        codeNames = Dictionary(
            ((try? engine.list(docType: "TaxCode")) ?? [])
                .map { ($0.id, stringField($0.fields["tax_code_name"]) ?? $0.id) },
            uniquingKeysWith: { first, _ in first }
        )
        if let fy = (try? engine.list(docType: "FiscalYear"))?.first(where: { isActive($0) }) {
            fyStart = dateField(fy.fields["year_start_date"])
            fyEnd = dateField(fy.fields["year_end_date"])
        }
    }

    private func exportCSV(_ ret: TaxReturnBuilder.Return) {
        message = nil; error = nil
        let result = reportResult(ret)
        #if os(macOS)
        do {
            switch try HubReportCSV.export(result, named: "\(vocab.noun) Return") {
            case .saved(let url): message = "Saved to \(url.lastPathComponent)."
            case .cancelled: break
            }
        } catch { self.error = (error as NSError).localizedDescription }
        #else
        message = "Export is available on macOS."
        #endif
    }

    private func file(_ ret: TaxReturnBuilder.Return) {
        message = nil; error = nil
        let boxes: [ChildRow] = ret.lines.enumerated().map { index, line in
            ChildRow(id: "box-\(index)", rowIndex: index, fields: [
                "label": .string("\(line.name) · \(rateText(line.rate))"),
                "rate": .double(line.rate),
                "output_tax": .double(line.outputTax),
                "input_tax": .double(line.inputTax),
            ])
        }
        var fields: [String: FieldValue] = [
            "period_label": .string(periodLabelText),
            "tax_noun": .string(vocab.noun),
            "output_tax": .double(ret.totalOutputTax),
            "input_tax": .double(ret.totalInputTax),
            "net_payable": .double(ret.netPayable),
            "output_base": .double(ret.totalOutputBase),
            "input_base": .double(ret.totalInputBase),
            "status": .string("Filed"),
            "filed_on": .date(Date()),
            "filed_by": .string(HubIdentity.userId()),
        ]
        if let periodStart { fields["period_start"] = .date(periodStart) }
        if let periodEnd { fields["period_end"] = .date(periodEnd) }

        let filing = Document(id: "", docType: "TaxFiling", company: "", status: "",
                              createdAt: Date(), updatedAt: Date(), syncVersion: 0, syncState: .local,
                              fields: fields, children: ["boxes": boxes])
        guard (try? engine.save(filing)) != nil else {
            error = "Couldn't save the filing."
            return
        }

        if lockOnFile, let periodEnd, applyLock(through: periodEnd) {
            message = "Filed and locked the books through \(periodEnd.formatted(date: .abbreviated, time: .omitted))."
        } else {
            message = "Return filed. You'll find it under Tax Filings."
        }
    }

    /// Set the Business-Profile books-lock date, never moving it earlier than an
    /// existing lock. Returns true when the lock now covers `date`.
    private func applyLock(through date: Date) -> Bool {
        guard var company = (try? engine.list(docType: "Company"))?.first else { return false }
        if let existing = dateField(company.fields["books_lock_date"]), existing >= date { return true }
        company.fields["books_lock_date"] = .date(date)
        return (try? engine.save(company)) != nil
    }

    private func reportResult(_ ret: TaxReturnBuilder.Return) -> ReportResult {
        var rows: [[String?]] = ret.lines.map { line in
            [line.name, rateText(line.rate),
             money(line.outputBase), money(line.outputTax),
             money(line.inputBase), money(line.inputTax)]
        }
        rows.append(["Total", "",
                     money(ret.totalOutputBase), money(ret.totalOutputTax),
                     money(ret.totalInputBase), money(ret.totalInputTax)])
        rows.append(["Net \(vocab.noun)", "", "", "", "", money(ret.netPayable)])
        return ReportResult(
            columns: ["Band", "Rate", "Output Base", "Output Tax", "Input Base", "Input Tax"],
            rows: rows
        )
    }

    // MARK: - Small views / helpers

    private func boxRow(_ label: String, _ value: Double, bold: Bool = false, muted: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: bold ? .semibold : .regular))
                .foregroundStyle(muted ? AnyShapeStyle(.secondary) : AnyShapeStyle(MercantisTheme.textPrimary))
            Spacer()
            Text(money(value))
                .font(.system(size: 14, weight: bold ? .semibold : .regular))
                .foregroundStyle(muted ? AnyShapeStyle(.secondary) : AnyShapeStyle(MercantisTheme.textPrimary))
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
    private func rateText(_ rate: Double) -> String {
        rate == rate.rounded() ? String(format: "%.0f%%", rate) : String(format: "%.2f%%", rate)
    }

    private func isActive(_ doc: Document) -> Bool {
        if case .bool(let b)? = doc.fields["is_active"] { return b }
        return false
    }
    private func stringField(_ value: FieldValue?) -> String? {
        guard case .string(let s)? = value else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
    private func dateField(_ value: FieldValue?) -> Date? {
        switch value { case .date(let d), .dateTime(let d): return d; default: return nil }
    }
}
