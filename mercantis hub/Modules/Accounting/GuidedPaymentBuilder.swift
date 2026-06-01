import Foundation
import MercantisCore

/// Phase 5 — Guided Payments. Whether the guided flow is collecting money
/// from a customer or paying a supplier.
enum GuidedPaymentMode: Equatable, Sendable {
    case receive   // customer pays us
    case pay       // we pay a supplier

    var paymentType: String { self == .receive ? "Receive" : "Pay" }
    var partyType: String   { self == .receive ? "Customer" : "Supplier" }
    var partyDocType: String { self == .receive ? "Customer" : "Supplier" }
    var partyNameField: String { self == .receive ? "customer_name" : "supplier_name" }
    var invoiceDocType: String { self == .receive ? "SalesInvoice" : "PurchaseInvoice" }
    /// The field on the invoice that names the party.
    var invoicePartyField: String { self == .receive ? "customer" : "supplier" }
    var title: String { self == .receive ? "Receive Payment" : "Pay Supplier" }
}

/// Pure construction logic behind the guided payment flows. Kept free of
/// `DocumentEngine` and SwiftUI so allocation maths and the Payment Entry
/// shape are unit-testable; the flow view supplies the loaded documents and
/// resolved accounts.
///
/// The output is an ordinary Payment Entry `Document` with `references`
/// child rows — exactly the shape `LedgerDerivationService.derivePaymentEntry`
/// already consumes — so GL, CustTrans / VendTrans, Settlement, and the
/// invoice `outstanding_amount` decrement all keep working unchanged.
enum GuidedPaymentBuilder {

    /// One outstanding invoice/bill presented for allocation.
    struct Outstanding: Identifiable, Equatable {
        let id: String           // invoice/bill document id
        let docType: String      // SalesInvoice / PurchaseInvoice
        let date: Date?
        let grandTotal: Double
        let outstanding: Double
        let currency: String?
    }

    /// A user-confirmed allocation of part of a payment to one invoice.
    struct Allocation: Equatable {
        let invoiceId: String
        let invoiceDocType: String
        let total: Double
        let outstanding: Double
        let allocated: Double
    }

    /// Filter a list of invoice/bill documents down to the outstanding ones
    /// for the guided flow: posted (docStatus 1) and still owing. Sorted by
    /// date so the oldest debt is offered first.
    static func outstanding(from invoices: [Document], mode: GuidedPaymentMode) -> [Outstanding] {
        invoices.compactMap { doc -> Outstanding? in
            guard doc.docStatus == 1 else { return nil }
            let grand = doubleValue(doc.fields["grand_total"]) ?? 0
            // Fall back to grand_total when outstanding hasn't been stamped
            // yet (older invoices) so they remain payable.
            let owing = doubleValue(doc.fields["outstanding_amount"]) ?? grand
            guard owing > 0.0001 else { return nil }
            return Outstanding(
                id: doc.id,
                docType: mode.invoiceDocType,
                date: dateValue(doc.fields["transaction_date"]),
                grandTotal: grand,
                outstanding: owing,
                currency: stringValue(doc.fields["currency"])
            )
        }
        .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }

    /// Sum of allocated amounts, rounded to currency precision.
    static func totalAllocated(_ allocations: [Allocation]) -> Double {
        round2(allocations.reduce(0) { $0 + $1.allocated })
    }

    /// Build the (draft) Payment Entry document from confirmed allocations.
    ///
    /// - `bankAccount`: the cash / bank account the money moves to (receive)
    ///   or from (pay).
    /// - `partyAccount`: the receivable (receive) or payable (pay) control
    ///   account, normally the Business Profile default.
    static func buildPaymentEntry(
        mode: GuidedPaymentMode,
        party: String,
        postingDate: Date,
        currency: String?,
        bankAccount: String,
        partyAccount: String,
        allocations: [Allocation]
    ) -> Document {
        let total = totalAllocated(allocations)

        // Receive: money lands in the bank, clearing the receivable.
        // Pay: money leaves the bank, clearing the payable. The GL
        // derivation credits paid_from and debits paid_to.
        let paidFrom = mode == .receive ? partyAccount : bankAccount
        let paidTo   = mode == .receive ? bankAccount  : partyAccount

        var fields: [String: FieldValue] = [
            "payment_type":    .string(mode.paymentType),
            "posting_date":    .date(postingDate),
            "party_type":      .string(mode.partyType),
            "party":           .string(party),
            "paid_from":       .string(paidFrom),
            "paid_to":         .string(paidTo),
            "paid_amount":     .double(total),
            "received_amount": .double(total),
        ]
        if let currency, !currency.isEmpty {
            fields["currency"] = .string(currency)
        }

        let references: [ChildRow] = allocations.enumerated().map { index, alloc in
            ChildRow(
                id: "alloc-\(index)",
                rowIndex: index,
                fields: [
                    "reference_doctype":  .string(alloc.invoiceDocType),
                    "reference_name":     .string(alloc.invoiceId),
                    "total_amount":       .double(alloc.total),
                    "outstanding_amount": .double(alloc.outstanding),
                    "allocated_amount":   .double(round2(alloc.allocated)),
                ]
            )
        }

        return Document(
            id: "",
            docType: "PaymentEntry",
            company: "",
            status: "Draft",
            createdAt: Date(),
            updatedAt: Date(),
            syncVersion: 0,
            syncState: .local,
            fields: fields,
            children: ["references": references]
        )
    }

    // MARK: - Coercion helpers

    static func round2(_ value: Double) -> Double { (value * 100).rounded() / 100 }

    private static func doubleValue(_ value: FieldValue?) -> Double? {
        switch value {
        case .double(let d): return d
        case .int(let i):    return Double(i)
        case .string(let s): return Double(s)
        default:             return nil
        }
    }

    private static func stringValue(_ value: FieldValue?) -> String? {
        guard case .string(let s) = value else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func dateValue(_ value: FieldValue?) -> Date? {
        switch value {
        case .date(let d), .dateTime(let d): return d
        default: return nil
        }
    }
}
