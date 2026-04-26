// mercantis hub
// Created by Kevin Busuttil on 12/04/2026.

// ADR-001: Mercantis Hub is a first-party ERP application built exclusively on
//          Mercantis Core's public APIs. It must never bypass Core internals.
// ADR-004: The app is described as a declarative AppManifest — no dynamic code loading.
// ADR-007: Hub references only the public API surface exposed by MercantisCore.

import Foundation

// Uses Core's AppManifest, DocType, SyncPolicy — imported from MercantisCore when dependency is wired up.

/// `HubManifest` constructs the declarative `AppManifest` that registers Mercantis Hub
/// with Mercantis Core's app system.
///
/// - ADR-001: Hub is a first-party consumer of Core's public APIs.
/// - ADR-004: The manifest is purely declarative data — no imperative logic.
/// - ADR-007: Only types from Core's public API surface are referenced here.
public enum HubManifest: Sendable {

    /// The canonical application identifier for Mercantis Hub.
    public static let appID = "app.mercantis.hub"

    /// The human-readable display name for Mercantis Hub.
    public static let appName = "Mercantis Hub"

    /// Builds and returns the full `AppManifest` for Mercantis Hub.
    ///
    /// The manifest wires together all ERP module DocType catalogs, workflows,
    /// automation rules, dashboards, reports, permissions, and localizations.
    ///
    /// - Returns: A fully-populated `AppManifest` value. (Uses Core's `AppManifest`)
    /// - TODO: Replace the placeholder return with an actual `AppManifest` initialisation
    ///         once MercantisCore is imported as a Swift package dependency.
    /// - TODO: Wire up DocType definitions from all modules:
    ///         CRM, Sales, Buying, Inventory, Accounting, HR, Manufacturing, Projects, Assets.
    /// - TODO: Wire up `HubWorkflows.allWorkflows`.
    /// - TODO: Wire up `HubAutomation.allRules`.
    /// - TODO: Wire up `HubDashboards.allDashboards`.
    /// - TODO: Wire up `HubReports.allReports`.
    /// - TODO: Wire up `HubPermissions.allRoles`.
    /// - TODO: Wire up `HubLocalizations.allBundles`.
    public static func build() -> Never {
        fatalError(
            "HubManifest.build() is a stub. Import MercantisCore and implement this function."
        )
    }
}
