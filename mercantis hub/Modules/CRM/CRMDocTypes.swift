// mercantis hub
// Created by Kevin Busuttil on 12/04/2026.

// ADR-006: Sync policies — descriptive master data uses `lastWriteWins`;
//          transactional pipeline documents use `versionChecked`.

import Foundation

// Uses Core's DocType, FieldDefinition, SyncPolicy — imported from MercantisCore when dependency is wired up.

/// DocType catalog for the **CRM** module.
///
/// Covers customer master data, contact management, address book, lead pipeline,
/// opportunity tracking, and communication log.
///
/// - ADR-006: Descriptive / master-data DocTypes use `lastWriteWins`.
///            Pipeline DocTypes (Lead, Opportunity) also use `lastWriteWins`
///            because they are single-owner records with low concurrent-edit risk.
public enum CRM: Sendable {

    // MARK: - Customer

    /// Represents a business or individual that purchases goods or services.
    ///
    /// Key fields:
    /// - `customerName` (title field)
    /// - `customerGroup`, `territory`, `customerType`
    ///
    /// Child tables:
    /// - `contacts` → `Contact`
    /// - `addresses` → `Address`
    ///
    /// Sync policy: `lastWriteWins` (ADR-006 — descriptive master data)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let customer = HubDocTypeDescriptor(
        name: "Customer",
        module: "CRM",
        syncPolicy: "lastWriteWins"
    )

    // MARK: - Contact

    /// A person associated with a Customer, Supplier, or Lead.
    ///
    /// Key fields:
    /// - `firstName`, `lastName` (title field: full name)
    /// - `email`, `phone`, `designation`
    ///
    /// Child tables: none
    ///
    /// Sync policy: `lastWriteWins` (ADR-006 — descriptive master data)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let contact = HubDocTypeDescriptor(
        name: "Contact",
        module: "CRM",
        syncPolicy: "lastWriteWins"
    )

    // MARK: - Address

    /// A postal or billing address linked to a party (Customer, Supplier, etc.).
    ///
    /// Key fields:
    /// - `addressTitle` (title field)
    /// - `addressLine1`, `city`, `country`, `pinCode`
    ///
    /// Child tables: none
    ///
    /// Sync policy: `lastWriteWins` (ADR-006 — descriptive master data)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let address = HubDocTypeDescriptor(
        name: "Address",
        module: "CRM",
        syncPolicy: "lastWriteWins"
    )

    // MARK: - Lead

    /// A prospective customer captured through marketing or sales outreach.
    ///
    /// Key fields:
    /// - `leadName` (title field)
    /// - `source`, `status`, `email`, `mobile`, `company`
    ///
    /// Child tables: none
    ///
    /// Sync policy: `lastWriteWins` (ADR-006)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let lead = HubDocTypeDescriptor(
        name: "Lead",
        module: "CRM",
        syncPolicy: "lastWriteWins"
    )

    // MARK: - Opportunity

    /// A qualified sales opportunity derived from a Lead.
    ///
    /// Key fields:
    /// - `title` (title field)
    /// - `customer`, `opportunityType`, `status`, `expectedClosingDate`, `probability`
    ///
    /// Child tables:
    /// - `items` → opportunity line items
    ///
    /// Sync policy: `lastWriteWins` (ADR-006)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let opportunity = HubDocTypeDescriptor(
        name: "Opportunity",
        module: "CRM",
        syncPolicy: "lastWriteWins"
    )

    // MARK: - Communication

    /// A log entry capturing an email, call, note, or other communication with a party.
    ///
    /// Key fields:
    /// - `subject` (title field)
    /// - `communicationMedium`, `status`, `sender`, `recipients`, `content`
    ///
    /// Child tables: none
    ///
    /// Sync policy: `lastWriteWins` (ADR-006 — descriptive data)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let communication = HubDocTypeDescriptor(
        name: "Communication",
        module: "CRM",
        syncPolicy: "lastWriteWins"
    )

    // MARK: - All DocTypes

    /// All CRM DocType descriptors — will be passed to `AppManifest` when Core is available.
    /// - TODO: Replace `HubDocTypeDescriptor` elements with `DocType` values from MercantisCore.
    public static let allDocTypes: [HubDocTypeDescriptor] = [
        customer, contact, address, lead, opportunity, communication,
    ]
}
