import Foundation
import MercantisCore

/// Hub-side dashboard definitions consumed by Core's `DashboardEngine`
/// (Phase C / ADR-045). Each dashboard is a list of `DashboardWidget`
/// descriptors; `DashboardEngine.resolve(dashboardId:)` returns a typed
/// `DashboardResult` that the UI layer renders.
///
/// Widget parameter syntax (ADR-045):
/// - `status=Open` → equality predicate (shorthand)
/// - `where.<field>__<op>=<value>` → typed operator predicate
/// - `columns=a,b,c` + `limit=N` → list widget configuration
/// - `target=...` → shortcut destination
public enum HubDashboards: Sendable {

    // MARK: - Sales Overview

    public static let salesOverview = DashboardDefinition(
        id: "sales-overview",
        name: "Sales Overview",
        widgets: [
            DashboardWidget(
                type: "count", title: "Customers",
                docType: "Customer", parameters: [:]
            ),
            DashboardWidget(
                type: "count", title: "Submitted Sales Orders",
                docType: "SalesOrder",
                parameters: ["where.docStatus__eq": "1"]
            ),
            DashboardWidget(
                type: "count", title: "Outstanding Sales Invoices",
                docType: "SalesInvoice",
                parameters: ["where.outstanding_amount__gt": "0"]
            ),
            DashboardWidget(
                type: "list", title: "Recent Quotations",
                docType: "Quotation",
                parameters: ["columns": "id,customer,grand_total,status",
                             "limit": "5"]
            ),
            DashboardWidget(
                type: "shortcut", title: "All Customers",
                docType: "Customer",
                parameters: ["target": "doctype:Customer"]
            ),
            DashboardWidget(
                type: "shortcut", title: "Sales Register",
                parameters: ["target": "report:sales-register"]
            ),
        ]
    )

    // MARK: - Inventory Overview

    public static let inventoryOverview = DashboardDefinition(
        id: "inventory-overview",
        name: "Inventory Overview",
        widgets: [
            DashboardWidget(
                type: "count", title: "Items",
                docType: "Item", parameters: [:]
            ),
            DashboardWidget(
                type: "count", title: "Warehouses",
                docType: "Warehouse", parameters: [:]
            ),
            DashboardWidget(
                type: "count", title: "Submitted Stock Entries",
                docType: "StockEntry",
                parameters: ["where.docStatus__eq": "1"]
            ),
            DashboardWidget(
                type: "list", title: "Recent Stock Movements",
                docType: "StockLedgerEntry",
                parameters: ["columns": "voucher_no,item,warehouse,qty_change",
                             "limit": "10"]
            ),
            DashboardWidget(
                type: "shortcut", title: "Stock Ledger View",
                parameters: ["target": "report:stock-ledger-view"]
            ),
            DashboardWidget(
                type: "shortcut", title: "New Stock Entry",
                docType: "StockEntry",
                parameters: ["target": "doctype:StockEntry"]
            ),
        ]
    )

    // MARK: - Accounting Overview

    public static let accountingOverview = DashboardDefinition(
        id: "accounting-overview",
        name: "Accounting Overview",
        widgets: [
            DashboardWidget(
                type: "count", title: "Accounts",
                docType: "Account",
                parameters: ["where.disabled__neq": "true"]
            ),
            DashboardWidget(
                type: "count", title: "Submitted Journal Entries",
                docType: "JournalEntry",
                parameters: ["where.docStatus__eq": "1"]
            ),
            DashboardWidget(
                type: "count", title: "Submitted Payment Entries",
                docType: "PaymentEntry",
                parameters: ["where.docStatus__eq": "1"]
            ),
            DashboardWidget(
                type: "list", title: "Recent GL Entries",
                docType: "GLEntry",
                parameters: ["columns": "voucher_no,account,debit,credit",
                             "limit": "10"]
            ),
            DashboardWidget(
                type: "shortcut", title: "Trial Balance",
                parameters: ["target": "report:trial-balance"]
            ),
            DashboardWidget(
                type: "shortcut", title: "Customer Aging",
                parameters: ["target": "report:customer-aging"]
            ),
        ]
    )

    // MARK: - Manufacturing Overview

    public static let manufacturingOverview = DashboardDefinition(
        id: "manufacturing-overview",
        name: "Manufacturing Overview",
        widgets: [
            DashboardWidget(
                type: "count", title: "Active BOMs",
                docType: "BOM",
                parameters: ["where.docStatus__eq": "1"]
            ),
            DashboardWidget(
                type: "count", title: "Open Work Orders",
                docType: "WorkOrder",
                parameters: ["where.status__neq": "Completed"]
            ),
            DashboardWidget(
                type: "count", title: "Production Plans",
                docType: "ProductionPlan",
                parameters: ["where.docStatus__eq": "1"]
            ),
            DashboardWidget(
                type: "list", title: "Recent Work Orders",
                docType: "WorkOrder",
                parameters: ["columns": "id,item,qty_to_produce,status",
                             "limit": "10"]
            ),
            DashboardWidget(
                type: "shortcut", title: "New Work Order",
                docType: "WorkOrder",
                parameters: ["target": "doctype:WorkOrder"]
            ),
            DashboardWidget(
                type: "shortcut", title: "New Production Plan",
                docType: "ProductionPlan",
                parameters: ["target": "doctype:ProductionPlan"]
            ),
        ]
    )

    public static let allDashboards: [DashboardDefinition] = [
        salesOverview,
        inventoryOverview,
        manufacturingOverview,
        accountingOverview,
    ]

    public static func dashboard(forId id: String) -> DashboardDefinition? {
        allDashboards.first { $0.id == id }
    }
}
