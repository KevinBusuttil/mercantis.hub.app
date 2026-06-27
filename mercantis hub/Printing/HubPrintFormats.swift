import Foundation
import MercantisCore

/// Hub's print-format catalogue (ADR-044). Every DocType gets an auto-generated
/// "Standard" format derived from its form layout / fields, so nothing is left
/// unprintable; the key sales / purchase documents additionally get a curated,
/// nicely-laid-out format which is their default. Exactly one format per
/// DocType is flagged `isDefault`.
///
/// Registered with the app's `PrintService` at startup; the document header's
/// Print button lists a DocType's formats (default first) and renders the
/// chosen one to PDF.
enum HubPrintFormats {

    /// Every format to register: a Standard per DocType + the curated set.
    static func all() -> [PrintFormat] {
        let curatedFormats = curated()
        let curatedDocTypes = Set(curatedFormats.map(\.docType))
        var formats: [PrintFormat] = []
        for docType in HubManifest.allDocTypes where !docType.isChildTable {
            // Standard is the default only when no curated format claims it.
            formats.append(standardFormat(for: docType, isDefault: !curatedDocTypes.contains(docType.id)))
        }
        return formats + curatedFormats
    }

    // MARK: - Standard (auto-generated)

    /// A "Standard" format built from a DocType's form layout (falling back to
    /// its raw field order): a heading, the document id, each section's scalar
    /// fields as a label/value grid, and every child table as a grid.
    static func standardFormat(for docType: DocType, isDefault: Bool) -> PrintFormat {
        var sections: [PrintSection] = [
            .heading(text: docType.name),
            .keyValue(label: "Document", value: "{id}"),
        ]

        func isPrintable(_ field: FieldDefinition) -> Bool {
            switch field.type {
            case .table, .image, .attachment: return false
            default: return true
            }
        }

        if let layout = docType.formLayout, !layout.sections.isEmpty {
            for section in layout.sections {
                let scalarKeys = section.fieldKeys.filter { key in
                    docType.fields.first { $0.key == key }.map(isPrintable) ?? false
                }
                if !scalarKeys.isEmpty {
                    sections.append(.fields(keys: scalarKeys, labels: labels(for: scalarKeys, in: docType)))
                }
                for key in section.fieldKeys {
                    if let field = docType.fields.first(where: { $0.key == key }), field.type == .table {
                        sections.append(tableSection(for: field))
                    }
                }
            }
        } else {
            let scalarKeys = docType.fields.filter(isPrintable).map(\.key)
            if !scalarKeys.isEmpty {
                sections.append(.fields(keys: scalarKeys, labels: labels(for: scalarKeys, in: docType)))
            }
            for field in docType.fields where field.type == .table {
                sections.append(tableSection(for: field))
            }
        }

        return PrintFormat(
            id: "std-\(docType.id)", name: "Standard", docType: docType.id,
            isDefault: isDefault,
            // The comprehensive format shows code + name for links (UUID keys
            // fall back to name only).
            linkDisplay: .codeAndName,
            sections: sections
        )
    }

    /// A child-table grid whose columns come from the child DocType's scalar
    /// fields (empty columns would make the renderer fall back to "every key").
    private static func tableSection(for field: FieldDefinition) -> PrintSection {
        let child = field.childDocType.flatMap { HubManifest.docType(for: $0) }
        let columns = (child?.fields ?? [])
            .filter { $0.type != .table && $0.type != .image && $0.type != .attachment }
            .map(\.key)
        let columnLabels = child.map { labels(for: columns, in: $0) } ?? [:]
        return .table(tableKey: field.key, columns: columns, labels: columnLabels)
    }

    private static func labels(for keys: [String], in docType: DocType) -> [String: String] {
        var map: [String: String] = [:]
        for key in keys {
            if let field = docType.fields.first(where: { $0.key == key }) {
                map[key] = field.label
            }
        }
        return map
    }

    // MARK: - Curated (key sales / purchase documents)

