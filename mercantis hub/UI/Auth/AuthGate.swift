import SwiftUI
import MercantisCoreUI

/// Sits between the app entry and the workspace shell: blocks the app until an
/// operator profile is unlocked. First run sends you through profile creation;
/// thereafter a cold start re-locks and shows the passcode gate.
///
/// Ported from the Flutter `AuthGate` (`lib/auth/auth_gate.dart`). On macOS
/// there is no nested `MaterialApp` to swap, so this is a plain wrapper `View`
/// that returns either the lock UI or `content`.
struct AuthGate<Content: View>: View {
    @ObservedObject var store: AuthStore
    @ViewBuilder var content: () -> Content

    var body: some View {
        Group {
            if !store.hasProfiles {
                OperatorSetupView(store: store, firstRun: true)
            } else if !store.unlocked {
                LockScreen(store: store)
            } else {
                content()
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .background(MercantisTheme.appBackground)
        // Animate the gate → shell crossfade so unlocking feels instantaneous
        // rather than a hard cut.
        .animation(.easeInOut(duration: 0.2), value: store.unlocked)
        .animation(.easeInOut(duration: 0.2), value: store.hasProfiles)
    }
}
