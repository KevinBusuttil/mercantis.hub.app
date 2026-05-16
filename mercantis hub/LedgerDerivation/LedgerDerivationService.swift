import Foundation
import MercantisCore

/// Wall 7 — Hub-side derivation of append-only ledger rows from
/// transactional document submits.
///
/// Core's `AutomationActionHandler` contract mutates the current document
/// only; cross-DocType writes (writing rows in *other* DocTypes when a
/// parent is submitted) live outside that contract. The natural seam is
/// Core's typed event bus (ADR-020): this service subscribes to
/// `DocumentSubmittedEvent` and `DocumentCancelledEvent` on the shared
/// `EventEmitter`, routes by `docType`, and writes derived rows via
/// `DocumentEngine.save(_:)`.
///
/// ### Idempotency
///
/// Every derived row carries a deterministic id (e.g.
/// `SLE-<sourceId>-<rowIndex>-out`, `GL-<sourceId>-debit`). Because
/// `engine.save` upserts on non-empty id, re-firing the derivation against
/// the same source — e.g. when this service is wired in after the fact
/// and replayed — overwrites in place instead of duplicating.
///
/// ### Cancellation
///
/// On `DocumentCancelledEvent` the service writes reversal rows with the
/// debit / credit / qty values swapped (and an `is_reversal: true` flag).
/// Original rows stay in place so the trail is auditable. Reversal ids
/// are `<originalId>-reversal`.
///
/// ### Re-entrancy
///
/// The service ignores events whose `docType` it doesn't recognise — in
/// particular `StockLedgerEntry` and `GLEntry` themselves, so the
/// `engine.save(...)` calls below don't loop back.
public final class LedgerDerivationService: @unchecked Sendable {

    private let engine: DocumentEngine
    private let emitter: EventEmitter
    private var tokens: [SubscriptionToken] = []

    public init(engine: DocumentEngine, emitter: EventEmitter) {
        self.engine = engine
        self.emitter = emitter
        wire()
    }

    deinit {
        for token in tokens { token.cancel() }
    }

    // MARK: - Subscription wiring

    private func wire() {
        let submitToken = emitter.subscribe(DocumentSubmittedEvent.self) { [weak self] event in
            self?.handleSubmit(document: event.document)
        }
        let cancelToken = emitter.subscribe(DocumentCancelledEvent.self) { [weak self] event in
            self?.handleCancel(document: event.document)
        }
        tokens.append(submitToken)
        tokens.append(cancelToken)
    }

    private func handleSubmit(document: Document) {
        do {
            switch document.docType {
            case "StockEntry":      try deriveStockEntry(document, reversal: false)
            case "JournalEntry":    try deriveJournalEntry(document, reversal: false)
            case "PaymentEntry":    try derivePaymentEntry(document, reversal: false)
            case "SalesInvoice":    try deriveSalesInvoice(document, reversal: false)
            case "PurchaseInvoice": try derivePurchaseInvoice(document, reversal: false)
            default: return
            }
        } catch {
            // Derivation failed after the parent commit. Surface to the
            // console; production wiring should route to the audit log
            // or a notification channel. The parent doc is durable; the
            // derivation can be re-run from a maintenance UI later.
            print("LedgerDerivation submit error for \(document.docType) \(document.id): \(error)")
        }
    }

    private func handleCancel(document: Document) {
        do {
            switch document.docType {
            case "StockEntry":      try deriveStockEntry(document, reversal: true)
            case "JournalEntry":    try deriveJournalEntry(document, reversal: true)
            case "PaymentEntry":    try derivePaymentEntry(document, reversal: true)
            case "SalesInvoice":    try deriveSalesInvoice(document, reversal: true)
            case "PurchaseInvoice": try derivePurchaseInvoice(document, reversal: true)
            default: return
            }
        } catch {
            print("LedgerDerivation cancel error for \(document.docType) \(document.id): \(error)")
        }
    }

    // MARK: - Stock Entry → Stock Ledger Entry (InventTrans shape)

