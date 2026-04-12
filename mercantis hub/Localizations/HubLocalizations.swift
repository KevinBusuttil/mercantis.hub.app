// mercantis hub
// Created by Kevin Busuttil on 12/04/2026.

import Foundation

// Uses Core's LocalizationBundle — imported from MercantisCore when dependency is wired up.

/// Stub namespace for Hub's localization string catalogs.
///
/// Localization bundles are declarative `LocalizationBundle` values (ADR-004) that map
/// string keys to translated values for each supported locale. Core's rendering engine
/// resolves keys at runtime; Hub only provides the bundle data.
///
/// - ADR-004: Localization bundles are declarative manifest data.
/// - ADR-008: No dynamic code loading; all string mappings are statically declared.
public enum HubLocalizations: Sendable {

    // MARK: - English (en)

    /// Localization bundle for the **English** (`en`) locale.
    ///
    /// This is the primary / fallback locale for Mercantis Hub.
    ///
    /// - TODO: Populate with all Hub UI string keys mapped to English values.
    /// - TODO: Implement using `LocalizationBundle` from MercantisCore.
    public static var english: Never {
        fatalError("english is a stub — implement with Core's LocalizationBundle.")
    }

    // MARK: - Maltese (mt)

    /// Localization bundle for the **Maltese** (`mt`) locale.
    ///
    /// Maltese is a co-official language of Malta and is supported as a first-class
    /// locale in Mercantis Hub given the target market.
    ///
    /// - TODO: Populate with all Hub UI string keys mapped to Maltese translations.
    /// - TODO: Implement using `LocalizationBundle` from MercantisCore.
    public static var maltese: Never {
        fatalError("maltese is a stub — implement with Core's LocalizationBundle.")
    }

    // MARK: - All Bundles

    /// All localization bundles — will be wired into `HubManifest.build()`.
    /// - TODO: Replace with an array of `LocalizationBundle` values from MercantisCore.
    public static let allBundles: [Any] = []
}
