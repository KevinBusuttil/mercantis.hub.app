import SwiftUI
import MercantisCore
import MercantisCoreUI

/// Settings for the opt-in AI fallback (ADR-049). Lets the user connect their
/// preferred LLM (Anthropic or any OpenAI-compatible endpoint) with their own
/// key, gated by a confidence threshold and a monthly cap. Port of the Flutter
/// `CaptureAiSettingsScreen`.
///
/// Storage:
///   • Non-secret settings live in `@AppStorage` as a JSON blob (see
///     `CaptureAiSettingsStore`).
///   • The API key is a secret. It is persisted via `CaptureAiKeyStore`, which
///     on a shipping build SHOULD write to the macOS/iOS Keychain. This file
///     ships a `UserDefaults`-backed stub with an explicit security note so the
///     screen is functional without a compile; swap the stub for a Keychain
///     implementation before release. (See KEYCHAIN NOTE below.)
struct CaptureAISettingsView: View {
    @State private var settings = CaptureAiSettingsStore.load()
    @State private var apiKey: String = CaptureAiKeyStore.load() ?? ""
    @State private var monthlyLimitText: String = ""
    @State private var obscureKey = true
    @State private var savedToast = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("When a receipt is hard to read on-device, the app can ask an "
                     + "AI to read it. This sends the photo to the provider you choose, "
                     + "using your own key. Off by default.")
                    .font(.system(size: 13))
                    .foregroundStyle(MercantisTheme.textSecondary)

                Toggle("Use AI for hard-to-read receipts", isOn: $settings.enabled)
                    .toggleStyle(.switch)

                Divider().overlay(MercantisTheme.hairline)

                Picker("Provider", selection: $settings.provider) {
                    Text("Anthropic (Claude)").tag(LlmProvider.anthropic)
                    Text("OpenAI-compatible").tag(LlmProvider.openAiCompatible)
                }
                .onChange(of: settings.provider) { _, newValue in onProviderChanged(newValue) }

                labelledField("API base URL", text: $settings.endpoint)

                labelledField("Model", text: $settings.model,
                              helper: "e.g. claude-opus-4-8, or your provider's model id")

                VStack(alignment: .leading, spacing: 4) {
                    Text("API key").font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MercantisTheme.textSecondary)
                    HStack {
                        Group {
                            if obscureKey {
                                SecureField("API key", text: $apiKey)
                            } else {
                                TextField("API key", text: $apiKey)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        Button {
                            obscureKey.toggle()
                        } label: {
                            Image(systemName: obscureKey ? "eye" : "eye.slash")
                        }
                        .buttonStyle(.borderless)
                    }
                    Text("Stored on this device. Use a scoped/limited key.")
                        .font(.system(size: 11))
                        .foregroundStyle(MercantisTheme.textTertiary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Ask AI when confidence is below \(Int((settings.threshold * 100).rounded()))%")
                        .font(.system(size: 13))
                    Slider(value: $settings.threshold, in: 0.3...0.9, step: 0.1)
                }

                labelledField("Monthly AI limit (cost cap)", text: $monthlyLimitText)

                Button {
                    save()
                } label: {
                    Text("Save").frame(maxWidth: .infinity)
                }
                .buttonStyle(MercantisPrimaryButtonStyle())
                .controlSize(.large)

                if savedToast {
                    Text("AI settings saved.")
                        .font(.system(size: 12))
                        .foregroundStyle(MercantisTheme.brandPrimary)
                }
            }
            .padding(20)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .background(MercantisTheme.appBackground)
        .navigationTitle("Smart capture (AI)")
        .onAppear { monthlyLimitText = String(settings.monthlyLimit) }
    }

    private func labelledField(_ label: String, text: Binding<String>, helper: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12, weight: .medium))
                .foregroundStyle(MercantisTheme.textSecondary)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
            if let helper {
                Text(helper).font(.system(size: 11))
                    .foregroundStyle(MercantisTheme.textTertiary)
            }
        }
    }

    /// Swap to the provider's default base URL if the field still holds the
    /// other provider's default (mirrors the Flutter `_onProviderChanged`).
    private func onProviderChanged(_ p: LlmProvider) {
        let trimmed = settings.endpoint.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty
            || settings.endpoint == LlmReceiptExtractor.anthropicBaseUrl
            || settings.endpoint == LlmReceiptExtractor.openAiBaseUrl {
            settings.endpoint = p == .anthropic
                ? LlmReceiptExtractor.anthropicBaseUrl
                : LlmReceiptExtractor.openAiBaseUrl
        }
    }

    private func save() {
        settings.endpoint = settings.endpoint.trimmingCharacters(in: .whitespaces)
        settings.model = settings.model.trimmingCharacters(in: .whitespaces)
        settings.monthlyLimit = Int(monthlyLimitText.trimmingCharacters(in: .whitespaces)) ?? 100
        CaptureAiSettingsStore.save(settings)
        CaptureAiKeyStore.save(apiKey.trimmingCharacters(in: .whitespaces))
        savedToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { savedToast = false }
    }
}

// MARK: - Settings persistence

/// Persists the non-secret `CaptureAiSettings` as a JSON blob in `UserDefaults`.
/// Port of the Flutter `captureAiSettingsProvider` storage.
enum CaptureAiSettingsStore {
    private static let key = "MercantisHub.capture.aiSettings"

    static func load() -> CaptureAiSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(CaptureAiSettings.self, from: data) else {
            return CaptureAiSettings()
        }
        return decoded
    }

    static func save(_ settings: CaptureAiSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// Stores the bring-your-own-key API secret.
///
/// KEYCHAIN NOTE (ADR-049 / security): the API key is a credential and SHOULD
/// be stored in the system Keychain (`kSecClassGenericPassword`,
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), not in `UserDefaults`.
/// This stub uses `UserDefaults` only so the screen is usable without extra
/// wiring; replace the two method bodies with a `Security`-framework
/// implementation (service: "app.mercantis.hub", account: "capture.ai.apiKey")
/// before shipping. The rest of the module reads the key exclusively through
/// `CaptureAiKeyStore.load()`, so swapping the backend is a one-file change.
enum CaptureAiKeyStore {
    private static let key = "MercantisHub.capture.aiApiKey" // TODO: move to Keychain

    static func load() -> String? {
        let v = UserDefaults.standard.string(forKey: key)
        return (v?.isEmpty ?? true) ? nil : v
    }

    static func save(_ apiKey: String) {
        if apiKey.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(apiKey, forKey: key)
        }
    }
}

/// Builds the configured `LlmReceiptExtractor` from stored settings + key, or
/// `nil` when the fallback is disabled / unconfigured. The Swift analogue of the
/// Flutter `captureServiceProvider`'s extractor assembly.
enum CaptureAiAssembly {
    static func makeExtractor() -> LlmReceiptExtractor? {
        let settings = CaptureAiSettingsStore.load()
        guard settings.enabled,
              let apiKey = CaptureAiKeyStore.load(),
              !settings.endpoint.isEmpty, !settings.model.isEmpty else { return nil }
        return LlmReceiptExtractor(
            provider: settings.provider,
            endpoint: settings.endpoint,
            model: settings.model,
            apiKey: apiKey
        )
    }

    static var threshold: Double { CaptureAiSettingsStore.load().threshold }
}