    private func deriveStockEntry(_ doc: Document, reversal: Bool) throws {
        let rows = doc.children["items"] ?? []
        let postingDate = doc.fields["posting_date"] ?? .date(Date())
        let postingTime = doc.fields["posting_time"]
        let transType = stockLedgerTransType(forPurpose: doc.fields["purpose"])

        for row in rows {
            let item        = row.fields["item"]
            let qty         = row.fields["qty"] ?? .double(0)
            let rate        = row.fields["valuation_rate"]
            let sourceWh    = row.fields["source_warehouse"]
            let targetWh    = row.fields["target_warehouse"]

            // Outbound leg (qty leaves source warehouse).
            if case .string(let whId)? = sourceWh, !whId.isEmpty {
                let signedQty = negate(qty, when: !reversal)
                try writeSLE(
                    id: "SLE-\(doc.id)-\(row.rowIndex)-out\(reversal ? "-reversal" : "")",
                    transType: transType,
                    item: item, warehouse: .string(whId),
                    postingDate: postingDate, postingTime: postingTime,
                    voucherNo: doc.id, qtyChange: signedQty,
                    rate: rate, isReversal: reversal,
                    company: doc.company
                )
            }
            // Inbound leg (qty enters target warehouse).
            if case .string(let whId)? = targetWh, !whId.isEmpty {
                let signedQty = negate(qty, when: reversal)
                try writeSLE(
                    id: "SLE-\(doc.id)-\(row.rowIndex)-in\(reversal ? "-reversal" : "")",
                    transType: transType,
                    item: item, warehouse: .string(whId),
                    postingDate: postingDate, postingTime: postingTime,
                    voucherNo: doc.id, qtyChange: signedQty,
                    rate: rate, isReversal: reversal,
                    company: doc.company
                )
            }
        }
    }

    /// Map a Stock Entry `purpose` to the corresponding StockLedgerEntry
    /// `trans_type` enum value (Phase 5.7 / AX synthesis). Material
    /// Receipts / Issues / Transfers map 1:1; manufacturing-flavoured
    /// purposes consolidate to Production for now.
    private func stockLedgerTransType(forPurpose purpose: FieldValue?) -> String {
        guard case .string(let p)? = purpose else { return "Issue" }
        switch p {
        case "Material Receipt":     return "Receipt"
        case "Material Issue":       return "Issue"
        case "Material Transfer":    return "Transfer"
        case "Repack":               return "Adjustment"
        case "Manufacturing",
             "Send to Subcontractor": return "Production"
        default:                     return "Issue"
        }
    }

    private func writeSLE(
        id: String,
        transType: String,
        item: FieldValue?,
        warehouse: FieldValue,
        postingDate: FieldValue,
        postingTime: FieldValue?,
        voucherNo: String,
        qtyChange: FieldValue,
        rate: FieldValue?,
        isReversal: Bool,
        company: String
    ) throws {
        guard let item else { return }
        // Append-only ledger: if this exact row already exists (deterministic
        // id), the derivation has already run for this voucher leg. Skip
        // to avoid tripping Core's optimistic-concurrency guard with a
        // blind overwrite.
        if try engine.fetch(docType: "StockLedgerEntry", id: id) != nil { return }

        var fields: [String: FieldValue] = [
            "trans_type":    .string(transType),
            "item":          item,
            "warehouse":     warehouse,
            "posting_date":  postingDate,
            "voucher_type":  .string("StockEntry"),
            "voucher_no":    .string(voucherNo),
            "qty_change":    qtyChange,
            "is_reversal":   .bool(isReversal),
        ]
        if let postingTime { fields["posting_time"] = postingTime }
        if let rate        { fields["valuation_rate"] = rate }

        let sle = Document(
            id: id,
            docType: "StockLedgerEntry",
            company: company,
            status: "",
            createdAt: Date(),
            updatedAt: Date(),
            syncVersion: 0,
            syncState: .local,
            fields: fields,
            children: [:]
        )
        try engine.save(sle)
    }

    // MARK: - Journal Entry → GL Entry

