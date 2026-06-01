import MercantisCore

struct HubWorkspaceCopy {
    let title: String
    let subtitle: String
    let primaryActionTitle: String
    let emptyStateTitle: String
    let emptyStateMessage: String
    let emptyStateHint: String?
}

enum HubWorkspaceCopyPolicy {
    private static let mappedCopy: [String: HubWorkspaceCopy] = [
        "Company": .init(
            title: "Business Profile",
            subtitle: "Store your business identity and operational defaults in one place.",
            primaryActionTitle: "Set Up Business Profile",
            emptyStateTitle: "No business profile yet",
            emptyStateMessage: "Create your business profile to save company identity, default currency, warehouse, and account selections.",
            emptyStateHint: "Tip: keep one profile updated so future setup can reuse consistent defaults."
        ),
        "FiscalYear": .init(
            title: "Fiscal Years",
            subtitle: "Define accounting periods for financial reporting and period close.",
            primaryActionTitle: "New Fiscal Year",
            emptyStateTitle: "No fiscal year yet",
            emptyStateMessage: "Create your first fiscal year to define when your accounting period starts and ends.",
            emptyStateHint: "Tip: most businesses use January–December or align with their tax reporting period."
        ),
        "NumberingSeries": .init(
            title: "Numbering Series",
            subtitle: "Configure automatic numbering for invoices, bills, deliveries, and payments.",
            primaryActionTitle: "Set Up Numbering Series",
            emptyStateTitle: "No numbering configured",
            emptyStateMessage: "Set up numbering patterns so each document gets a unique, sequential reference automatically.",
            emptyStateHint: "Tip: use .YYYY. for year and .#### for a four-digit sequence number."
        ),
        "Supplier": .init(
            title: "Suppliers",
            subtitle: "Manage supplier profiles, purchasing defaults, and payment details.",
            primaryActionTitle: "New Supplier",
            emptyStateTitle: "No suppliers yet",
            emptyStateMessage: "Create your first supplier to start recording purchases and supplier bills.",
            emptyStateHint: "Tip: add payment terms and default accounts to speed up bill entry."
        ),
        "Customer": .init(
            title: "Customers",
            subtitle: "Manage customer profiles, contacts, billing details, and sales defaults.",
            primaryActionTitle: "New Customer",
            emptyStateTitle: "No customers yet",
            emptyStateMessage: "Create your first customer to start issuing quotes, orders, and invoices.",
            emptyStateHint: "Tip: add billing contacts to streamline invoicing."
        ),
        "Item": .init(
            title: "Items",
            subtitle: "Manage products, services, units, pricing, and stock behaviour.",
            primaryActionTitle: "New Item",
            emptyStateTitle: "No items yet",
            emptyStateMessage: "Create your first item to start pricing, stock movements, and transactions.",
            emptyStateHint: "Tip: configure UOM and default warehouse behaviour before trading."
        ),
        "StockEntry": .init(
            title: "Stock Movements",
            subtitle: "Record stock receipts, issues, transfers, and adjustments.",
            primaryActionTitle: "New Stock Movement",
            emptyStateTitle: "No stock movements yet",
            emptyStateMessage: "Create your first stock movement to keep warehouse balances accurate.",
            emptyStateHint: "Tip: choose the movement purpose before adding lines."
        ),
        "Quotation": .init(
            title: "Quotes",
            subtitle: "Track customer quotations and move accepted offers into sales orders.",
            primaryActionTitle: "New Quote",
            emptyStateTitle: "No quotes yet",
            emptyStateMessage: "Create your first quote to begin your sales pipeline.",
            emptyStateHint: nil
        ),
        "SalesOrder": .init(
            title: "Sales Orders",
            subtitle: "Manage confirmed customer orders from acceptance to fulfillment.",
            primaryActionTitle: "New Sales Order",
            emptyStateTitle: "No sales orders yet",
            emptyStateMessage: "Create your first sales order to track committed demand.",
            emptyStateHint: nil
        ),
        "SalesInvoice": .init(
            title: "Sales Invoices",
            subtitle: "Issue invoices, track receivables, and monitor collection status.",
            primaryActionTitle: "New Sales Invoice",
            emptyStateTitle: "No sales invoices yet",
            emptyStateMessage: "Create your first sales invoice to record revenue and customer balances.",
            emptyStateHint: nil
        ),
        "PurchaseOrder": .init(
            title: "Purchase Orders",
            subtitle: "Track supplier purchase commitments and expected receipts.",
            primaryActionTitle: "New Purchase Order",
            emptyStateTitle: "No purchase orders yet",
            emptyStateMessage: "Create your first purchase order to plan incoming stock and spend.",
            emptyStateHint: nil
        ),
        "PurchaseInvoice": .init(
            title: "Bills",
            subtitle: "Record supplier bills and monitor payable balances.",
            primaryActionTitle: "New Bill",
            emptyStateTitle: "No bills yet",
            emptyStateMessage: "Create your first bill to track payables and due dates.",
            emptyStateHint: nil
        ),
        "PaymentEntry": .init(
            title: "Payments",
            subtitle: "Record incoming and outgoing payments against customers and suppliers.",
            primaryActionTitle: "New Payment",
            emptyStateTitle: "No payments yet",
            emptyStateMessage: "Create your first payment to keep customer and supplier balances current.",
            emptyStateHint: nil
        )
    ]

    static func copy(for docType: DocType) -> HubWorkspaceCopy {
        if let mapped = mappedCopy[docType.id] {
            return mapped
        }

        let title = pluralizedTitle(for: docType.name)
        let noun = docType.name.lowercased()
        return HubWorkspaceCopy(
            title: title,
            subtitle: "Manage \(noun) records.",
            primaryActionTitle: "New \(docType.name)",
            emptyStateTitle: "No \(title.lowercased()) yet",
            emptyStateMessage: "Create your first \(noun) to get started.",
            emptyStateHint: nil
        )
    }

    private static func pluralizedTitle(for name: String) -> String {
        let lower = name.lowercased()
        if lower.hasSuffix("s") || lower.hasSuffix("ch") || lower.hasSuffix("sh") || lower.hasSuffix("x") {
            return "\(name)es"
        }
        if lower.hasSuffix("y"),
           let last = name.dropLast().last,
           !"aeiou".contains(last.lowercased()) {
            return "\(name.dropLast())ies"
        }
        return "\(name)s"
    }
}
