import Foundation
import Combine
import SwiftUI

/// Owns the on-device operator profiles and the lock state, and is the single
/// source of truth for "who is the current operator".
///
/// Ported from the Flutter `AuthNotifier` (`lib/auth/auth_store.dart`). The
/// Flutter app persists the profile list inside a synced `Hub Auth` document so
/// it rides the sync engine; the Swift Hub is offline-first / single-device and
/// already keeps comparable local-only state (device id, user id, saved report
/// variants) in `UserDefaults`, so this store does the same. The active session
/// is remembered but always re-locked on a cold start.
///
/// ### Persistence / Keychain note
/// Only a salted, stretched SHA-256 *digest* of each passcode is stored (see
/// `OperatorProfile`), never the passcode itself, so `UserDefaults` is an
/// acceptable store for the digest + metadata. If this app later needs to
/// resist offline disk inspection (e.g. a shared-device deployment), move the
/// `profiles` blob to the macOS Keychain (`kSecClassGenericPassword`,
/// service `"MercantisHub.auth"`) — the JSON encoding here is the value you'd
/// hand to `SecItemAdd`/`SecItemUpdate` unchanged.
@MainActor
final class AuthStore: ObservableObject {

    /// All on-device operator profiles, oldest first.
    @Published private(set) var profiles: [OperatorProfile] = []

    /// The profile whose session is active (signed in), even while locked.
    @Published private(set) var activeId: String?

    /// Whether the active profile has passed the passcode this run.
    @Published private(set) var unlocked: Bool = false

    private static let profilesKey = "MercantisHub.auth.profiles"
    private static let activeKey   = "MercantisHub.auth.activeId"

    private let defaults: UserDefaults

    // MARK: - Derived state

    var hasProfiles: Bool { !profiles.isEmpty }

    var active: OperatorProfile? {
        profiles.first { $0.id == activeId }
    }

    /// The operator that should drive the current-user identity. Falls back to
    /// `nil` until a profile is unlocked, so callers can keep the existing
    /// `HubIdentity` identity as the pre-unlock default (see wiring notes).
    var currentOperator: OperatorProfile? {
        guard let active, unlocked else { return nil }
        return active
    }

    // MARK: - Lifecycle

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hydrate()
    }

    private func hydrate() {
        if let data = defaults.data(forKey: Self.profilesKey),
           let decoded = try? JSONDecoder().decode([OperatorProfile].self, from: data) {
            profiles = decoded
        }
        let stored = defaults.string(forKey: Self.activeKey)
        activeId = (stored?.isEmpty == false) ? stored : nil
        // A cold start always re-locks: the user must re-enter a passcode.
        unlocked = false
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: Self.profilesKey)
        }
        defaults.set(activeId ?? "", forKey: Self.activeKey)
    }

    // MARK: - Mutations

    /// Create a profile. The first one created is signed in and unlocked
    /// immediately (you just proved you know its passcode by setting it).
    @discardableResult
    func createProfile(
        name: String,
        email: String,
        passcode: String,
        roles: Set<String> = ["System Manager"]
    ) -> OperatorProfile {
        let profile = OperatorProfile.create(
            id: "op-\(Int(Date().timeIntervalSince1970 * 1_000_000))",
            name: name,
            email: email,
            passcode: passcode,
            roles: roles
        )
        let first = profiles.isEmpty
        profiles.append(profile)
        if first {
            activeId = profile.id
            unlocked = true
        }
        persist()
        return profile
    }

    /// Verify `passcode` for `profileId`; on success start an unlocked session.
    @discardableResult
    func unlock(profileId: String, passcode: String) -> Bool {
        guard let profile = profiles.first(where: { $0.id == profileId }) else { return false }
        guard profile.verify(passcode) else { return false }
        activeId = profileId
        unlocked = true
        persist()
        return true
    }

    /// Re-lock without forgetting who is signed in.
    func lock() {
        unlocked = false
    }

    /// Forget the active session entirely (returns to the profile picker).
    func signOut() {
        activeId = nil
        unlocked = false
        persist()
    }

    @discardableResult
    func changePasscode(profileId: String, current: String, next: String) -> Bool {
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else { return false }
        guard profiles[index].verify(current) else { return false }
        profiles[index] = profiles[index].withPasscode(next)
        persist()
        return true
    }

    func removeProfile(_ profileId: String) {
        profiles.removeAll { $0.id == profileId }
        if activeId == profileId {
            activeId = nil
            unlocked = false
        }
        persist()
    }
}
