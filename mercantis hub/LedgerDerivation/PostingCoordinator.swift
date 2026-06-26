//
//  PostingCoordinator.swift
//  mercantis hub
//
//  Phase 1 cutover — posts selected DocTypes INSIDE the submit/cancel
//  transaction via the Core UnitOfWork seam, so the source document and its
//  ledger rows commit together (or roll back together). This replaces the
//  post-commit event derivation for those DocTypes; everything else stays on the
//  legacy LedgerDerivationService event path until later increments.
//
//  Increment 2 added Journal Entry. Increment 3a adds the GL-only invoices
//  (Sales Invoice, Purchase Invoice) — no stock movement, so no in-transaction
//  Bin recompute is needed. Stock / POS / Payment DocTypes are converted later.
//
//  The DocTypes posted here are listed in `atomicDocTypes`, which
//  LedgerDerivationService skips so there is no double-posting.
//

import Foundation
import SwiftUI
import MercantisCore

/// Posting failures that abort (and roll back) a submit/cancel.
public nonisolated enum PostingError: Error {
    /// The GL legs of a batch did not balance — debits must equal credits.
    case unbalanced(debit: Double, credit: Double)
}

/// Builds the in-transaction posting closures passed to `DocumentEngine.submit`
/// / `cancel` for the DocTypes it owns.
///
/// `nonisolated` so it aligns with MercantisCore's nonisolated engine API and
/// the non-`@Sendable` `inTransaction` closure it produces, matching the
/// LedgerDerivationService pattern.
nonisolated final class PostingCoordinator {

    /// DocTypes posted atomically here — and therefore skipped by the legacy
    /// event path. Single source of truth shared with LedgerDerivationService.
    static let atomicDocTypes: Set<String> = ["JournalEntry", "SalesInvoice", "PurchaseInvoice", "PaymentEntry"]

    /// Tolerance for the balanced-GL check (currency rounding).
    private static let balanceTolerance = 0.005

    private let engine: DocumentEngine

    init(engine: DocumentEngine) {
        self.engine = engine
    }

    /// The `inTransaction` closure for submitting `doc`, or nil when `doc`'s
    /// DocType is not posted atomically here (caller submits normally).
    func submitClosure(for doc: Document) -> ((UnitOfWork) throws -> Void)? {
        guard Self.atomicDocTypes.contains(doc.docType) else { return nil }
        let engine = self.engine
        // Resolve company-default accounts and referenced invoices OUTSIDE the
        // write transaction (a read inside the write would be reentrant);
        // capture them for posting.
        let fallbackVat = Self.companyDefault("default_vat_account", engine: engine)
        let invoices = Self.referencedInvoices(for: doc, engine: engine)
        return { uow in try Self.post(doc, reversal: false, fallbackVatAccount: fallbackVat, referencedInvoices: invoices, engine: engine, in: uow) }
    }

    /// The `inTransaction` closure for cancelling `doc` (writes reversal rows).
    func cancelClosure(for doc: Document) -> ((UnitOfWork) throws -> Void)? {
        guard Self.atomicDocTypes.contains(doc.docType) else { return nil }
        let engine = self.engine
        let fallbackVat = Self.companyDefault("default_vat_account", engine: engine)
        let invoices = Self.referencedInvoices(for: doc, engine: engine)
        return { uow in try Self.post(doc, reversal: true, fallbackVatAccount: fallbackVat, referencedInvoices: invoices, engine: engine, in: uow) }
    }

    // MARK: - Posting

    private static func post(
        _ doc: Document, reversal: Bool, fallbackVatAccount: String?,
        referencedInvoices: [String: Document], engine: DocumentEngine, in uow: UnitOfWork
    ) throws {
        // Idempotency: one batch per (source, direction). Post is v1, reverse v2,
        // so cancel doesn't collide with the original and a re-fire is a no-op.
        let version = reversal ? 2 : 1
        let batchId = PostingBatch.makeID(sourceId: doc.id, version: version)
        if try uow.postingBatchExists(id: batchId) { return }

        let ledgerDocs: [Document]
        switch doc.docType {
        case "JournalEntry":    ledgerDocs = journalEntryRows(doc, reversal: reversal)
        case "SalesInvoice":    ledgerDocs = salesInvoiceRows(doc, reversal: reversal, fallbackVatAccount: fallbackVatAccount)
        case "PurchaseInvoice": ledgerDocs = purchaseInvoiceRows(doc, reversal: reversal, fallbackVatAccount: fallbackVatAccount)
        case "PaymentEntry":    ledgerDocs = paymentEntryRows(doc, reversal: reversal, referencedInvoices: referencedInvoices)
        default:                return
        }

        // Payment Entry's GL legs can legitimately be single-sided in some
        // account models (the contra side lives in the subledger), and the
        // legacy event path never balance-checked it — so don't reject it here.
        let enforceBalance = doc.docType != "PaymentEntry"
        try commit(ledgerDocs, sourceType: doc.docType, source: doc, reversal: reversal, version: version, enforceBalance: enforceBalance, engine: engine, in: uow)
    }

    /// Validate the GL legs balance (when required), then write every ledger row
    /// and the PostingBatch in the unit of work. A failed balance (or any write)
    /// throws, rolling the whole submit/cancel back.
    private static func commit(
        _ ledgerDocs: [Document],
        sourceType: String,
        source: Document,
        reversal: Bool,
        version: Int,
        enforceBalance: Bool,
        engine: DocumentEngine,
        in uow: UnitOfWork
    ) throws {
        if enforceBalance {
            var totalDebit = 0.0
            var totalCredit = 0.0
            for row in ledgerDocs where row.docType == "GLEntry" {
                totalDebit  += asDouble(row.fields["debit"]) ?? 0
                totalCredit += asDouble(row.fields["credit"]) ?? 0
            }
            guard abs(totalDebit - totalCredit) < balanceTolerance else {
                throw PostingError.unbalanced(debit: totalDebit, credit: totalCredit)
            }
        }

        for row in ledgerDocs {
            try engine.writeDocument(row, action: reversal ? "reverse" : "post", in: uow)
        }

        try uow.recordPostingBatch(PostingBatch(
            id: PostingBatch.makeID(sourceId: source.id, version: version),
            sourceType: sourceType,
            sourceId: source.id,
            status: reversal ? .reversed : .posted,
            version: version,
            postedAt: Date(),
            reversalOfBatch: reversal ? PostingBatch.makeID(sourceId: source.id, version: 1) : nil
        ))
    }

    // MARK: - Row builders (mirror LedgerDerivationService.derive*)

    private static func journalEntryRows(_ doc: Document, reversal: Bool) -> [Document] {
        let postingDate = doc.fields["posting_date"] ?? .date(Date())
        let currency = doc.fields["company_currency"]
        var docs: [Document] = []

        for row in doc.children["accounts"] ?? [] {
            guard let account = row.fields["account"] else { continue }
            let debit  = reversal ? (row.fields["credit"] ?? .double(0)) : (row.fields["debit"]  ?? .double(0))
            let credit = reversal ? (row.fields["debit"]  ?? .double(0)) : (row.fields["credit"] ?? .double(0))

            docs.append(glRow(
                id: "GL-\(doc.id)-\(row.rowIndex)\(suffix(reversal))",
                postingDate: postingDate, account: account,
                debit: debit, credit: credit,
                partyType: asString(row.fields["party_type"]), party: row.fields["party"],
                costCenter: row.fields["cost_center"],
                voucherType: "JournalEntry", voucherNo: doc.id, reversal: reversal, company: doc.company
            ))

            guard case .string(let partyTypeValue)? = row.fields["party_type"],
                  case .string(let partyId)? = row.fields["party"], !partyId.isEmpty else { continue }
            let net = (asDouble(debit) ?? 0) - (asDouble(credit) ?? 0)
            guard net != 0 else { continue }

            switch partyTypeValue {
            case "Customer":
                docs.append(custTransRow(
                    id: "CT-\(doc.id)-\(row.rowIndex)\(suffix(reversal))",
                    transType: "Adjustment", customer: .string(partyId),
                    postingDate: postingDate, dueDate: nil, amount: .double(net),
                    currency: currency, voucherType: "JournalEntry", voucherNo: doc.id,
                    reversal: reversal, company: doc.company
                ))
            case "Supplier":
                docs.append(vendTransRow(
                    id: "VT-\(doc.id)-\(row.rowIndex)\(suffix(reversal))",
                    transType: "Adjustment", supplier: .string(partyId),
                    postingDate: postingDate, dueDate: nil, amount: .double(-net),
                    currency: currency, voucherType: "JournalEntry", voucherNo: doc.id,
                    reversal: reversal, company: doc.company
                ))
            default:
                break
            }
        }
        return docs
    }

    private static func salesInvoiceRows(_ doc: Document, reversal: Bool, fallbackVatAccount: String?) -> [Document] {
        guard let receivable = doc.fields["debit_to"],
              let income = doc.fields["income_account"] else { return [] }
        let postingDate = doc.fields["transaction_date"] ?? .date(Date())
        let amount   = doc.fields["grand_total"] ?? .double(0)
        let costCenter = doc.fields["cost_center"]
        let customer = doc.fields["customer"]
        let currency = doc.fields["currency"]
        let dueDate  = doc.fields["due_date"]
        let taxRowsChildren = doc.children["taxes"] ?? []
        let grand = asDouble(amount) ?? 0
        let net   = asDouble(doc.fields["net_total"]) ?? (grand - totalTax(taxRowsChildren))

        var docs: [Document] = []
        // Dr AR (gross), Cr Income (net).
        docs.append(glRow(
            id: "GL-\(doc.id)-debit\(suffix(reversal))", postingDate: postingDate, account: receivable,
            debit: .double(reversal ? 0 : grand), credit: .double(reversal ? grand : 0),
            partyType: "Customer", party: customer, costCenter: costCenter,
            voucherType: "SalesInvoice", voucherNo: doc.id, reversal: reversal, company: doc.company
        ))
        docs.append(glRow(
            id: "GL-\(doc.id)-credit\(suffix(reversal))", postingDate: postingDate, account: income,
            debit: .double(reversal ? net : 0), credit: .double(reversal ? 0 : net),
            partyType: nil, party: nil, costCenter: costCenter,
            voucherType: "SalesInvoice", voucherNo: doc.id, reversal: reversal, company: doc.company
        ))
        docs += taxRowDocs(doc, rows: taxRowsChildren, party: customer, partyTypeValue: "Customer", isOutput: true, reversal: reversal, fallbackVatAccount: fallbackVatAccount)

        if let customerValue = customer {
            docs.append(custTransRow(
                id: "CT-\(doc.id)\(suffix(reversal))", transType: reversal ? "CreditNote" : "Invoice",
                customer: customerValue, postingDate: postingDate, dueDate: dueDate,
                amount: signed(amount, negate: reversal), currency: currency,
                voucherType: "SalesInvoice", voucherNo: doc.id, reversal: reversal, company: doc.company
            ))
        }
        return docs
    }

    private static func purchaseInvoiceRows(_ doc: Document, reversal: Bool, fallbackVatAccount: String?) -> [Document] {
        guard let payable = doc.fields["credit_to"],
              let expense = doc.fields["expense_account"] else { return [] }
        let postingDate = doc.fields["transaction_date"] ?? .date(Date())
        let amount   = doc.fields["grand_total"] ?? .double(0)
        let costCenter = doc.fields["cost_center"]
        let supplier = doc.fields["supplier"]
        let currency = doc.fields["currency"]
        let dueDate  = doc.fields["due_date"]
        let taxRowsChildren = doc.children["taxes"] ?? []
        let grand = asDouble(amount) ?? 0
        let net   = asDouble(doc.fields["net_total"]) ?? (grand - totalTax(taxRowsChildren))

        var docs: [Document] = []
        // Cr AP (gross), Dr Expense (net).
        docs.append(glRow(
            id: "GL-\(doc.id)-credit\(suffix(reversal))", postingDate: postingDate, account: payable,
            debit: .double(reversal ? grand : 0), credit: .double(reversal ? 0 : grand),
            partyType: "Supplier", party: supplier, costCenter: costCenter,
            voucherType: "PurchaseInvoice", voucherNo: doc.id, reversal: reversal, company: doc.company
        ))
        docs.append(glRow(
            id: "GL-\(doc.id)-debit\(suffix(reversal))", postingDate: postingDate, account: expense,
            debit: .double(reversal ? 0 : net), credit: .double(reversal ? net : 0),
            partyType: nil, party: nil, costCenter: costCenter,
            voucherType: "PurchaseInvoice", voucherNo: doc.id, reversal: reversal, company: doc.company
        ))
        docs += taxRowDocs(doc, rows: taxRowsChildren, party: supplier, partyTypeValue: "Supplier", isOutput: false, reversal: reversal, fallbackVatAccount: fallbackVatAccount)

        if let supplierValue = supplier {
            docs.append(vendTransRow(
                id: "VT-\(doc.id)\(suffix(reversal))", transType: reversal ? "CreditNote" : "Invoice",
                supplier: supplierValue, postingDate: postingDate, dueDate: dueDate,
                amount: signed(amount, negate: reversal), currency: currency,
                voucherType: "PurchaseInvoice", voucherNo: doc.id, reversal: reversal, company: doc.company
            ))
        }
        return docs
    }

    /// Mirrors `derivePaymentEntry`: GL leg(s) for the cash movement, a
    /// Cust/VendTrans payment row, a Settlement row per allocation, and the
    /// matching invoice `outstanding_amount` decrement (applied as an updated
    /// invoice document so it commits in the same transaction). The referenced
    /// invoices are pre-fetched outside the write transaction.
    private static func paymentEntryRows(_ doc: Document, reversal: Bool, referencedInvoices: [String: Document]) -> [Document] {
        let postingDate = doc.fields["posting_date"] ?? .date(Date())
        let amount   = doc.fields["paid_amount"] ?? .double(0)
        let paidFrom = doc.fields["paid_from"]
        let paidTo   = doc.fields["paid_to"]
        let partyType = asString(doc.fields["party_type"])
        let party    = doc.fields["party"]
        let currency = doc.fields["currency"]

        var docs: [Document] = []
        // Cash leaves paid_from (Cr), arrives at paid_to (Dr). Reversal flips.
        if let paidFrom {
            docs.append(glRow(
                id: "GL-\(doc.id)-from\(suffix(reversal))", postingDate: postingDate, account: paidFrom,
                debit: reversal ? amount : .double(0), credit: reversal ? .double(0) : amount,
                partyType: partyType, party: party, costCenter: nil,
                voucherType: "PaymentEntry", voucherNo: doc.id, reversal: reversal, company: doc.company
            ))
        }
        if let paidTo {
            docs.append(glRow(
                id: "GL-\(doc.id)-to\(suffix(reversal))", postingDate: postingDate, account: paidTo,
                debit: reversal ? .double(0) : amount, credit: reversal ? amount : .double(0),
                partyType: partyType, party: party, costCenter: nil,
                voucherType: "PaymentEntry", voucherNo: doc.id, reversal: reversal, company: doc.company
            ))
        }

        // Subledger + settlement only for party payments (not Internal Transfer).
        guard case .string(let kind)? = doc.fields["payment_type"], kind != "Internal Transfer",
              case .string(let partyId)? = party, !partyId.isEmpty else { return docs }

        let subledgerAmount = signed(amount, negate: !reversal)
        switch kind {
        case "Receive":
            docs.append(custTransRow(
                id: "CT-\(doc.id)\(suffix(reversal))", transType: reversal ? "Adjustment" : "Payment",
                customer: .string(partyId), postingDate: postingDate, dueDate: nil,
                amount: subledgerAmount, currency: currency,
                voucherType: "PaymentEntry", voucherNo: doc.id, reversal: reversal, company: doc.company
            ))
        case "Pay":
            docs.append(vendTransRow(
                id: "VT-\(doc.id)\(suffix(reversal))", transType: reversal ? "Adjustment" : "Payment",
                supplier: .string(partyId), postingDate: postingDate, dueDate: nil,
                amount: subledgerAmount, currency: currency,
                voucherType: "PaymentEntry", voucherNo: doc.id, reversal: reversal, company: doc.company
            ))
        default:
            break
        }

        // Settlement row per allocation + accumulate the outstanding delta per
        // invoice (delta is signed: submit decrements, cancel restores).
        var outstandingDelta: [String: Double] = [:]
        for (idx, ref) in (doc.children["references"] ?? []).enumerated() {
            guard case .string(let invType)? = ref.fields["reference_doctype"],
                  case .string(let invNo)? = ref.fields["reference_name"],
                  let allocated = ref.fields["allocated_amount"] else { continue }
            docs.append(settlementRow(
                id: "STL-\(doc.id)-\(idx)\(suffix(reversal))",
                paymentVoucherNo: doc.id, invoiceVoucherType: invType, invoiceVoucherNo: invNo,
                partyType: kind == "Receive" ? "Customer" : "Supplier", party: partyId,
                allocatedAmount: signed(allocated, negate: reversal), postingDate: postingDate,
                reversal: reversal, company: doc.company
            ))
            outstandingDelta[invNo, default: 0] += asDouble(signed(allocated, negate: !reversal)) ?? 0
        }

        // Updated invoice documents with the adjusted outstanding_amount
        // (allowOnSubmit on Sales/Purchase Invoice), written in the same tx.
        for (invNo, delta) in outstandingDelta {
            guard var invoice = referencedInvoices[invNo] else { continue }
            let current = asDouble(invoice.fields["outstanding_amount"])
                ?? asDouble(invoice.fields["grand_total"]) ?? 0
            invoice.fields["outstanding_amount"] = .double(current + delta)
            docs.append(invoice)
        }

        return docs
    }

    private static func settlementRow(
        id: String, paymentVoucherNo: String, invoiceVoucherType: String, invoiceVoucherNo: String,
        partyType: String, party: String, allocatedAmount: FieldValue, postingDate: FieldValue,
        reversal: Bool, company: String
    ) -> Document {
        let fields: [String: FieldValue] = [
            "payment_voucher_type": .string("PaymentEntry"),
            "payment_voucher_no":   .string(paymentVoucherNo),
            "invoice_voucher_type": .string(invoiceVoucherType),
            "invoice_voucher_no":   .string(invoiceVoucherNo),
            "party_type":           .string(partyType),
            "party":                .string(party),
            "allocated_amount":     allocatedAmount,
            "posting_date":         postingDate,
            "is_reversal":          .bool(reversal),
        ]
        return ledger(id: id, docType: "Settlement", company: company, fields: fields)
    }

    /// Pre-fetch the invoices a Payment Entry settles, keyed by id, OUTSIDE the
    /// write transaction. Empty for non-PaymentEntry DocTypes.
    private static func referencedInvoices(for doc: Document, engine: DocumentEngine) -> [String: Document] {
        guard doc.docType == "PaymentEntry" else { return [:] }
        var result: [String: Document] = [:]
        for ref in doc.children["references"] ?? [] {
            guard case .string(let invType)? = ref.fields["reference_doctype"], !invType.isEmpty,
                  case .string(let invNo)? = ref.fields["reference_name"], !invNo.isEmpty,
                  result[invNo] == nil else { continue }
            if let invoice = try? engine.fetch(docType: invType, id: invNo) {
                result[invNo] = invoice
            }
        }
        return result
    }

    /// VAT GL leg (Cr output / Dr input) + TaxTrans row per tax child row.
    private static func taxRowDocs(
        _ doc: Document, rows: [ChildRow], party: FieldValue?, partyTypeValue: String,
        isOutput: Bool, reversal: Bool, fallbackVatAccount: String?
    ) -> [Document] {
        guard !rows.isEmpty else { return [] }
        let postingDate = doc.fields["transaction_date"] ?? doc.fields["posting_date"] ?? .date(Date())
        let fallbackAccount = fallbackVatAccount
        var docs: [Document] = []

        for (idx, row) in rows.enumerated() {
            let taxAmount = asDouble(row.fields["tax_amount"]) ?? 0
            let taxable   = asDouble(row.fields["taxable_amount"]) ?? 0
            let account   = nonEmptyString(row.fields["tax_account"]) ?? fallbackAccount

            if taxAmount != 0, let account {
                let amt = FieldValue.double(taxAmount)
                let zero = FieldValue.double(0)
                let debit:  FieldValue
                let credit: FieldValue
                if isOutput {
                    debit  = reversal ? amt : zero
                    credit = reversal ? zero : amt
                } else {
                    debit  = reversal ? zero : amt
                    credit = reversal ? amt : zero
                }
                docs.append(glRow(
                    id: "GL-\(doc.id)-tax-\(idx)\(suffix(reversal))", postingDate: postingDate,
                    account: .string(account), debit: debit, credit: credit,
                    partyType: nil, party: nil, costCenter: nil,
                    voucherType: doc.docType, voucherNo: doc.id, reversal: reversal, company: doc.company
                ))
            }

            var taxFields: [String: FieldValue] = [
                "tax_type":     .string(asString(row.fields["tax_type"]) ?? "VAT"),
                "posting_date": postingDate,
                "base_amount":  signed(.double(taxable), negate: reversal),
                "tax_amount":   signed(.double(taxAmount), negate: reversal),
                "party_type":   .string(partyTypeValue),
                "voucher_type": .string(doc.docType),
                "voucher_no":   .string(doc.id),
                "is_reversal":  .bool(reversal),
            ]
            if let taxCode = asString(row.fields["tax_code"]) { taxFields["tax"] = .string(taxCode) }
            if let rate = row.fields["rate"] { taxFields["rate"] = rate }
            if let party { taxFields["party"] = party }
            docs.append(ledger(id: "TT-\(doc.id)-\(idx)\(suffix(reversal))", docType: "TaxTrans", company: doc.company, fields: taxFields))
        }
        return docs
    }

    // MARK: - Ledger document builders

    private static func glRow(
        id: String, postingDate: FieldValue, account: FieldValue,
        debit: FieldValue, credit: FieldValue,
        partyType: String?, party: FieldValue?, costCenter: FieldValue?,
        voucherType: String, voucherNo: String, reversal: Bool, company: String
    ) -> Document {
        var fields: [String: FieldValue] = [
            "posting_date": postingDate,
            "account":      account,
            "debit":        debit,
            "credit":       credit,
            "voucher_type": .string(voucherType),
            "voucher_no":   .string(voucherNo),
            "is_reversal":  .bool(reversal),
        ]
        if let partyType  { fields["party_type"]  = .string(partyType) }
        if let party      { fields["party"]       = party }
        if let costCenter { fields["cost_center"] = costCenter }
        return ledger(id: id, docType: "GLEntry", company: company, fields: fields)
    }

    private static func custTransRow(
        id: String, transType: String, customer: FieldValue, postingDate: FieldValue,
        dueDate: FieldValue?, amount: FieldValue, currency: FieldValue?,
        voucherType: String, voucherNo: String, reversal: Bool, company: String
    ) -> Document {
        var fields: [String: FieldValue] = [
            "trans_type":   .string(transType),
            "customer":     customer,
            "posting_date": postingDate,
            "amount":       amount,
            "voucher_type": .string(voucherType),
            "voucher_no":   .string(voucherNo),
            "is_reversal":  .bool(reversal),
        ]
        if let dueDate  { fields["due_date"] = dueDate }
        if let currency { fields["currency"] = currency }
        return ledger(id: id, docType: "CustTrans", company: company, fields: fields)
    }

    private static func vendTransRow(
        id: String, transType: String, supplier: FieldValue, postingDate: FieldValue,
        dueDate: FieldValue?, amount: FieldValue, currency: FieldValue?,
        voucherType: String, voucherNo: String, reversal: Bool, company: String
    ) -> Document {
        var fields: [String: FieldValue] = [
            "trans_type":   .string(transType),
            "supplier":     supplier,
            "posting_date": postingDate,
            "amount":       amount,
            "voucher_type": .string(voucherType),
            "voucher_no":   .string(voucherNo),
            "is_reversal":  .bool(reversal),
        ]
        if let dueDate  { fields["due_date"] = dueDate }
        if let currency { fields["currency"] = currency }
        return ledger(id: id, docType: "VendTrans", company: company, fields: fields)
    }

    private static func ledger(id: String, docType: String, company: String, fields: [String: FieldValue]) -> Document {
        Document(
            id: id, docType: docType, company: company, status: "",
            createdAt: Date(), updatedAt: Date(),
            syncVersion: 0, syncState: .local,
            fields: fields, children: [:]
        )
    }

    // MARK: - Value helpers

    private static func suffix(_ reversal: Bool) -> String { reversal ? "-reversal" : "" }

    private static func totalTax(_ rows: [ChildRow]) -> Double {
        rows.reduce(0) { $0 + (asDouble($1.fields["tax_amount"]) ?? 0) }
    }

    private static func signed(_ value: FieldValue, negate: Bool) -> FieldValue {
        guard negate else { return value }
        return .double(-(asDouble(value) ?? 0))
    }

    private static func companyDefault(_ key: String, engine: DocumentEngine) -> String? {
        guard let company = (try? engine.list(docType: "Company"))?.first else { return nil }
        return nonEmptyString(company.fields[key])
    }

    private static func asDouble(_ value: FieldValue?) -> Double? {
        switch value {
        case .double(let d): return d
        case .int(let i): return Double(i)
        case .string(let s): return Double(s)
        default: return nil
        }
    }

    private static func asString(_ value: FieldValue?) -> String? {
        if case .string(let s)? = value { return s }
        return nil
    }

    private static func nonEmptyString(_ value: FieldValue?) -> String? {
        guard let s = asString(value), !s.isEmpty else { return nil }
        return s
    }
}

// MARK: - Environment injection

private struct PostingCoordinatorKey: EnvironmentKey {
    static let defaultValue: PostingCoordinator? = nil
}

extension EnvironmentValues {
    /// The app's posting coordinator, injected at app scope so the form's
    /// submit/cancel actions can route atomic-posting DocTypes through the
    /// submit transaction. Nil in previews / tests that don't inject it.
    var postingCoordinator: PostingCoordinator? {
        get { self[PostingCoordinatorKey.self] }
        set { self[PostingCoordinatorKey.self] = newValue }
    }
}
