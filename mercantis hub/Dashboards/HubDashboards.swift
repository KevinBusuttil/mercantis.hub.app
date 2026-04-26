// mercantis hub
// Created by Kevin Busuttil on 12/04/2026.

import Foundation

// Uses Core's DashboardDefinition, DashboardWidget — imported from MercantisCore when dependency is wired up.

/// Stub namespace for all Hub dashboard definitions.
///
/// Dashboards are declarative `DashboardDefinition` values (ADR-004) composed of
/// `DashboardWidget` descriptors. Core renders dashboards; Hub only provides the data.
///
/// - ADR-004: Dashboards are declarative manifest data.
/// - ADR-008: No dynamic code loading; all widget configurations are statically declared.
public enum HubDashboards: Sendable {

    // MARK: - Sales Overview

    /// A high-level sales performance dashboard.
    ///
    /// Proposed widgets:
    /// - Total Sales (current period) — number card
    /// - Sales by Customer — bar chart
    /// - Outstanding Receivables — number card
    /// - Sales Order Status — donut chart
    ///
    /// - TODO: Implement using `DashboardDefinition` + `DashboardWidget` from MercantisCore.
    public static var salesOverview: Never {
        fatalError("salesOverview is a stub — implement with Core's DashboardDefinition.")
    }

    // MARK: - Inventory Summary

    /// A snapshot of current stock levels and movements.
    ///
    /// Proposed widgets:
    /// - Stock Value — number card
    /// - Items Below Re-order Level — list
    /// - Stock Entries (last 30 days) — line chart
    /// - Warehouse-wise Stock — bar chart
    ///
    /// - TODO: Implement using `DashboardDefinition` + `DashboardWidget` from MercantisCore.
    public static var inventorySummary: Never {
        fatalError("inventorySummary is a stub — implement with Core's DashboardDefinition.")
    }

    // MARK: - Accounting Summary

    /// A financial health overview for the current fiscal period.
    ///
    /// Proposed widgets:
    /// - Profit & Loss (current period) — number card
    /// - Accounts Receivable vs Payable — bar chart
    /// - Cash Flow — line chart
    /// - Expense Breakdown — donut chart
    ///
    /// - TODO: Implement using `DashboardDefinition` + `DashboardWidget` from MercantisCore.
    public static var accountingSummary: Never {
        fatalError("accountingSummary is a stub — implement with Core's DashboardDefinition.")
    }

    // MARK: - HR Overview

    /// An HR operations snapshot.
    ///
    /// Proposed widgets:
    /// - Headcount — number card
    /// - Leave Requests Pending Approval — list
    /// - Attendance Rate (current month) — gauge
    /// - Expense Claims Pending — number card
    ///
    /// - TODO: Implement using `DashboardDefinition` + `DashboardWidget` from MercantisCore.
    public static var hrOverview: Never {
        fatalError("hrOverview is a stub — implement with Core's DashboardDefinition.")
    }

    // MARK: - All Dashboards

    /// All dashboard definitions — will be wired into `HubManifest.build()`.
    /// - TODO: Replace with an array of `DashboardDefinition` values from MercantisCore.
    public static let allDashboards: [Any] = []
}
