import Foundation
import MercantisCore

/// The DocTypes a user is allowed to build a brand-new report on.
///
/// Mirrors `HubCustomReportCatalog` (which gates *report customisation*) but
/// for *from-scratch* reports: Hub decides which record types are safe to
/// expose, with friendly labels, and gates the raw ledger/audit spine behind
/// the Advanced/Accountant view so a normal user never reports on it by
/// accident.
enum HubReportableDocTypes {

    struct Entry: Identifiable, Equatable {
        let docType: String
        let label: String
        let visibility: HubVisibility

        var id: String { docType }
    }

    /// Safe, user-facing record types first; raw ledger/audit tables are
    /// `.advanced`. Only entries whose DocType is actually registered in the
    /// running manifest are offered (see `available(_:)`).
    static let all: [Entry] = [
        // Masters / CRM
        .init(docType: "Customer", label: "Customers", visibility: .normal),
        .init(docType: "Supplier", label: "Suppliers", visibility: .normal),
        .init(docType: "Item", label: "Items", visibility: .normal),
        .init(docType: "Contact", label: "Contacts", visibility: .normal),
        .init(docType: "Lead", label: "Leads", visibility: .normal),
        // Sales
        .init(docType: "Quotation", label: "Quotes", visibility: .normal),
        .init(docType: "SalesOrder", label: "Sales Orders", visibility: .normal),
        .init(docType: "SalesInvoice", label: "Sales Invoices", visibility: .normal),
        // Buying
        .init(docType: "PurchaseOrder", label: "Purchase Orders", visibility: .normal),
        .init(docType: "PurchaseInvoice", label: "Purchase Invoices", visibility: .normal),
        // Money / setup
        .init(docType: "PaymentEntry", label: "Payments", visibility: .normal),
        .init(docType: "Account", label: "Accounts", visibility: .normal),
        .init(docType: "Warehouse", label: "Warehouses", visibility: .normal),
        .init(docType: "PriceList", label: "Price Lists", visibility: .normal),
        // Advanced: the AX-style audit/ledger spine — only when advanced is on.
        .init(docType: "GLEntry", label: "GL Entries", visibility: .advanced),
        .init(docType: "CustTrans", label: "Customer Transactions", visibility: .advanced),
        .init(docType: "VendTrans", label: "Supplier Transactions", visibility: .advanced),
        .init(docType: "TaxTrans", label: "Tax Transactions", visibility: .advanced),
        .init(docType: "StockLedgerEntry", label: "Stock Ledger Entries", visibility: .advanced),
        .init(docType: "JournalEntry", label: "Journal Entries", visibility: .advanced),
        .init(docType: "Settlement", label: "Settlements", visibility: .advanced),
    ]

    /// Entries the user may currently start a report from: visible under the
    /// advanced/normal preference *and* registered in the manifest.
    static func available(_ settings: HubVisibilitySettings) -> [Entry] {
        all.filter { settings.isVisible($0.visibility) && HubManifest.docType(for: $0.docType) != nil }
    }

    static func entry(for docType: String) -> Entry? {
        all.first { $0.docType == docType }
    }

    /// Whether the given DocType can be reported on under the current
    /// preference (used to gate the audit spine).
    static func isReportable(_ docType: String, settings: HubVisibilitySettings) -> Bool {
        guard let entry = entry(for: docType) else { return false }
        return settings.isVisible(entry.visibility)
    }
}