    private func deriveJournalEntry(_ doc: Document, reversal: Bool) throws {
        let rows = doc.children["accounts"] ?? []
        let postingDate = doc.fields["posting_date"] ?? .date(Date())
        let currency = doc.fields["company_currency"]

        for row in rows {
            guard let account = row.fields["account"] else { continue }
            // Reversal swaps debit and credit.
            let debit  = reversal ? (row.fields["credit"] ?? .double(0)) : (row.fields["debit"]  ?? .double(0))
            let credit = reversal ? (row.fields["debit"]  ?? .double(0)) : (row.fields["credit"] ?? .double(0))

            try writeGLEntry(
                id: "GL-\(doc.id)-\(row.rowIndex)\(reversal ? "-reversal" : "")",
                postingDate: postingDate,
                account: account,
                debit: debit, credit: credit,
                partyType: row.fields["party_type"],
                party: row.fields["party"],
                costCenter: row.fields["cost_center"],
                voucherType: "JournalEntry",
                voucherNo: doc.id,
                isReversal: reversal,
                company: doc.company
            )

            // Phase 5.7: when a JE row is party-tagged the subledger
            // should reflect the adjustment. Net effect for the customer
            // is `debit - credit` (Dr increases what they owe; Cr
            // decreases it). Reversal already swapped the values above.
            guard case .string(let partyTypeValue)? = row.fields["party_type"],
                  case .string(let partyId)? = row.fields["party"],
                  !partyId.isEmpty else { continue }
            let debitD  = asDouble(debit)  ?? 0
            let creditD = asDouble(credit) ?? 0
            let net = debitD - creditD
            guard net != 0 else { continue }
            let amount = FieldValue.double(net)

            switch partyTypeValue {
            case "Customer":
                try writeCustTrans(
                    id: "CT-\(doc.id)-\(row.rowIndex)\(reversal ? "-reversal" : "")",
                    transType: "Adjustment",
                    customer: .string(partyId),
                    postingDate: postingDate,
                    dueDate: nil,
                    amount: amount,
                    currency: currency,
                    voucherType: "JournalEntry",
                    voucherNo: doc.id,
                    isReversal: reversal,
                    company: doc.company
                )
            case "Supplier":
                // Supplier subledger uses the opposite sign convention
                // (positive = we owe them). A JE Cr to the supplier
                // increases what we owe → +net. Flip the sign.
                try writeVendTrans(
                    id: "VT-\(doc.id)-\(row.rowIndex)\(reversal ? "-reversal" : "")",
                    transType: "Adjustment",
                    supplier: .string(partyId),
                    postingDate: postingDate,
                    dueDate: nil,
                    amount: .double(-net),
                    currency: currency,
                    voucherType: "JournalEntry",
                    voucherNo: doc.id,
                    isReversal: reversal,
                    company: doc.company
                )
            default:
                break
            }
        }
    }

    // MARK: - Payment Entry → GL Entry + Cust/VendTrans + Settlement

    private func derivePaymentEntry(_ doc: Document, reversal: Bool) throws {
        let postingDate = doc.fields["posting_date"] ?? .date(Date())
        let amount      = doc.fields["paid_amount"] ?? .double(0)
        let paidFrom    = doc.fields["paid_from"]
        let paidTo      = doc.fields["paid_to"]
        let partyType   = doc.fields["party_type"]
        let party       = doc.fields["party"]
        let currency    = doc.fields["currency"]
        let paymentType = doc.fields["payment_type"]

        if let paidFrom {
            // Cash leaves paid_from: credit it (or debit on reversal).
            try writeGLEntry(
                id: "GL-\(doc.id)-from\(reversal ? "-reversal" : "")",
                postingDate: postingDate,
                account: paidFrom,
                debit: reversal ? amount : .double(0),
                credit: reversal ? .double(0) : amount,
                partyType: partyType, party: party,
                costCenter: nil,
                voucherType: "PaymentEntry",
                voucherNo: doc.id,
                isReversal: reversal,
                company: doc.company
            )
        }
        if let paidTo {
            // Cash arrives at paid_to: debit it (or credit on reversal).
            try writeGLEntry(
                id: "GL-\(doc.id)-to\(reversal ? "-reversal" : "")",
                postingDate: postingDate,
                account: paidTo,
                debit: reversal ? .double(0) : amount,
                credit: reversal ? amount : .double(0),
                partyType: partyType, party: party,
                costCenter: nil,
                voucherType: "PaymentEntry",
                voucherNo: doc.id,
                isReversal: reversal,
                company: doc.company
            )
        }

        // Phase 5.7: subledger Payment row + per-invoice Settlement rows.
        // payment_type "Receive" → CustTrans (party owes us less).
        // payment_type "Pay"     → VendTrans (we owe supplier less).
        // payment_type "Internal Transfer" → no subledger leg.
        guard case .string(let kind)? = paymentType, kind != "Internal Transfer" else { return }
        guard case .string(let partyId)? = party, !partyId.isEmpty else { return }

        // Negative on the customer / supplier side because the payment
        // reduces what they owe / what we owe.
        let subledgerAmount = signedAmount(amount, negate: !reversal)

        switch kind {
        case "Receive":
            try writeCustTrans(
                id: "CT-\(doc.id)\(reversal ? "-reversal" : "")",
                transType: reversal ? "Adjustment" : "Payment",
                customer: .string(partyId),
                postingDate: postingDate,
                dueDate: nil,
                amount: subledgerAmount,
                currency: currency,
                voucherType: "PaymentEntry",
                voucherNo: doc.id,
                isReversal: reversal,
                company: doc.company
            )
        case "Pay":
            try writeVendTrans(
                id: "VT-\(doc.id)\(reversal ? "-reversal" : "")",
                transType: reversal ? "Adjustment" : "Payment",
                supplier: .string(partyId),
                postingDate: postingDate,
                dueDate: nil,
                amount: subledgerAmount,
                currency: currency,
                voucherType: "PaymentEntry",
                voucherNo: doc.id,
                isReversal: reversal,
                company: doc.company
            )
        default:
            break
        }

        // Walk PaymentEntry.references → Settlement row per allocation +
        // decrement matching invoice's outstanding_amount.
        let refs = doc.children["references"] ?? []
        for (idx, ref) in refs.enumerated() {
            guard case .string(let invDocType)? = ref.fields["reference_doctype"],
                  case .string(let invNo)?      = ref.fields["reference_name"],
                  let allocated = ref.fields["allocated_amount"] else { continue }

            let settlementId = "STL-\(doc.id)-\(idx)\(reversal ? "-reversal" : "")"
            let wrote = try writeSettlement(
                id: settlementId,
                paymentVoucherType: "PaymentEntry",
                paymentVoucherNo: doc.id,
                invoiceVoucherType: invDocType,
                invoiceVoucherNo: invNo,
                partyType: kind == "Receive" ? "Customer" : "Supplier",
                party: partyId,
                allocatedAmount: signedAmount(allocated, negate: reversal),
                postingDate: postingDate,
                isReversal: reversal,
                company: doc.company
            )
            // Only adjust the invoice's outstanding_amount when the
            // Settlement was actually written this run. If the Settlement
            // already existed (re-fire / replay), the decrement has
            // already been applied — repeating it would double-count.
            if wrote {
                try adjustInvoiceOutstanding(
                    docType: invDocType,
                    id: invNo,
                    delta: signedAmount(allocated, negate: !reversal)
                )
            }
        }
    }

