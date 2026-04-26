// mercantis hub
// Created by Kevin Busuttil on 12/04/2026.

// ADR-006: Sync policies — AssetMovement/AssetDepreciation use `versionChecked`
//          (financial/transactional records); Asset master data uses `lastWriteWins`.

import Foundation

// Uses Core's DocType, FieldDefinition, SyncPolicy — imported from MercantisCore when dependency is wired up.

/// DocType catalog for the **Assets** module.
///
/// Covers fixed asset records, physical location movements, and depreciation schedules.
///
/// - ADR-006: `versionChecked` for movement and depreciation entries prevents silent
///            overwrites of financial asset-register data.
public enum Assets: Sendable {

    // MARK: - Asset

    /// Represents a fixed asset owned by the company (e.g. vehicle, machinery, property).
    ///
    /// Key fields:
    /// - `assetName` (title field)
    /// - `assetCategory`, `location`, `purchaseDate`, `grossPurchaseAmount`, `status`
    ///
    /// Child tables:
    /// - `financeBooks` → depreciation schedule rows per finance book
    ///
    /// Sync policy: `lastWriteWins` (ADR-006 — master data)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let asset = HubDocTypeDescriptor(
        name: "Asset",
        module: "Assets",
        syncPolicy: "lastWriteWins"
    )

    // MARK: - AssetMovement

    /// Records the physical transfer of an asset between locations or custodians.
    ///
    /// Key fields:
    /// - `name` (title field, auto-generated)
    /// - `purpose`, `transactionDate`, `company`
    ///
    /// Child tables:
    /// - `assets` → asset movement item rows (source/target location, custodian)
    ///
    /// Sync policy: `versionChecked` (ADR-006 — financial/transactional asset-register document)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let assetMovement = HubDocTypeDescriptor(
        name: "AssetMovement",
        module: "Assets",
        syncPolicy: "versionChecked"
    )

    // MARK: - AssetDepreciation

    /// A depreciation journal entry that reduces the book value of an asset over time.
    ///
    /// Key fields:
    /// - `name` (title field, auto-generated)
    /// - `asset`, `financeBook`, `scheduledDate`, `depreciationAmount`, `assetValueAfterDepreciation`
    ///
    /// Child tables: none
    ///
    /// Sync policy: `versionChecked` (ADR-006 — financial asset-register document)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let assetDepreciation = HubDocTypeDescriptor(
        name: "AssetDepreciation",
        module: "Assets",
        syncPolicy: "versionChecked"
    )

    // MARK: - All DocTypes

    /// All Assets DocType descriptors — will be passed to `AppManifest` when Core is available.
    /// - TODO: Replace `HubDocTypeDescriptor` elements with `DocType` values from MercantisCore.
    public static let allDocTypes: [HubDocTypeDescriptor] = [
        asset, assetMovement, assetDepreciation,
    ]
}
