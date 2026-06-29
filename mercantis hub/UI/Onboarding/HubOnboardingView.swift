import SwiftUI
import MercantisCore
import MercantisCoreUI

/// Phase 1 (Accounting Autopilot) — first-run setup wizard. Asks the owner four
/// plain questions — business name, country, whether they're tax-registered,
/// and their accounting basis — plus a business-type preset, then seeds a
/// complete jurisdiction-appropriate accounting setup (chart of accounts with
/// equity and expenses, tax codes, fiscal year, warehouse, and a Business
/// Profile wired to those defaults). Re-openable later from the sidebar.
struct HubOnboardingView: View {

    let engine: DocumentEngine
    @ObservedObject var settings: HubVisibilitySettings

    @State private var businessName = ""
    @State private var countryId = HubJurisdictionLibrary.generic.id
    @State private var currency = HubJurisdictionLibrary.generic.currencyCode
    @State private var currencyEdited = false
    @State private var taxRegistered = true
    @State private var taxId = ""
    @State private var basis: HubAccountingBasis = .accrual
    @State private var preset: HubPreset = .services
    @State private var mode: HubUserMode = .owner
    @State private var working = false
    /// True when a Business Profile already exists — the wizard is re-run as an
    /// "update" rather than a first-run setup.
    @State private var isUpdate = false
    @State private var originalCountryId = HubJurisdictionLibrary.generic.id
    @State private var originalCurrency = HubJurisdictionLibrary.generic.currencyCode

    private let currencies = ["EUR", "USD", "GBP", "CAD"]

    private var jurisdiction: Jurisdiction {
        HubJurisdictionLibrary.jurisdiction(id: countryId)
    }

    private var leviesTax: Bool { jurisdiction.taxStyle != .none }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                businessSection
                jurisdictionSection
                presetSection
                modeSection
                if jurisdictionChanged { jurisdictionCaution }
                actions
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .frame(minWidth: 560, minHeight: 640)
        .onAppear {
            preset = settings.preset ?? .services
            mode = settings.userMode
            loadExistingProfile()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(isUpdate ? "Review your setup" : "Welcome to Mercantis Hub").font(.title).bold()
            Text(isUpdate
                 ? "Update your business details below. We'll apply the changes and top up anything that's missing — your existing accounts and records stay exactly as they are."
                 : "Tell us a few things about your business and we'll set up your accounts, tax, and a focused workspace automatically. You won't need to understand any accounting — and you can change all of this later.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    /// Pre-fill from the existing Business Profile so a re-run shows current
    /// values (and "Save changes" doesn't overwrite them with wizard defaults).
    private func loadExistingProfile() {
        guard let company = (try? engine.list(docType: "Company"))?.first else { return }
        isUpdate = true
        if let name = companyString(company.fields["business_name"]) { businessName = name }
        if let code = companyString(company.fields["default_currency"]) { currency = code }
        if let countryName = companyString(company.fields["country"]),
           let match = HubJurisdictionLibrary.all.first(where: { $0.name == countryName }) {
            countryId = match.id
        }
        if case .bool(let registered)? = company.fields["tax_registered"] { taxRegistered = registered }
        if let tid = companyString(company.fields["vat_tax_number"]) { taxId = tid }
        if let stored = companyString(company.fields["accounting_basis"]),
           let parsed = HubAccountingBasis(rawValue: stored) { basis = parsed }
        // Remember the loaded jurisdiction/currency to detect a risky change, and
        // keep the loaded currency from being auto-overwritten by a country edit.
        originalCountryId = countryId
        originalCurrency = currency
        currencyEdited = true
    }

    private func companyString(_ value: FieldValue?) -> String? {
        guard case .string(let s)? = value else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var businessSection: some View {
        MercantisInspectorCard("Your Business", systemImage: "building.2") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Business name").font(.caption).foregroundStyle(.secondary)
                    TextField("e.g. Bay Street Coffee", text: $businessName)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Currency").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $currency) {
                        ForEach(currencies, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 280)
                    .onChange(of: currency) { _, _ in currencyEdited = true }
                }
            }
        }
    }