    // MARK: - Sales Invoice → GL Entry + CustTrans

    private func deriveSalesInvoice(_ doc: Document, reversal: Bool) throws {
        let postingDate = doc.fields["transaction_date"] ?? .date(Date())
        let amount      = doc.fields["grand_total"] ?? .double(0)
        guard let receivable = doc.fields["debit_to"],
              let income     = doc.fields["income_account"] else { return }
        let costCenter = doc.fields["cost_center"]
        let customer   = doc.fields["customer"]
        let currency   = doc.fields["currency"]
        let dueDate    = doc.fields["due_date"]

        // Dr Accounts Receivable (party = customer)
        try writeGLEntry(
            id: "GL-\(doc.id)-debit\(reversal ? "-reversal" : "")",
            postingDate: postingDate,
            account: receivable,
            debit: reversal ? .double(0) : amount,
            credit: reversal ? amount : .double(0),
            partyType: .string("Customer"), party: customer,
            costCenter: costCenter,
            voucherType: "SalesInvoice",
            voucherNo: doc.id,
            isReversal: reversal,
            company: doc.company
        )
        // Cr Income
        try writeGLEntry(
            id: "GL-\(doc.id)-credit\(reversal ? "-reversal" : "")",
            postingDate: postingDate,
            account: income,
            debit: reversal ? amount : .double(0),
            credit: reversal ? .double(0) : amount,
            partyType: nil, party: nil,
            costCenter: costCenter,
            voucherType: "SalesInvoice",
            voucherNo: doc.id,
            isReversal: reversal,
            company: doc.company
        )

        // Phase 5.7: CustTrans subledger row for drill-down reporting.
        // Reversal flips the sign and changes the trans_type to CreditNote
        // so the customer statement shows what actually happened.
        guard let customerValue = customer else { return }
        try writeCustTrans(
            id: "CT-\(doc.id)\(reversal ? "-reversal" : "")",
            transType: reversal ? "CreditNote" : "Invoice",
            customer: customerValue,
            postingDate: postingDate,
            dueDate: dueDate,
            amount: signedAmount(amount, negate: reversal),
            currency: currency,
            voucherType: "SalesInvoice",
            voucherNo: doc.id,
            isReversal: reversal,
            company: doc.company
        )
    }

