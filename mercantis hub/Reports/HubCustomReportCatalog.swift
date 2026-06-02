import Foundation
import MercantisCore

/// Hub's curated catalogue of which built-in reports a user is allowed to
/// customise, with friendly ERP labels for every column and filter.
///
/// This is the Hub-side half of the saved-report epic: Core owns the generic
/// `SavedReportDefinition` model and execution rules; Hub decides *which*
/// reports are safe to expose, what their columns/filters should be called in
/// plain language, and whether a report needs the Advanced/Accountant view.
///
/// Only safe, user-facing reports live here. Raw audit/ledger reports
/// (Trial Balance, GL Entry dumps, Customer Statement) are deliberately
/// omitted or gated to `.advanced` so a normal user never customises them by
/// accident.
enum HubCustomReportCatalog {

    /// A column the user may show/hide, reorder, or relabel. `key` must match
    /// the corresponding output column produced by `HubReports.runResult`, so
    /// the runner can map a saved column back onto the computed result.
    struct ColumnTemplate: Equatable {
        let key: String
        let label: String
    }

    /// A filter the user may store a default for. `targetDocType`, when set,
    /// lets the editor offer a record picker (e.g. choose a Customer) instead
    /// of a free-text field.
    struct FilterTemplate: Equatable {
        let fieldKey: String
        let label: String
        var targetDocType: String? = nil
    }

    /// One customisable report template.
    struct Template: Identifiable, Equatable {
        /// The built-in `HubReports` report this customises.
        let baseReportId: String
        /// Friendly report name shown to the user.
        let name: String
        /// The source DocType the underlying report queries.
        let sourceDocType: String
        let columns: [ColumnTemplate]
        let filters: [FilterTemplate]
        /// Visibility gate. `.advanced` templates only appear when the
        /// Advanced/Accountant view is enabled.
        let visibility: HubVisibility

        var id: String { baseReportId }
    }

    // MARK: - Catalogue

