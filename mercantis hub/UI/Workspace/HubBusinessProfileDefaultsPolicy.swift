import Foundation
import MercantisCore

enum HubBusinessProfileDefaultsPolicy {

    static func applyDraftDefaults(
        to document: Document,
        docType: DocType,
        businessProfile: Document?
    ) -> Document {
        guard document.id.isEmpty else { return document }

        var document = document
        switch docType.id {
        case "SalesOrder":
            applyIfMissing(&document, field: "currency", from: "default_currency", businessProfile: businessProfile)
        case "SalesInvoice":
            applyIfMissing(&document, field: "currency", from: "default_currency", businessProfile: businessProfile)
            applyAccount(&document, field: "debit_to", slot: .receivable, businessProfile: businessProfile)
            applyAccount(&document, field: "income_account", slot: .income, businessProfile: businessProfile)
            applyIfMissing(&document, field: "tax_code", from: "default_tax_code", businessProfile: businessProfile)
        case "PurchaseOrder":
            applyIfMissing(&document, field: "currency", from: "default_currency", businessProfile: businessProfile)
        case "PurchaseInvoice":
            applyIfMissing(&document, field: "currency", from: "default_currency", businessProfile: businessProfile)
            applyAccount(&document, field: "credit_to", slot: .payable, businessProfile: businessProfile)
            applyAccount(&document, field: "expense_account", slot: .expense, businessProfile: businessProfile)
            applyIfMissing(&document, field: "tax_code", from: "default_tax_code", businessProfile: businessProfile)
        case "PurchaseReceipt", "SalesDelivery":
            applyIfMissing(&document, field: "currency", from: "default_currency", businessProfile: businessProfile)
        case "PaymentEntry":
            applyPaymentDefaults(to: &document, businessProfile: businessProfile)
        default:
            break
        }

        switch docType.id {
        case "SalesOrder", "SalesInvoice", "PurchaseOrder", "PurchaseInvoice",
             "PurchaseReceipt", "SalesDelivery":
            applyWarehouseDefault(toChildrenNamed: "items", in: &document, businessProfile: businessProfile)
        default:
            break
        }

        return document
    }

    static func prepareForFirstSave(
        _ document: Document,
        docType: DocType,
        businessProfile: Document?
    ) -> Document {
        guard document.id.isEmpty else { return document }

        var document = applyDraftDefaults(
            to: document,
            docType: docType,
            businessProfile: businessProfile
        )

        switch docType.id {
        case "SalesOrder", "SalesInvoice", "PurchaseOrder", "PurchaseInvoice",
             "PurchaseReceipt", "SalesDelivery":
            applyWarehouseDefault(toChildrenNamed: "items", in: &document, businessProfile: businessProfile)
        case "PaymentEntry":
            applyPaymentDefaults(to: &document, businessProfile: businessProfile)
        default:
            break
        }

        return document
    }

    private static func applyPaymentDefaults(
        to document: inout Document,
        businessProfile: Document?
    ) {
        guard case .string(let paymentType)? = document.fields["payment_type"] else { return }

        switch paymentType {
        case "Receive":
            applyAccount(&document, field: "paid_from", slot: .receivable, businessProfile: businessProfile)
            applyAccount(&document, field: "paid_to", slot: .cashBank, businessProfile: businessProfile)
        case "Pay":
            applyAccount(&document, field: "paid_from", slot: .cashBank, businessProfile: businessProfile)
            applyAccount(&document, field: "paid_to", slot: .payable, businessProfile: businessProfile)
        default:
            break
        }
    }

    /// Resolve a posting account for a slot via the central `HubAccountResolver`
    /// (today: the Business-Profile company default; extension point for
    /// per-customer / per-supplier / per-item posting profiles).
    private static func applyAccount(
        _ document: inout Document,
        field: String,
        slot: HubAccountSlot,
        businessProfile: Document?
    ) {
        guard isMissing(document.fields[field]) else { return }
        guard let accountId = HubAccountResolver.account(for: slot, businessProfile: businessProfile) else { return }
        document.fields[field] = .string(accountId)
    }

    private static func applyWarehouseDefault(
        toChildrenNamed key: String,
        in document: inout Document,
        businessProfile: Document?
    ) {
        guard let warehouse = nonEmptyValue(for: "default_warehouse", in: businessProfile) else { return }
        guard let children = document.children[key], !children.isEmpty else { return }

        document.children[key] = children.map { child in
            var child = child
            if isMissing(child.fields["warehouse"]) {
                child.fields["warehouse"] = warehouse
            }
            return child
        }
    }

    private static func applyIfMissing(
        _ document: inout Document,
        field: String,
        from businessProfileField: String,
        businessProfile: Document?
    ) {
        guard isMissing(document.fields[field]) else { return }
        guard let value = nonEmptyValue(for: businessProfileField, in: businessProfile) else { return }
        document.fields[field] = value
    }

    private static func nonEmptyValue(for key: String, in businessProfile: Document?) -> FieldValue? {
        guard let value = businessProfile?.fields[key] else { return nil }
        return isMissing(value) ? nil : value
    }

    private static func isMissing(_ value: FieldValue?) -> Bool {
        guard let value else { return true }
        if case .string(let text) = value {
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }
}
