// mercantis hub
// Created by Kevin Busuttil on 12/04/2026.

// ADR-006: Sync policies — WorkOrder uses `versionChecked` (transactional production document);
//          BillOfMaterials/Operation/Workstation use `lastWriteWins` (master data).

import Foundation

// Uses Core's DocType, FieldDefinition, SyncPolicy — imported from MercantisCore when dependency is wired up.

/// DocType catalog for the **Manufacturing** module.
///
/// Covers bills of materials, production work orders, operations, and workstations.
///
/// - ADR-006: `versionChecked` for work orders guards against concurrent production scheduling conflicts.
public enum Manufacturing: Sendable {

    // MARK: - BillOfMaterials

    /// Defines the component structure and operations required to manufacture an item.
    ///
    /// Key fields:
    /// - `item` (title field — the finished good)
    /// - `quantity`, `uom`, `isDefault`, `isActive`
    ///
    /// Child tables:
    /// - `items` → BOM item (component) rows
    /// - `operations` → BOM operation rows
    ///
    /// Sync policy: `lastWriteWins` (ADR-006 — master data)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let billOfMaterials = HubDocTypeDescriptor(
        name: "BillOfMaterials",
        module: "Manufacturing",
        syncPolicy: "lastWriteWins"
    )

    // MARK: - WorkOrder

    /// A production order that drives the manufacture of a quantity of a finished good.
    ///
    /// Key fields:
    /// - `name` (title field, auto-generated)
    /// - `productionItem`, `qty`, `plannedStartDate`, `status`, `bom`
    ///
    /// Child tables:
    /// - `requiredItems` → raw material rows
    /// - `operations` → production operation rows
    ///
    /// Sync policy: `versionChecked` (ADR-006 — transactional production document)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let workOrder = HubDocTypeDescriptor(
        name: "WorkOrder",
        module: "Manufacturing",
        syncPolicy: "versionChecked"
    )

    // MARK: - Operation

    /// A discrete manufacturing step (e.g. cutting, welding, painting).
    ///
    /// Key fields:
    /// - `operationName` (title field)
    /// - `defaultWorkstation`, `description`
    ///
    /// Child tables: none
    ///
    /// Sync policy: `lastWriteWins` (ADR-006 — master data)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let operation = HubDocTypeDescriptor(
        name: "Operation",
        module: "Manufacturing",
        syncPolicy: "lastWriteWins"
    )

    // MARK: - Workstation

    /// A physical or virtual station where manufacturing operations are performed.
    ///
    /// Key fields:
    /// - `workstationName` (title field)
    /// - `productionCapacity`, `workstationType`, `status`
    ///
    /// Child tables:
    /// - `workingHours` → operating-hour rows
    ///
    /// Sync policy: `lastWriteWins` (ADR-006 — master data)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let workstation = HubDocTypeDescriptor(
        name: "Workstation",
        module: "Manufacturing",
        syncPolicy: "lastWriteWins"
    )

    // MARK: - All DocTypes

    /// All Manufacturing DocType descriptors — will be passed to `AppManifest` when Core is available.
    /// - TODO: Replace `HubDocTypeDescriptor` elements with `DocType` values from MercantisCore.
    public static let allDocTypes: [HubDocTypeDescriptor] = [
        billOfMaterials, workOrder, operation, workstation,
    ]
}
