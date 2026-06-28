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
    @State private var working = false

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
                actions
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .frame(minWidth: 560, minHeight: 640)
        .onAppear { preset = settings.preset ?? .services }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Welcome to Mercantis Hub").font(.title).bold()
            Text("Tell us a few things about your business and we'll set up your accounts, tax, and a focused workspace automatically. You won't need to understand any accounting — and you can change all of this later.")
                .font(.callout).foregroundStyle(.secondary)
        }
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

    private var actions: some View {
        HStack {
            Button("Skip for now") { settings.onboardingComplete = true }
                .buttonStyle(.link)
            Spacer()
            Button {
                finish()
            } label: {
                Text(working ? "Setting up…" : "Get Started").frame(minWidth: 120)
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
            basis: basis
        )
        settings.apply(preset)
        settings.onboardingComplete = true
    }
}