    // MARK: - Purchase Invoice → GL Entry + VendTrans

    private func derivePurchaseInvoice(_ doc: Document, reversal: Bool) throws {
        let postingDate = doc.fields["transaction_date"] ?? .date(Date())
        let amount      = doc.fields["grand_total"] ?? .double(0)
        guard let payable  = doc.fields["credit_to"],
              let expense  = doc.fields["expense_account"] else { return }
        let costCenter = doc.fields["cost_center"]
        let supplier   = doc.fields["supplier"]
        let currency   = doc.fields["currency"]
        let dueDate    = doc.fields["due_date"]

        // Cr Accounts Payable (party = supplier)
        try writeGLEntry(
            id: "GL-\(doc.id)-credit\(reversal ? "-reversal" : "")",
            postingDate: postingDate,
            account: payable,
            debit: reversal ? amount : .double(0),
            credit: reversal ? .double(0) : amount,
            partyType: .string("Supplier"), party: supplier,
            costCenter: costCenter,
            voucherType: "PurchaseInvoice",
            voucherNo: doc.id,
            isReversal: reversal,
            company: doc.company
        )
        // Dr Expense
        try writeGLEntry(
            id: "GL-\(doc.id)-debit\(reversal ? "-reversal" : "")",
            postingDate: postingDate,
            account: expense,
            debit: reversal ? .double(0) : amount,
            credit: reversal ? amount : .double(0),
            partyType: nil, party: nil,
            costCenter: costCenter,
            voucherType: "PurchaseInvoice",
            voucherNo: doc.id,
            isReversal: reversal,
            company: doc.company
        )

        // Phase 5.7: VendTrans subledger row.
        guard let supplierValue = supplier else { return }
        try writeVendTrans(
            id: "VT-\(doc.id)\(reversal ? "-reversal" : "")",
            transType: reversal ? "CreditNote" : "Invoice",
            supplier: supplierValue,
            postingDate: postingDate,
            dueDate: dueDate,
            amount: signedAmount(amount, negate: reversal),
            currency: currency,
            voucherType: "PurchaseInvoice",
            voucherNo: doc.id,
            isReversal: reversal,
            company: doc.company
        )
    }

    // MARK: - Shared writer

    private func writeGLEntry(
        id: String,
        postingDate: FieldValue,
        account: FieldValue,
        debit: FieldValue,
        credit: FieldValue,
        partyType: FieldValue?,
        party: FieldValue?,
        costCenter: FieldValue?,
        voucherType: String,
        voucherNo: String,
        isReversal: Bool,
        company: String
    ) throws {
        if try engine.fetch(docType: "GLEntry", id: id) != nil { return }

        var fields: [String: FieldValue] = [
            "posting_date": postingDate,
            "account":      account,
            "debit":        debit,
            "credit":       credit,
            "voucher_type": .string(voucherType),
            "voucher_no":   .string(voucherNo),
            "is_reversal":  .bool(isReversal),
        ]
        if let partyType  { fields["party_type"]  = partyType }
        if let party      { fields["party"]       = party }
        if let costCenter { fields["cost_center"] = costCenter }

        let gle = Document(
            id: id,
            docType: "GLEntry",
            company: company,
            status: "",
            createdAt: Date(),
            updatedAt: Date(),
            syncVersion: 0,
            syncState: .local,
            fields: fields,
            children: [:]
        )
        try engine.save(gle)
    }

    // MARK: - Subledger writers (Phase 5.7)

    private func writeCustTrans(
        id: String,
        transType: String,
        customer: FieldValue,
        postingDate: FieldValue,
        dueDate: FieldValue?,
        amount: FieldValue,
        currency: FieldValue?,
        voucherType: String,
        voucherNo: String,
        isReversal: Bool,
        company: String
    ) throws {
        if try engine.fetch(docType: "CustTrans", id: id) != nil { return }

        var fields: [String: FieldValue] = [
            "trans_type":   .string(transType),
            "customer":     customer,
            "posting_date": postingDate,
            "amount":       amount,
            "voucher_type": .string(voucherType),
            "voucher_no":   .string(voucherNo),
            "is_reversal":  .bool(isReversal),
        ]
        if let dueDate  { fields["due_date"] = dueDate }
        if let currency { fields["currency"] = currency }

        let doc = Document(
            id: id, docType: "CustTrans", company: company, status: "",
            createdAt: Date(), updatedAt: Date(),
            syncVersion: 0, syncState: .local,
            fields: fields, children: [:]
        )
        try engine.save(doc)
    }

