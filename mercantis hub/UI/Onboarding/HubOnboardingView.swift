import SwiftUI
import MercantisCore
import MercantisCoreUI

/// Phase 8 — first-run setup wizard. Asks the user their business type,
/// applies the matching preset (which controls module visibility), and
/// seeds the initial Business Setup records (currency, fiscal year,
/// warehouse, chart of accounts, Business Profile). Re-openable later from
/// the sidebar to change the preset.
struct HubOnboardingView: View {

    let engine: DocumentEngine
    @ObservedObject var settings: HubVisibilitySettings

    @State private var businessName = ""
    @State private var currency = "EUR"
    @State private var preset: HubPreset = .services
    @State private var working = false

    private let currencies = ["EUR", "USD", "GBP"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                businessSection
                presetSection
                actions
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .frame(minWidth: 560, minHeight: 600)
        .onAppear { preset = settings.preset ?? .services }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Welcome to Mercantis Hub").font(.title).bold()
            Text("Tell us about your business and we'll set up a focused workspace with sensible defaults. You can change any of this later.")
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
                    .frame(maxWidth: 240)
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
        HubOnboardingSeeder.seed(engine: engine, businessName: businessName, currencyCode: currency)
        settings.apply(preset)
        settings.onboardingComplete = true
    }
}
