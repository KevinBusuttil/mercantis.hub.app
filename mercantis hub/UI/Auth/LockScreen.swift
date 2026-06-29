import SwiftUI
import MercantisCoreUI

/// The passcode gate shown on a locked cold start: pick an operator, enter the
/// passcode. Pre-selects the last active profile so the common case is a single
/// passcode entry.
///
/// Ported from the Flutter `LockScreen` (`lib/auth/lock_screen.dart`), styled
/// with the Hub `MercantisTheme` tokens to match the rest of the macOS app.
struct LockScreen: View {
    @ObservedObject var store: AuthStore

    @State private var selectedId: String?
    @State private var passcode: String = ""
    @State private var error: String?
    @State private var showAddOperator = false
    @FocusState private var passcodeFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header

                VStack(spacing: 8) {
                    ForEach(store.profiles) { profile in
                        operatorRow(profile)
                    }
                }

                passcodeField

                Button(action: unlock) {
                    Label("Unlock", systemImage: "lock.open")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selectedId == nil || passcode.isEmpty)

                if let error {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(MercantisTheme.danger)
                }

                Button {
                    showAddOperator = true
                } label: {
                    Label("Add operator", systemImage: "person.badge.plus")
                }
                .buttonStyle(.borderless)
            }
            .padding(24)
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
        }
        .background(MercantisTheme.appBackground)
        .onAppear {
            if selectedId == nil {
                selectedId = store.activeId ?? store.profiles.first?.id
            }
            passcodeFocused = true
        }
        .sheet(isPresented: $showAddOperator) {
            OperatorSetupView(store: store, firstRun: false)
                .frame(minWidth: 460, minHeight: 480)
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(MercantisTheme.brandPrimary, in: RoundedRectangle(cornerRadius: 14))
            Text("Neuradix Atlas")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(MercantisTheme.textPrimary)
            Text("Choose an operator to sign in")
                .font(.callout)
                .foregroundStyle(MercantisTheme.textSecondary)
        }
        .padding(.bottom, 4)
    }

    private func operatorRow(_ profile: OperatorProfile) -> some View {
        let isSelected = profile.id == selectedId
        return Button {
            selectedId = profile.id
            passcode = ""
            error = nil
            passcodeFocused = true
        } label: {
            HStack(spacing: 12) {
                Text(profile.initials)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(MercantisTheme.brandPrimary, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(MercantisTheme.textPrimary)
                    if !profile.email.isEmpty {
                        Text(profile.email)
                            .font(.caption)
                            .foregroundStyle(MercantisTheme.textSecondary)
                    }
                }
                Spacer()
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? MercantisTheme.brandPrimary : MercantisTheme.textTertiary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? MercantisTheme.brandPrimarySoft : MercantisTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? MercantisTheme.brandPrimaryBorder : MercantisTheme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var passcodeField: some View {
        SecureField("Passcode", text: $passcode)
            .textFieldStyle(.roundedBorder)
            .controlSize(.large)
            .focused($passcodeFocused)
            .disabled(selectedId == nil)
            .onSubmit(unlock)
    }

    private func unlock() {
        guard let id = selectedId, !passcode.isEmpty else { return }
        if store.unlock(profileId: id, passcode: passcode) {
            // The gate observes `store.unlocked` and rebuilds into the shell.
            error = nil
        } else {
            error = "Incorrect passcode."
            passcode = ""
            passcodeFocused = true
        }
    }
}
