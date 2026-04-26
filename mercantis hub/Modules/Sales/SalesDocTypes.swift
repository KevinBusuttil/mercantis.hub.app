// mercantis hub
// Created by Kevin Busuttil on 12/04/2026.

// ADR-006: Sync policies — financial/transactional documents use `versionChecked`
//          to prevent silent overwrites; pricing master data uses `lastWriteWins`.

import Foundation

// Uses Core's DocType, FieldDefinition, SyncPolicy — imported from MercantisCore when dependency is wired up.

/// DocType catalog for the **Sales** module.
///
/// Covers the full order-to-cash pipeline: quotations, sales orders, delivery notes,
/// sales invoices, and pricing rules.
///
/// - ADR-006: `versionChecked` is required for all financial/transactional documents.
public enum Sales: Sendable {

    // MARK: - Quotation

    /// A price offer issued to a prospective customer before an order is placed.
    ///
    /// Key fields:
    /// - `name` (title field, auto-generated)
    /// - `customer`, `validTill`, `status`
    ///
    /// Child tables:
    /// - `items` → quotation line items
    /// - `taxes` → tax breakdown rows
    ///
    /// Sync policy: `versionChecked` (ADR-006 — transactional sales document)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let quotation = HubDocTypeDescriptor(
        name: "Quotation",
        module: "Sales",
        syncPolicy: "versionChecked"
    )

    // MARK: - SalesOrder

    /// A confirmed order from a customer, binding the sale.
    ///
    /// Key fields:
    /// - `name` (title field, auto-generated)
    /// - `customer`, `deliveryDate`, `status`, `orderType`
    ///
    /// Child tables:
    /// - `items` → order line items
    /// - `taxes` → tax breakdown rows
    /// - `paymentSchedule` → payment milestone rows
    ///
    /// Sync policy: `versionChecked` (ADR-006 — financial transactional document)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let salesOrder = HubDocTypeDescriptor(
        name: "SalesOrder",
        module: "Sales",
        syncPolicy: "versionChecked"
    )

    // MARK: - DeliveryNote

    /// Records the physical shipment of goods to a customer against a Sales Order.
    ///
    /// Key fields:
    /// - `name` (title field, auto-generated)
    /// - `customer`, `postingDate`, `status`
    ///
    /// Child tables:
    /// - `items` → delivery line items (with batch/serial tracking)
    ///
    /// Sync policy: `versionChecked` (ADR-006 — transactional inventory movement)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let deliveryNote = HubDocTypeDescriptor(
        name: "DeliveryNote",
        module: "Sales",
        syncPolicy: "versionChecked"
    )

    // MARK: - SalesInvoice

    /// The financial invoice issued to a customer, driving accounts-receivable entries.
    ///
    /// Key fields:
    /// - `name` (title field, auto-generated)
    /// - `customer`, `postingDate`, `dueDate`, `status`, `outstandingAmount`
    ///
    /// Child tables:
    /// - `items` → invoice line items
    /// - `taxes` → tax breakdown rows
    /// - `payments` → payment allocation rows
    ///
    /// Sync policy: `versionChecked` (ADR-006 — financial document; must not be silently overwritten)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let salesInvoice = HubDocTypeDescriptor(
        name: "SalesInvoice",
        module: "Sales",
        syncPolicy: "versionChecked"
    )

    // MARK: - PricingRule

    /// Defines conditional pricing logic (discounts, rate overrides) applied to sales documents.
    ///
    /// Key fields:
    /// - `title` (title field)
    /// - `applyOn`, `itemCode`, `itemGroup`, `brand`, `minQty`, `maxQty`, `rateOrDiscount`
    ///
    /// Child tables: none
    ///
    /// Sync policy: `lastWriteWins` (ADR-006 — pricing configuration / master data)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let pricingRule = HubDocTypeDescriptor(
        name: "PricingRule",
        module: "Sales",
        syncPolicy: "lastWriteWins"
    )

    // MARK: - All DocTypes

    /// All Sales DocType descriptors — will be passed to `AppManifest` when Core is available.
    /// - TODO: Replace `HubDocTypeDescriptor` elements with `DocType` values from MercantisCore.
    public static let allDocTypes: [HubDocTypeDescriptor] = [
        quotation, salesOrder, deliveryNote, salesInvoice, pricingRule,
    ]
}
