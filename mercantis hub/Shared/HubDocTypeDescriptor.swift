// mercantis hub
// Created by Kevin Busuttil on 12/04/2026.

import Foundation

// Uses Core's DocType, SyncPolicy — imported from MercantisCore when dependency is wired up.

/// A lightweight placeholder descriptor for a DocType, used throughout Hub's module
/// catalogs until `DocType` from MercantisCore is available as an imported dependency.
///
/// - TODO: Remove this type entirely once MercantisCore is imported as a Swift package.
///         All usages will be replaced with Core's `DocType` value type.
public struct HubDocTypeDescriptor: Sendable {
    /// The programmatic name of the DocType (e.g. `"Customer"`).
    public let name: String
    /// The ERP module this DocType belongs to (e.g. `"CRM"`).
    public let module: String
    /// A string tag representing the intended sync policy.
    /// Will map to Core's `SyncPolicy` enum (ADR-006) when MercantisCore is imported.
    public let syncPolicy: String

    public init(name: String, module: String, syncPolicy: String) {
        self.name = name
        self.module = module
        self.syncPolicy = syncPolicy
    }
}