    private func writeVendTrans(
        id: String,
        transType: String,
        supplier: FieldValue,
        postingDate: FieldValue,
        dueDate: FieldValue?,
        amount: FieldValue,
        currency: FieldValue?,
        voucherType: String,
        voucherNo: String,
        isReversal: Bool,
        company: String
    ) throws {
        if try engine.fetch(docType: "VendTrans", id: id) != nil { return }

        var fields: [String: FieldValue] = [
            "trans_type":   .string(transType),
            "supplier":     supplier,
            "posting_date": postingDate,
            "amount":       amount,
            "voucher_type": .string(voucherType),
            "voucher_no":   .string(voucherNo),
            "is_reversal":  .bool(isReversal),
        ]
        if let dueDate  { fields["due_date"] = dueDate }
        if let currency { fields["currency"] = currency }

        let doc = Document(
            id: id, docType: "VendTrans", company: company, status: "",
            createdAt: Date(), updatedAt: Date(),
            syncVersion: 0, syncState: .local,
            fields: fields, children: [:]
        )
        try engine.save(doc)
    }

    /// Append a Settlement row. Returns `true` when a new row was
    /// written, `false` when the row already existed (so callers know
    /// whether to apply the matching outstanding-amount adjustment).
    @discardableResult
    private func writeSettlement(
        id: String,
        paymentVoucherType: String,
        paymentVoucherNo: String,
        invoiceVoucherType: String,
        invoiceVoucherNo: String,
        partyType: String,
        party: String,
        allocatedAmount: FieldValue,
        postingDate: FieldValue,
        isReversal: Bool,
        company: String
    ) throws -> Bool {
        if try engine.fetch(docType: "Settlement", id: id) != nil { return false }

        let fields: [String: FieldValue] = [
            "payment_voucher_type": .string(paymentVoucherType),
            "payment_voucher_no":   .string(paymentVoucherNo),
            "invoice_voucher_type": .string(invoiceVoucherType),
            "invoice_voucher_no":   .string(invoiceVoucherNo),
            "party_type":           .string(partyType),
            "party":                .string(party),
            "allocated_amount":     allocatedAmount,
            "posting_date":         postingDate,
            "is_reversal":          .bool(isReversal),
        ]
        let doc = Document(
            id: id, docType: "Settlement", company: company, status: "",
            createdAt: Date(), updatedAt: Date(),
            syncVersion: 0, syncState: .local,
            fields: fields, children: [:]
        )
        try engine.save(doc)
        return true
    }

    /// Adjust an invoice's `outstanding_amount` by `delta` (signed).
    /// Used by PaymentEntry settlement so Wall 6's Mark-as-Paid gate
    /// (`outstanding_amount <= 0`) actually fires when the invoice is
    /// fully paid. The field is marked `allowOnSubmit: true` on both
    /// SalesInvoice and PurchaseInvoice for exactly this reason.
    ///
    /// Best-effort: a missing invoice or a non-numeric outstanding
    /// silently no-ops rather than blocking the rest of the derivation.
    private func adjustInvoiceOutstanding(
        docType: String,
        id: String,
        delta: FieldValue
    ) throws {
        guard var invoice = try engine.fetch(docType: docType, id: id) else { return }
        let current  = asDouble(invoice.fields["outstanding_amount"])
            ?? asDouble(invoice.fields["grand_total"])
            ?? 0
        let deltaVal = asDouble(delta) ?? 0
        invoice.fields["outstanding_amount"] = .double(current + deltaVal)
        try engine.save(invoice)
    }

    // MARK: - Helpers

    /// Return `-value` when `flag` is true, otherwise return `value`.
    /// Used for signed qty / reversal flips.
    private func negate(_ value: FieldValue, when flag: Bool) -> FieldValue {
        guard flag else { return value }
        switch value {
        case .int(let i):    return .int(-i)
        case .double(let d): return .double(-d)
        default:             return value
        }
    }

    /// Wrap `value` with an optional sign flip — used by subledger writes
    /// where Invoice rows are positive and Payment rows are negative.
    private func signedAmount(_ value: FieldValue, negate: Bool) -> FieldValue {
        self.negate(value, when: negate)
    }

    private func asDouble(_ value: FieldValue?) -> Double? {
        switch value {
        case .double(let d): return d
        case .int(let i):    return Double(i)
        default:             return nil
        }
    }
}