    private var jurisdictionSection: some View {
        MercantisInspectorCard("Country & Tax", systemImage: "globe") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Where is your business based?").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $countryId) {
                        ForEach(HubJurisdictionLibrary.all) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 320)
                    .onChange(of: countryId) { _, _ in
                        // Default the currency to the country's, unless the user
                        // has already chosen one explicitly.
                        if !currencyEdited { currency = jurisdiction.currencyCode }
                    }
                    Text("Sets up a chart of accounts and tax codes that suit your country.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                if leviesTax {
                    Toggle(isOn: $taxRegistered) {
                        Text("Registered for \(jurisdiction.taxRegimeLabel)")
                    }
                    if taxRegistered {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(jurisdiction.taxIdLabel).font(.caption).foregroundStyle(.secondary)
                            TextField(jurisdiction.taxIdLabel, text: $taxId)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 320)
                        }
                        Text("We'll add \(jurisdiction.taxRegimeLabel) codes and apply the standard rate to new invoices automatically.")
                            .font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Text("No tax will be added to your invoices until you register.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("How do you account for income and costs?").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $basis) {
                        ForEach(HubAccountingBasis.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 280)
                    Text(basis.blurb).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What kind of business is this?").font(.headline)
            ForEach(HubPreset.allCases) { option in
                presetCard(option)
            }
        }
    }

    private func presetCard(_ option: HubPreset) -> some View {
        Button {
            preset = option
        } label: {
            HStack(spacing: 14) {
                Image(systemName: option.systemImage)
                    .font(.system(size: 22))
                    .frame(width: 36)
                    .foregroundStyle(preset == option ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title).font(.body).bold()
                    Text(option.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: preset == option ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(preset == option ? Color.accentColor : Color.secondary.opacity(0.4))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(preset == option ? Color.accentColor.opacity(0.10) : Color.gray.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(preset == option ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var modeSection: some View {
        MercantisInspectorCard("How much detail do you want?", systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("", selection: $mode) {
                    ForEach(HubUserMode.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)
                Text(mode.blurb).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    /// On a re-run, warn that switching country or currency layers a second
    /// jurisdiction's tax codes/accounts rather than replacing the first.
    private var jurisdictionChanged: Bool {
        isUpdate && (countryId != originalCountryId || currency != originalCurrency)
    }

    private var jurisdictionCaution: some View {
        Label("Changing your country or currency adds the new tax codes and accounts alongside the existing ones rather than replacing them. For a clean switch, start a fresh workspace instead.",
              systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(MercantisTheme.warning)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MercantisTheme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var actions: some View {
        HStack {
            Button(isUpdate ? "Cancel" : "Skip for now") { settings.onboardingComplete = true }
                .buttonStyle(.link)
            Spacer()
            Button {
                finish()
            } label: {
                Text(working ? (isUpdate ? "Saving…" : "Setting up…")
                             : (isUpdate ? "Save changes" : "Get Started"))
                    .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(working)
        }
    }

    private func finish() {
        working = true
        // Honour the chosen currency even if it differs from the country's
        // suggested one.
        let base = jurisdiction
        let resolved = Jurisdiction(
            id: base.id, name: base.name, currencyCode: currency,
            taxStyle: base.taxStyle, taxRegimeLabel: base.taxRegimeLabel, taxIdLabel: base.taxIdLabel
        )
        HubOnboardingSeeder.seed(
            engine: engine,
            businessName: businessName,
            jurisdiction: resolved,
            registered: leviesTax && taxRegistered,
            taxId: taxId,
            basis: basis,
            preset: preset
        )
        settings.apply(preset)
        settings.userMode = mode
        settings.onboardingComplete = true
    }
}