    private static func curated() -> [PrintFormat] {
        [
            transactionFormat(id: "quotation", name: "Quotation", docType: "Quotation",
                              title: "Quotation", partyKey: "customer", partyLabel: "Customer"),
            transactionFormat(id: "sales-order", name: "Sales Order", docType: "SalesOrder",
                              title: "Sales Order", partyKey: "customer", partyLabel: "Customer"),
            transactionFormat(id: "tax-invoice", name: "Tax Invoice", docType: "SalesInvoice",
                              title: "Tax Invoice", partyKey: "customer", partyLabel: "Customer",
                              showTaxBreakdown: true),
            transactionFormat(id: "purchase-order", name: "Purchase Order", docType: "PurchaseOrder",
                              title: "Purchase Order", partyKey: "supplier", partyLabel: "Supplier"),
            transactionFormat(id: "purchase-invoice", name: "Purchase Invoice", docType: "PurchaseInvoice",
                              title: "Purchase Invoice", partyKey: "supplier", partyLabel: "Supplier",
                              showTaxBreakdown: true),
            deliveryFormat(id: "delivery-note", name: "Delivery Note", docType: "SalesDelivery",
                           title: "Delivery Note", partyKey: "customer", partyLabel: "Customer"),
            deliveryFormat(id: "goods-receipt", name: "Goods Received Note", docType: "PurchaseReceipt",
                           title: "Goods Received Note", partyKey: "supplier", partyLabel: "Supplier"),
            paymentReceiptFormat(),
        ]
    }

    /// A goods-movement document (Delivery Note / Goods Received Note): party +
    /// date, an item table with quantities and source warehouse, and a total
    /// quantity — no prices or totals.
    private static func deliveryFormat(
        id: String, name: String, docType: String, title: String,
        partyKey: String, partyLabel: String
    ) -> PrintFormat {
        PrintFormat(
            id: "fmt-\(id)", name: name, docType: docType, isDefault: true,
            linkDisplay: .name,
            fieldLinkDisplays: [partyKey: .codeAndName, "item": .codeAndName],
            sections: [
                .heading(text: title),
                .keyValue(label: "Document", value: "{id}"),
                .fields(keys: [partyKey, "transaction_date"],
                        labels: [partyKey: partyLabel, "transaction_date": "Date"]),
                .table(
                    tableKey: "items",
                    columns: ["item", "description", "qty", "uom", "warehouse"],
                    labels: ["item": "Item", "description": "Description", "qty": "Qty",
                             "uom": "UOM", "warehouse": "Warehouse"]
                ),
                .keyValue(label: "Total Qty", value: "{total_qty}"),
            ]
        )
    }

    /// A payment voucher / receipt: party + reference + the amounts.
    private static func paymentReceiptFormat() -> PrintFormat {
        PrintFormat(
            id: "fmt-payment-receipt", name: "Payment Receipt", docType: "PaymentEntry", isDefault: true,
            linkDisplay: .name,
            sections: [
                .heading(text: "Payment Receipt"),
                .keyValue(label: "Document", value: "{id}"),
                .fields(
                    keys: ["payment_type", "party", "posting_date", "reference_no"],
                    labels: ["payment_type": "Type", "party": "Party",
                             "posting_date": "Date", "reference_no": "Reference"]
                ),
                .keyValue(label: "Paid Amount", value: "{paid_amount}"),
                .keyValue(label: "Received Amount", value: "{received_amount}"),
            ]
        )
    }

    /// A clean header → party/date → items → totals layout shared by the
    /// sales / purchase documents.
    private static func transactionFormat(
        id: String, name: String, docType: String, title: String,
        partyKey: String, partyLabel: String, showTaxBreakdown: Bool = false
    ) -> PrintFormat {
        var sections: [PrintSection] = [
            .heading(text: title),
            .keyValue(label: "Document", value: "{id}"),
            .fields(
                keys: [partyKey, "transaction_date", "currency"],
                labels: [partyKey: partyLabel, "transaction_date": "Date", "currency": "Currency"]
            ),
            .table(
                tableKey: "items",
                columns: ["item", "description", "qty", "uom", "rate", "amount"],
                labels: [
                    "item": "Item", "description": "Description", "qty": "Qty",
                    "uom": "UOM", "rate": "Rate", "amount": "Amount",
                ]
            ),
            .keyValue(label: "Total Qty", value: "{total_qty}"),
        ]
        if showTaxBreakdown {
            sections.append(.keyValue(label: "Net Total", value: "{net_total}"))
            sections.append(.keyValue(label: "Total Taxes", value: "{total_taxes}"))
        }
        sections.append(.keyValue(label: "Grand Total", value: "{grand_total}"))

        // A customer/supplier-facing document: names by default, but the party
        // and item carry their code as well (e.g. "ITEM-0003 — Sunflower Oil").
        return PrintFormat(
            id: "fmt-\(id)", name: name, docType: docType, isDefault: true,
            linkDisplay: .name,
            fieldLinkDisplays: [partyKey: .codeAndName, "item": .codeAndName],
            sections: sections
        )
    }
}
