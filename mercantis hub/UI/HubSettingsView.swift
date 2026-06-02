import SwiftUI

/// The app's Settings (⌘,) window. Houses workspace configuration that used
/// to clutter the navigation sidebar: the business-type preset, the optional
/// modules, the advanced/accountant view, and re-running the setup wizard.
/// Per the macOS HIG, app settings belong here rather than in the sidebar.
struct HubSettingsView: View {

    @ObservedObject var settings: HubVisibilitySettings

    private var presetBinding: Binding<HubPreset> {
        Binding(
            get: { settings.preset ?? .services },
            set: { settings.apply($0) }
        )
    }

    var body: some View {
        Form {
            Section("Workspace") {
                Picker("Business type", selection: presetBinding) {
                    ForEach(HubPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                Text(presetBinding.wrappedValue.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Advanced / Accountant view", isOn: $settings.showAdvanced)
                    .help("Show the internal ledgers — GL Entry, Customer / Supplier Transactions, Settlements, Tax Transactions, and the Stock Ledger — that power balances, statements, and reports.")
            }

            Section {
                Toggle("Point of Sale", isOn: $settings.posEnabled)
                    .help("A touch-friendly till that posts real sales, payments, VAT, and stock movements.")
                Toggle("Deliveries", isOn: $settings.deliveriesEnabled)
                    .help("Sales deliveries and manual delivery-route planning.")
                Toggle("Manufacturing", isOn: $settings.manufacturingEnabled)
                    .help("BOMs, work orders, and production planning.")
            } header: {
                Text("Modules")
            } footer: {
                Text("Choosing a business type sets these for you; turn individual modules on or off any time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Setup") {
                Button("Run setup wizard…") {
                    settings.onboardingComplete = false
                }
                .help("Re-open the first-run wizard to change your business type or re-seed defaults.")
            }
        }
        .formStyle(.grouped)
        // Resizable: give a comfortable minimum + ideal size but let the
        // user grow the window (paired with `.windowResizability(.contentMinSize)`
        // on the Settings scene).
        .frame(minWidth: 420, idealWidth: 480, maxWidth: .infinity,
               minHeight: 460, idealHeight: 560, maxHeight: .infinity)
    }
}