    /// Every customisable report, safe (normal) ones first. Trial Balance,
    /// Customer Statement, Pending Receipts and the GL/CustTrans/VendTrans
    /// dumps are intentionally absent.
    static let all: [Template] = [
        Template(
            baseReportId: HubReports.salesRegister.id,
            name: "Sales Register",
            sourceDocType: HubReports.salesRegister.docType,
            columns: [
                .init(key: "id", label: "Invoice"),
                .init(key: "transaction_date", label: "Date"),
                .init(key: "customer", label: "Customer"),
                .init(key: "currency", label: "Currency"),
                .init(key: "grand_total", label: "Grand Total"),
                .init(key: "outstanding_amount", label: "Outstanding"),
                .init(key: "status", label: "Status"),
            ],
            filters: [
                .init(fieldKey: "customer", label: "Customer", targetDocType: "Customer"),
                .init(fieldKey: "status", label: "Status"),
            ],
            visibility: .normal
        ),
        Template(
            baseReportId: HubReports.purchaseRegister.id,
            name: "Purchase Register",
            sourceDocType: HubReports.purchaseRegister.docType,
            columns: [
                .init(key: "id", label: "Invoice"),
                .init(key: "transaction_date", label: "Date"),
                .init(key: "supplier", label: "Supplier"),
                .init(key: "currency", label: "Currency"),
                .init(key: "grand_total", label: "Grand Total"),
                .init(key: "outstanding_amount", label: "Outstanding"),
                .init(key: "status", label: "Status"),
            ],
            filters: [
                .init(fieldKey: "supplier", label: "Supplier", targetDocType: "Supplier"),
                .init(fieldKey: "status", label: "Status"),
            ],
            visibility: .normal
        ),
        Template(
            baseReportId: HubReports.stockOnHand.id,
            name: "Stock on Hand",
            sourceDocType: HubReports.stockOnHand.docType,
            columns: [
                .init(key: "Item", label: "Item"),
                .init(key: "Warehouse", label: "Warehouse"),
                .init(key: "Actual Qty", label: "Actual Qty"),
                .init(key: "Valuation Rate", label: "Valuation Rate"),
                .init(key: "Stock Value", label: "Stock Value"),
                .init(key: "Last Movement", label: "Last Movement"),
            ],
            filters: [
                .init(fieldKey: "item", label: "Item", targetDocType: "Item"),
                .init(fieldKey: "warehouse", label: "Warehouse", targetDocType: "Warehouse"),
            ],
            visibility: .normal
        ),
        Template(
            baseReportId: HubReports.customerAging.id,
            name: "Customer Aging",
            sourceDocType: HubReports.customerAging.docType,
            columns: [
                .init(key: "customer", label: "Customer"),
                .init(key: "0-30 days", label: "0–30 days"),
                .init(key: "31-60 days", label: "31–60 days"),
                .init(key: "61-90 days", label: "61–90 days"),
                .init(key: "90+ days", label: "90+ days"),
                .init(key: "Outstanding", label: "Outstanding"),
            ],
            filters: [
                .init(fieldKey: "customer", label: "Customer", targetDocType: "Customer"),
            ],
            visibility: .normal
        ),
        Template(
            baseReportId: HubReports.supplierLedger.id,
            name: "Supplier Ledger",
            sourceDocType: HubReports.supplierLedger.docType,
            columns: [
                .init(key: "posting_date", label: "Date"),
                .init(key: "voucher_no", label: "Voucher"),
                .init(key: "trans_type", label: "Type"),
                .init(key: "amount", label: "Amount"),
                .init(key: "running_balance", label: "Running Balance"),
            ],
            filters: [
                .init(fieldKey: "supplier", label: "Supplier", targetDocType: "Supplier"),
            ],
            visibility: .normal
        ),
        Template(
            baseReportId: HubReports.vatSummary.id,
            name: "VAT Summary",
            sourceDocType: HubReports.vatSummary.docType,
            columns: [
                .init(key: "Tax Code", label: "Tax Code"),
                .init(key: "Rate", label: "Rate"),
                .init(key: "Output Base", label: "Output Base"),
                .init(key: "Output VAT", label: "Output VAT"),
                .init(key: "Input Base", label: "Input Base"),
                .init(key: "Input VAT", label: "Input VAT"),
                .init(key: "Net VAT", label: "Net VAT"),
            ],
            filters: [],
            visibility: .normal
        ),
        Template(
            baseReportId: HubReports.openDeliveries.id,
            name: "Open Deliveries",
            sourceDocType: HubReports.openDeliveries.docType,
            columns: [
                .init(key: "Delivery", label: "Delivery"),
                .init(key: "Customer", label: "Customer"),
                .init(key: "Delivery Date", label: "Delivery Date"),
                .init(key: "Scheduled", label: "Scheduled"),
                .init(key: "Status", label: "Status"),
            ],
            filters: [
                .init(fieldKey: "customer", label: "Customer", targetDocType: "Customer"),
            ],
            visibility: .normal
        ),
        Template(
            baseReportId: HubReports.todaysRoutes.id,
            name: "Today's Routes",
            sourceDocType: HubReports.todaysRoutes.docType,
            columns: [
                .init(key: "Route", label: "Route"),
                .init(key: "Driver", label: "Driver"),
                .init(key: "Vehicle", label: "Vehicle"),
                .init(key: "Status", label: "Status"),
                .init(key: "Stops", label: "Stops"),
                .init(key: "Delivered", label: "Delivered"),
            ],
            filters: [],
            visibility: .normal
        ),
        // Advanced: the raw stock ledger. Customisable only when the
        // Advanced/Accountant view is on, so a normal user never sees it.
        Template(
            baseReportId: HubReports.stockLedgerView.id,
            name: "Stock Ledger View",
            sourceDocType: HubReports.stockLedgerView.docType,
            columns: [
                .init(key: "posting_date", label: "Date"),
                .init(key: "voucher_no", label: "Voucher"),
                .init(key: "item", label: "Item"),
                .init(key: "warehouse", label: "Warehouse"),
                .init(key: "qty_change", label: "Qty Change"),
                .init(key: "valuation_rate", label: "Valuation Rate"),
                .init(key: "amount", label: "Amount"),
                .init(key: "is_reversal", label: "Reversal"),
            ],
            filters: [
                .init(fieldKey: "item", label: "Item", targetDocType: "Item"),
                .init(fieldKey: "warehouse", label: "Warehouse", targetDocType: "Warehouse"),
            ],
            visibility: .advanced
        ),
    ]

    /// Look up a template by the built-in report id it customises.
    static func template(forBaseReportId id: String) -> Template? {
        all.first { $0.baseReportId == id }
    }

    /// Whether a built-in report can be customised under the current
    /// advanced/normal preference.
    static func isCustomisable(reportId: String, settings: HubVisibilitySettings) -> Bool {
        guard let template = template(forBaseReportId: reportId) else { return false }
        return settings.isVisible(template.visibility)
    }

    /// Templates the user may currently start a customisation from, honouring
    /// the advanced-view gate.
    static func availableTemplates(_ settings: HubVisibilitySettings) -> [Template] {
        all.filter { settings.isVisible($0.visibility) }
    }

    // MARK: - Cloning into a Core saved report

    /// Build a fresh `SavedReportDefinition` from a template: every column
    /// visible and in catalogue order with its friendly label, every filter
    /// present with no default yet.
    static func makeSavedReport(
        from template: Template,
        ownerUserId: String,
        name: String? = nil,
        now: Date = Date()
    ) -> SavedReportDefinition {
        let columns = template.columns.enumerated().map { index, column in
            SavedReportColumn(
                fieldKey: column.key,
                labelOverride: column.label,
                visible: true,
                order: index
            )
        }
        let filters = template.filters.map { filter in
            SavedReportFilter(fieldKey: filter.fieldKey, op: .equals)
        }
        return SavedReportDefinition(
            name: name ?? template.name,
            baseReportId: template.baseReportId,
            sourceDocType: template.sourceDocType,
            ownerUserId: ownerUserId,
            visibility: .private,
            columns: columns,
            filters: filters,
            sorts: [],
            createdAt: now,
            updatedAt: now
        )
    }
}
