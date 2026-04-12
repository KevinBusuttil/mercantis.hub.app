// mercantis hub
// Created by Kevin Busuttil on 12/04/2026.

import Foundation

// Uses Core's ReportDefinition, ReportFilter — imported from MercantisCore when dependency is wired up.

/// Stub namespace for all Hub report definitions.
///
/// Reports are declarative `ReportDefinition` values (ADR-004) that specify the
/// data source, filters, columns, and groupings. Core's reporting engine executes them;
/// Hub only provides the configuration.
///
/// - ADR-004: Reports are declarative manifest data.
/// - ADR-008: No dynamic code loading; all report configurations are statically declared.
public enum HubReports: Sendable {

    // MARK: - Sales Register

    /// A tabular listing of all Sales Invoices for a given period.
    ///
    /// Key filters: date range, customer, territory, item
    /// Key columns: invoice no, date, customer, grand total, outstanding, status
    ///
    /// - TODO: Implement using `ReportDefinition` + `ReportFilter` from MercantisCore.
    public static var salesRegister: Never {
        fatalError("salesRegister is a stub — implement with Core's ReportDefinition.")
    }

    // MARK: - Purchase Register

    /// A tabular listing of all Purchase Invoices for a given period.
    ///
    /// Key filters: date range, supplier, item
    /// Key columns: invoice no, date, supplier, grand total, outstanding, status
    ///
    /// - TODO: Implement using `ReportDefinition` + `ReportFilter` from MercantisCore.
    public static var purchaseRegister: Never {
        fatalError("purchaseRegister is a stub — implement with Core's ReportDefinition.")
    }

    // MARK: - Stock Balance

    /// Current on-hand stock balance per item and warehouse.
    ///
    /// Key filters: item, item group, warehouse, date
    /// Key columns: item code, item name, warehouse, opening qty, in qty, out qty, balance qty, valuation rate, balance value
    ///
    /// - TODO: Implement using `ReportDefinition` + `ReportFilter` from MercantisCore.
    public static var stockBalance: Never {
        fatalError("stockBalance is a stub — implement with Core's ReportDefinition.")
    }

    // MARK: - Trial Balance

    /// The double-entry trial balance for a given fiscal period.
    ///
    /// Key filters: fiscal year, from/to date, cost centre, finance book
    /// Key columns: account, opening debit/credit, period debit/credit, closing debit/credit
    ///
    /// - TODO: Implement using `ReportDefinition` + `ReportFilter` from MercantisCore.
    public static var trialBalance: Never {
        fatalError("trialBalance is a stub — implement with Core's ReportDefinition.")
    }

    // MARK: - Profit & Loss

    /// Income statement showing revenue, cost of goods sold, and operating expenses.
    ///
    /// Key filters: fiscal year, from/to date, cost centre, finance book
    /// Key columns: account, amount (current period), amount (previous period), % change
    ///
    /// - TODO: Implement using `ReportDefinition` + `ReportFilter` from MercantisCore.
    public static var profitAndLoss: Never {
        fatalError("profitAndLoss is a stub — implement with Core's ReportDefinition.")
    }

    // MARK: - Accounts Receivable

    /// Ageing of outstanding customer receivables.
    ///
    /// Key filters: date, customer, payment terms
    /// Key columns: customer, invoice no, due date, invoiced amount, paid amount, outstanding, ageing bucket
    ///
    /// - TODO: Implement using `ReportDefinition` + `ReportFilter` from MercantisCore.
    public static var accountsReceivable: Never {
        fatalError("accountsReceivable is a stub — implement with Core's ReportDefinition.")
    }

    // MARK: - Accounts Payable

    /// Ageing of outstanding supplier payables.
    ///
    /// Key filters: date, supplier, payment terms
    /// Key columns: supplier, invoice no, due date, invoiced amount, paid amount, outstanding, ageing bucket
    ///
    /// - TODO: Implement using `ReportDefinition` + `ReportFilter` from MercantisCore.
    public static var accountsPayable: Never {
        fatalError("accountsPayable is a stub — implement with Core's ReportDefinition.")
    }

    // MARK: - All Reports

    /// All report definitions — will be wired into `HubManifest.build()`.
    /// - TODO: Replace with an array of `ReportDefinition` values from MercantisCore.
    public static let allReports: [Any] = []
}
