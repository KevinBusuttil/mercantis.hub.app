// mercantis hub
// Created by Kevin Busuttil on 12/04/2026.

// ADR-006: Sync policies — JournalEntry/PaymentEntry use `versionChecked` (financial transactions);
//          GLEntry uses `appendOnly` (immutable general-ledger audit trail);
//          Account/FiscalYear/CostCenter master data uses `lastWriteWins`.

import Foundation

// Uses Core's DocType, FieldDefinition, SyncPolicy — imported from MercantisCore when dependency is wired up.

/// DocType catalog for the **Accounting** module.
///
/// Covers the chart of accounts, general ledger, journal entries, payment entries,
/// fiscal years, and cost centres.
///
/// - ADR-006: `appendOnly` for GL entries ensures an immutable double-entry audit trail.
public enum Accounting: Sendable {

    // MARK: - Account

    /// A node in the chart of accounts (asset, liability, income, expense, equity).
    ///
    /// Key fields:
    /// - `accountName` (title field)
    /// - `accountType`, `parentAccount`, `isGroup`, `company`, `currency`
    ///
    /// Child tables: none
    ///
    /// Sync policy: `lastWriteWins` (ADR-006 — master data)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let account = HubDocTypeDescriptor(
        name: "Account",
        module: "Accounting",
        syncPolicy: "lastWriteWins"
    )

    // MARK: - FiscalYear

    /// Defines the company's accounting year boundaries.
    ///
    /// Key fields:
    /// - `yearName` (title field)
    /// - `yearStartDate`, `yearEndDate`, `companies`
    ///
    /// Child tables:
    /// - `companies` → fiscal year company rows
    ///
    /// Sync policy: `lastWriteWins` (ADR-006 — master data)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let fiscalYear = HubDocTypeDescriptor(
        name: "FiscalYear",
        module: "Accounting",
        syncPolicy: "lastWriteWins"
    )

    // MARK: - CostCenter

    /// A hierarchical node for allocating income/expense to business units.
    ///
    /// Key fields:
    /// - `costCenterName` (title field)
    /// - `parentCostCenter`, `isGroup`, `company`
    ///
    /// Child tables: none
    ///
    /// Sync policy: `lastWriteWins` (ADR-006 — master data)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let costCenter = HubDocTypeDescriptor(
        name: "CostCenter",
        module: "Accounting",
        syncPolicy: "lastWriteWins"
    )

    // MARK: - JournalEntry

    /// A manual double-entry accounting record (debit/credit pairs).
    ///
    /// Key fields:
    /// - `name` (title field, auto-generated)
    /// - `postingDate`, `voucherType`, `totalDebit`, `totalCredit`, `status`
    ///
    /// Child tables:
    /// - `accounts` → journal entry account rows (debit/credit lines)
    ///
    /// Sync policy: `versionChecked` (ADR-006 — financial transactional document)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let journalEntry = HubDocTypeDescriptor(
        name: "JournalEntry",
        module: "Accounting",
        syncPolicy: "versionChecked"
    )

    // MARK: - PaymentEntry

    /// Records a payment received from a customer or made to a supplier.
    ///
    /// Key fields:
    /// - `name` (title field, auto-generated)
    /// - `paymentType`, `party`, `postingDate`, `paidAmount`, `receivedAmount`, `status`
    ///
    /// Child tables:
    /// - `references` → payment-to-invoice reconciliation rows
    /// - `deductions` → write-off/discount rows
    ///
    /// Sync policy: `versionChecked` (ADR-006 — financial transactional document)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let paymentEntry = HubDocTypeDescriptor(
        name: "PaymentEntry",
        module: "Accounting",
        syncPolicy: "versionChecked"
    )

    // MARK: - GLEntry

    /// An immutable general-ledger posting row created automatically by submitted transactions.
    ///
    /// Key fields:
    /// - `name` (title field, auto-generated)
    /// - `account`, `postingDate`, `debit`, `credit`, `voucherType`, `voucherNo`, `costCenter`
    ///
    /// Child tables: none
    ///
    /// Sync policy: `appendOnly` (ADR-006 — immutable double-entry ledger; rows are never updated)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let glEntry = HubDocTypeDescriptor(
        name: "GLEntry",
        module: "Accounting",
        syncPolicy: "appendOnly"
    )

    // MARK: - All DocTypes

    /// All Accounting DocType descriptors — will be passed to `AppManifest` when Core is available.
    /// - TODO: Replace `HubDocTypeDescriptor` elements with `DocType` values from MercantisCore.
    public static let allDocTypes: [HubDocTypeDescriptor] = [
        account, fiscalYear, costCenter, journalEntry, paymentEntry, glEntry,
    ]
}
