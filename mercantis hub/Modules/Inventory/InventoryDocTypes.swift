// mercantis hub
// Created by Kevin Busuttil on 12/04/2026.

// ADR-006: Sync policies — StockEntry uses `versionChecked` (transactional movement);
//          StockLedgerEntry uses `appendOnly` (immutable audit ledger);
//          item/warehouse master data uses `lastWriteWins`.

import Foundation

// Uses Core's DocType, FieldDefinition, SyncPolicy — imported from MercantisCore when dependency is wired up.

/// DocType catalog for the **Inventory** module.
///
/// Covers item master, warehouse setup, stock movements, the stock ledger,
/// and item groupings.
///
/// - ADR-006: `appendOnly` is used for ledger entries to preserve an immutable audit trail.
public enum Inventory: Sendable {

    // MARK: - Item

    /// Represents a physical product, raw material, or service that is bought or sold.
    ///
    /// Key fields:
    /// - `itemCode` (title field)
    /// - `itemName`, `itemGroup`, `stockUOM`, `isStockItem`, `hasSerialNo`, `hasBatchNo`
    ///
    /// Child tables:
    /// - `uomConversions` → unit-of-measure conversion rows
    /// - `supplierItems` → preferred supplier rows
    ///
    /// Sync policy: `lastWriteWins` (ADR-006 — master data)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let item = HubDocTypeDescriptor(
        name: "Item",
        module: "Inventory",
        syncPolicy: "lastWriteWins"
    )

    // MARK: - ItemGroup

    /// A hierarchical grouping for Items (e.g. Raw Material, Finished Goods).
    ///
    /// Key fields:
    /// - `itemGroupName` (title field)
    /// - `parentItemGroup`, `isGroup`
    ///
    /// Child tables: none
    ///
    /// Sync policy: `lastWriteWins` (ADR-006 — master data)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let itemGroup = HubDocTypeDescriptor(
        name: "ItemGroup",
        module: "Inventory",
        syncPolicy: "lastWriteWins"
    )

    // MARK: - Warehouse

    /// Represents a physical or logical storage location for inventory.
    ///
    /// Key fields:
    /// - `warehouseName` (title field)
    /// - `company`, `isGroup`, `parentWarehouse`
    ///
    /// Child tables: none
    ///
    /// Sync policy: `lastWriteWins` (ADR-006 — master data)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let warehouse = HubDocTypeDescriptor(
        name: "Warehouse",
        module: "Inventory",
        syncPolicy: "lastWriteWins"
    )

    // MARK: - StockEntry

    /// Records an inventory movement (receipt, issue, transfer, manufacture).
    ///
    /// Key fields:
    /// - `name` (title field, auto-generated)
    /// - `stockEntryType`, `postingDate`, `postingTime`, `status`
    ///
    /// Child tables:
    /// - `items` → stock entry detail rows (source/target warehouse, qty, rate)
    ///
    /// Sync policy: `versionChecked` (ADR-006 — transactional stock movement)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let stockEntry = HubDocTypeDescriptor(
        name: "StockEntry",
        module: "Inventory",
        syncPolicy: "versionChecked"
    )

    // MARK: - StockLedgerEntry

    /// An immutable ledger row written for every inventory movement, providing a full audit trail.
    ///
    /// Key fields:
    /// - `name` (title field, auto-generated)
    /// - `item`, `warehouse`, `postingDate`, `actualQty`, `valuationRate`, `stockValue`
    ///
    /// Child tables: none
    ///
    /// Sync policy: `appendOnly` (ADR-006 — immutable audit ledger; rows are never updated)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let stockLedgerEntry = HubDocTypeDescriptor(
        name: "StockLedgerEntry",
        module: "Inventory",
        syncPolicy: "appendOnly"
    )

    // MARK: - All DocTypes

    /// All Inventory DocType descriptors — will be passed to `AppManifest` when Core is available.
    /// - TODO: Replace `HubDocTypeDescriptor` elements with `DocType` values from MercantisCore.
    public static let allDocTypes: [HubDocTypeDescriptor] = [
        item, itemGroup, warehouse, stockEntry, stockLedgerEntry,
    ]
}
