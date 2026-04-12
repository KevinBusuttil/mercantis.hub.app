// mercantis hub
// Created by Kevin Busuttil on 12/04/2026.

import Foundation

// Uses Core's PermissionRule — imported from MercantisCore when dependency is wired up.

/// Stub namespace for Hub's default role-based permission templates.
///
/// Permission rules are declarative `PermissionRule` values (ADR-004) that specify
/// which roles can read, write, submit, cancel, or delete each DocType.
/// Core's `PermissionEngine` enforces them at runtime; Hub only provides the data.
///
/// - ADR-004: Permissions are declarative manifest data.
/// - ADR-008: No dynamic code loading; permission rules are statically declared.
public enum HubPermissions: Sendable {

    // MARK: - System Manager

    /// Full access to all DocTypes and settings.
    ///
    /// - TODO: Implement using `PermissionRule` values from MercantisCore.
    public static var systemManager: Never {
        fatalError("systemManager is a stub — implement with Core's PermissionRule.")
    }

    // MARK: - Sales Manager

    /// Full access to CRM and Sales module DocTypes; read access to Inventory.
    ///
    /// DocTypes in scope: Customer, Contact, Address, Lead, Opportunity,
    ///                    Quotation, SalesOrder, DeliveryNote, SalesInvoice, PricingRule
    ///
    /// - TODO: Implement using `PermissionRule` values from MercantisCore.
    public static var salesManager: Never {
        fatalError("salesManager is a stub — implement with Core's PermissionRule.")
    }

    // MARK: - Accountant

    /// Full access to Accounting module DocTypes; read access to Sales and Buying invoices.
    ///
    /// DocTypes in scope: Account, JournalEntry, GLEntry, PaymentEntry, FiscalYear, CostCenter,
    ///                    SalesInvoice (read), PurchaseInvoice (read)
    ///
    /// - TODO: Implement using `PermissionRule` values from MercantisCore.
    public static var accountant: Never {
        fatalError("accountant is a stub — implement with Core's PermissionRule.")
    }

    // MARK: - Stock User

    /// Full access to Inventory module DocTypes; read access to Items.
    ///
    /// DocTypes in scope: Item, ItemGroup, Warehouse, StockEntry, StockLedgerEntry
    ///
    /// - TODO: Implement using `PermissionRule` values from MercantisCore.
    public static var stockUser: Never {
        fatalError("stockUser is a stub — implement with Core's PermissionRule.")
    }

    // MARK: - HR Manager

    /// Full access to HR module DocTypes.
    ///
    /// DocTypes in scope: Employee, LeaveApplication, Attendance, ExpenseClaim, Payroll
    ///
    /// - TODO: Implement using `PermissionRule` values from MercantisCore.
    public static var hrManager: Never {
        fatalError("hrManager is a stub — implement with Core's PermissionRule.")
    }

    // MARK: - Purchase Manager

    /// Full access to Buying module DocTypes; read access to Inventory.
    ///
    /// DocTypes in scope: Supplier, PurchaseOrder, PurchaseReceipt, PurchaseInvoice
    ///
    /// - TODO: Implement using `PermissionRule` values from MercantisCore.
    public static var purchaseManager: Never {
        fatalError("purchaseManager is a stub — implement with Core's PermissionRule.")
    }

    // MARK: - All Roles

    /// All permission role definitions — will be wired into `HubManifest.build()`.
    /// - TODO: Replace with an array of `PermissionRule` values from MercantisCore.
    public static let allRoles: [Any] = []
}
