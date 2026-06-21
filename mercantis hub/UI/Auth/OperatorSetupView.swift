import SwiftUI
import MercantisCoreUI

/// Create (and, on the lock screen, add) an operator profile and its passcode.
/// On first run this is the gate's landing screen; it is also presented as a
/// sheet from the lock screen / Settings to manage operators.
///
/// Ported from the Flutter `OperatorSetupScreen`
/// (`lib/auth/operator_setup_screen.dart`). When not first-run it also lists
/// the existing operators with a remove affordance, which on macOS is the
/// natural place to manage the roster (Settings-adjacent).
struct OperatorSetupView: View {
    @ObservedObject var store: AuthStore

    /// True when no profiles exist yet (renders as a full landing page rather
    /// than a managed roster with a dismiss button).
    let firstRun: Bool

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var email = ""
    @State private var passcode = ""
    @State private var confirm = ""
    @State private var error: String?

    private static let minLength = 4

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if firstRun {
                    landingHeader
                } else {
                    Text("Add operator")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(MercantisTheme.textPrimary)
                }

                createForm

                if !firstRun && !store.profiles.isEmpty {
                    Divider().padding(.vertical, 4)
                    rosterSection
                }
            }
            .padding(24)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
        }
        .background(MercantisTheme.appBackground)
        .toolbar {
            if !firstRun {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var landingHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(MercantisTheme.brandPrimary, in: RoundedRectangle(cornerRadius: 12))
                Text("Create your operator")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(MercantisTheme.textPrimary)
            }
            Text("Operators sign in on this device with a passcode. Add more later from the lock screen or Settings.")
                .font(.callout)
                .foregroundStyle(MercantisTheme.textSecondary)
        }
        .padding(.bottom, 4)
    }

    private var createForm: some View {
        VStack(spacing: 12) {
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
            TextField("Email (optional)", text: $email)
                .textFieldStyle(.roundedBorder)
            SecureField("Passcode", text: $passcode)
                .textFieldStyle(.roundedBorder)
            SecureField("Confirm passcode", text: $confirm)
                .textFieldStyle(.roundedBorder)
                .onSubmit(create)

            Button(action: create) {
                Label(firstRun ? "Create & sign in" : "Add operator",
                      systemImage: "person.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if let error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(MercantisTheme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var rosterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Operators")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MercantisTheme.textSecondary)
            ForEach(store.profiles) { profile in
                HStack(spacing: 12) {
                    Text(profile.initials)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(MercantisTheme.brandPrimary, in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(profile.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(MercantisTheme.textPrimary)
                        if profile.id == store.activeId {
                            Text("Signed in")
                                .font(.caption2)
                                .foregroundStyle(MercantisTheme.success)
                        }
                    }
                    Spacer()
                    Button(role: .destructive) {
                        store.removeProfile(profile.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    // Don't let the roster be emptied while signed in — there
                    // must always remain at least one way back in.
                    .disabled(store.profiles.count <= 1)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(MercantisTheme.surface)
                )
            }
        }
    }

    private func create() {
        if let problem = validate() {
            error = problem
            return
        }
        let wasUnlocked = store.unlocked
        let profile = store.createProfile(name: name.trimmingCharacters(in: .whitespaces),
                                          email: email.trimmingCharacters(in: .whitespaces),
                                          passcode: passcode)
        // Adding from the lock screen (already had profiles, still locked):
        // sign straight into the new profile.
        if !wasUnlocked && store.active?.id != profile.id {
            store.unlock(profileId: profile.id, passcode: passcode)
        }
        error = nil
        if !firstRun {
            dismiss()
        }
        // First run: the gate observes the now-unlocked state and rebuilds.
    }

    private func validate() -> String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "Enter a name." }
        if passcode.count < Self.minLength { return "Passcode must be at least \(Self.minLength) characters." }
        if passcode != confirm { return "Passcodes do not match." }
        return nil
    }
}
