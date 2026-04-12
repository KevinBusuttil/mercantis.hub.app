// mercantis hub
// Created by Kevin Busuttil on 12/04/2026.

import Foundation

// Uses Core's AutomationRule, AutomationAction — imported from MercantisCore when dependency is wired up.

/// Stub namespace for all Hub automation rules.
///
/// Hub automation rules are declarative `AutomationRule` values (ADR-004) that describe
/// trigger-action pairs evaluated by Core's automation engine. Hub provides no custom
/// runtime code — it only supplies the rule data.
///
/// - ADR-004: Automation rules are declarative manifest data.
/// - ADR-008: No dynamic code loading; all actions are declared as data.
public enum HubAutomation: Sendable {

    // MARK: - GL Entry Creation on Invoice Submit

    /// Automatically creates GL entries when a Sales Invoice or Purchase Invoice is submitted.
    ///
    /// Trigger: `onSubmit` on `SalesInvoice` / `PurchaseInvoice`
    /// Action: Create corresponding `GLEntry` rows via Core's accounting engine.
    ///
    /// - TODO: Implement using `AutomationRule` from MercantisCore.
    public static var createGLEntriesOnInvoiceSubmit: Never {
        fatalError("createGLEntriesOnInvoiceSubmit is a stub — implement with Core's AutomationRule.")
    }

    // MARK: - Large Order Manager Notification

    /// Notifies the Sales Manager when a Sales Order exceeds a configured threshold amount.
    ///
    /// Trigger: `onSubmit` on `SalesOrder` where `grandTotal` > threshold
    /// Action: Send an in-app notification to users with the Sales Manager role.
    ///
    /// - TODO: Implement using `AutomationRule` from MercantisCore.
    public static var notifyManagerOnLargeOrder: Never {
        fatalError("notifyManagerOnLargeOrder is a stub — implement with Core's AutomationRule.")
    }

    // MARK: - Stock Ledger Entry on Stock Entry Submit

    /// Appends `StockLedgerEntry` rows when a `StockEntry` is submitted.
    ///
    /// Trigger: `onSubmit` on `StockEntry`
    /// Action: Create immutable `StockLedgerEntry` rows for each detail line.
    ///
    /// - TODO: Implement using `AutomationRule` from MercantisCore.
    public static var createStockLedgerOnStockEntrySubmit: Never {
        fatalError("createStockLedgerOnStockEntrySubmit is a stub — implement with Core's AutomationRule.")
    }

    // MARK: - Payroll GL Entries

    /// Creates GL entries when a Payroll run is submitted.
    ///
    /// Trigger: `onSubmit` on `Payroll`
    /// Action: Create `GLEntry` rows for salary payable and expense accounts.
    ///
    /// - TODO: Implement using `AutomationRule` from MercantisCore.
    public static var createGLEntriesOnPayrollSubmit: Never {
        fatalError("createGLEntriesOnPayrollSubmit is a stub — implement with Core's AutomationRule.")
    }

    // MARK: - All Rules

    /// All automation rules — will be wired into `HubManifest.build()`.
    /// - TODO: Replace with an array of `AutomationRule` values from MercantisCore.
    public static let allRules: [Any] = []
}
