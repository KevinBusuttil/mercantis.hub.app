// mercantis hub
// Created by Kevin Busuttil on 12/04/2026.

// ADR-006: Sync policies — financial/transactional documents use `versionChecked`;
//          supplier master data uses `lastWriteWins`.

import Foundation

// Uses Core's DocType, FieldDefinition, SyncPolicy — imported from MercantisCore when dependency is wired up.

/// DocType catalog for the **Buying** module.
///
/// Covers the procure-to-pay pipeline: supplier master, purchase orders,
/// purchase receipts, and purchase invoices.
///
/// - ADR-006: `versionChecked` is required for all financial/transactional documents.
public enum Buying: Sendable {

    // MARK: - Supplier

    /// Represents a vendor or supplier of goods and services.
    ///
    /// Key fields:
    /// - `supplierName` (title field)
    /// - `supplierGroup`, `country`, `supplierType`
    ///
    /// Child tables:
    /// - `contacts` → `Contact`
    /// - `addresses` → `Address`
    ///
    /// Sync policy: `lastWriteWins` (ADR-006 — descriptive master data)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let supplier = HubDocTypeDescriptor(
        name: "Supplier",
        module: "Buying",
        syncPolicy: "lastWriteWins"
    )

    // MARK: - PurchaseOrder

    /// A formal order issued to a supplier for goods or services.
    ///
    /// Key fields:
    /// - `name` (title field, auto-generated)
    /// - `supplier`, `scheduleDate`, `status`
    ///
    /// Child tables:
    /// - `items` → purchase order line items
    /// - `taxes` → tax breakdown rows
    ///
    /// Sync policy: `versionChecked` (ADR-006 — transactional document)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let purchaseOrder = HubDocTypeDescriptor(
        name: "PurchaseOrder",
        module: "Buying",
        syncPolicy: "versionChecked"
    )

    // MARK: - PurchaseReceipt

    /// Records the physical receipt of goods from a supplier against a Purchase Order.
    ///
    /// Key fields:
    /// - `name` (title field, auto-generated)
    /// - `supplier`, `postingDate`, `status`
    ///
    /// Child tables:
    /// - `items` → received line items (with batch/serial tracking)
    ///
    /// Sync policy: `versionChecked` (ADR-006 — transactional inventory movement)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let purchaseReceipt = HubDocTypeDescriptor(
        name: "PurchaseReceipt",
        module: "Buying",
        syncPolicy: "versionChecked"
    )

    // MARK: - PurchaseInvoice

    /// The vendor invoice received from a supplier, driving accounts-payable entries.
    ///
    /// Key fields:
    /// - `name` (title field, auto-generated)
    /// - `supplier`, `postingDate`, `dueDate`, `status`, `outstandingAmount`
    ///
    /// Child tables:
    /// - `items` → invoice line items
    /// - `taxes` → tax breakdown rows
    ///
    /// Sync policy: `versionChecked` (ADR-006 — financial document)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let purchaseInvoice = HubDocTypeDescriptor(
        name: "PurchaseInvoice",
        module: "Buying",
        syncPolicy: "versionChecked"
    )

    // MARK: - All DocTypes

    /// All Buying DocType descriptors — will be passed to `AppManifest` when Core is available.
    /// - TODO: Replace `HubDocTypeDescriptor` elements with `DocType` values from MercantisCore.
    public static let allDocTypes: [HubDocTypeDescriptor] = [
        supplier, purchaseOrder, purchaseReceipt, purchaseInvoice,
    ]
}
