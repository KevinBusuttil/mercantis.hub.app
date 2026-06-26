//
//  PostingCoordinator.swift
//  mercantis hub
//
//  Phase 1 (cutover increment 2) — posts selected DocTypes INSIDE the submit
//  transaction via the Core UnitOfWork seam, so the source document and its
//  ledger rows commit together (or roll back together). This replaces the
//  post-commit event derivation for those DocTypes; everything else stays on the
//  legacy LedgerDerivationService event path until later increments.
//
//  This increment handles Journal Entry. The DocTypes posted here are listed in
//  `atomicDocTypes`, which LedgerDerivationService skips so there is no
//  double-posting.
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
    static let atomicDocTypes: Set<String> = ["JournalEntry"]

    private let engine: DocumentEngine

    init(engine: DocumentEngine) {
        self.engine = engine
    }

    /// The `inTransaction` closure for submitting `doc`, or nil when `doc`'s
    /// DocType is not posted atomically here (caller submits normally).
    func submitClosure(for doc: Document) -> ((UnitOfWork) throws -> Void)? {
        guard Self.atomicDocTypes.contains(doc.docType) else { return nil }
        let engine = self.engine
        return { uow in try Self.post(doc, reversal: false, engine: engine, in: uow) }
    }

    /// The `inTransaction` closure for cancelling `doc` (writes reversal rows).
    func cancelClosure(for doc: Document) -> ((UnitOfWork) throws -> Void)? {
        guard Self.atomicDocTypes.contains(doc.docType) else { return nil }
        let engine = self.engine
        return { uow in try Self.post(doc, reversal: true, engine: engine, in: uow) }
    }

    // MARK: - Posting

    private static func post(_ doc: Document, reversal: Bool, engine: DocumentEngine, in uow: UnitOfWork) throws {
        switch doc.docType {
        case "JournalEntry":
            try postJournalEntry(doc, reversal: reversal, engine: engine, in: uow)
        default:
            break
        }
    }

    /// Mirrors `LedgerDerivationService.deriveJournalEntry`, but builds the GL /
    /// subledger rows, validates the batch balances, and writes everything plus
    /// the PostingBatch inside `uow` — so a JE that doesn't balance (or any write
    /// failure) rolls the whole submit back and the document stays Draft.
    private static func postJournalEntry(_ doc: Document, reversal: Bool, engine: DocumentEngine, in uow: UnitOfWork) throws {
        // Distinct batch ids for post (v1) vs reverse (v2) so cancel doesn't
        // collide with the original, and a re-fire is idempotent.
        let version = reversal ? 2 : 1
        let batchId = PostingBatch.makeID(sourceId: doc.id, version: version)
        if try uow.postingBatchExists(id: batchId) { return }

        let postingDate = doc.fields["posting_date"] ?? .date(Date())
        let currency = doc.fields["company_currency"]
        let rows = doc.children["accounts"] ?? []

        var totalDebit = 0.0
        var totalCredit = 0.0
        var ledgerDocs: [Document] = []

        for row in rows {
            guard let account = row.fields["account"] else { continue }
            // Reversal swaps debit and credit.
            let debit  = reversal ? (row.fields["credit"] ?? .double(0)) : (row.fields["debit"]  ?? .double(0))
            let credit = reversal ? (row.fields["debit"]  ?? .double(0)) : (row.fields["credit"] ?? .double(0))
            totalDebit  += asDouble(debit) ?? 0
            totalCredit += asDouble(credit) ?? 0

            var glFields: [String: FieldValue] = [
                "posting_date": postingDate,
                "account":      account,
                "debit":        debit,
                "credit":       credit,
                "voucher_type": .string("JournalEntry"),
                "voucher_no":   .string(doc.id),
                "is_reversal":  .bool(reversal),
            ]
            if let partyType = row.fields["party_type"]   { glFields["party_type"]  = partyType }
            if let party = row.fields["party"]            { glFields["party"]       = party }
            if let costCenter = row.fields["cost_center"] { glFields["cost_center"] = costCenter }
            ledgerDocs.append(ledgerDoc(
                id: "GL-\(doc.id)-\(row.rowIndex)\(reversal ? "-reversal" : "")",
                docType: "GLEntry", company: doc.company, fields: glFields
            ))

            // Party-tagged rows adjust the customer / supplier subledger,
            // mirroring deriveJournalEntry's sign conventions.
            guard case .string(let partyTypeValue)? = row.fields["party_type"],
                  case .string(let partyId)? = row.fields["party"], !partyId.isEmpty else { continue }
            let net = (asDouble(debit) ?? 0) - (asDouble(credit) ?? 0)
            guard net != 0 else { continue }

            switch partyTypeValue {
            case "Customer":
                var fields: [String: FieldValue] = [
                    "trans_type":   .string("Adjustment"),
                    "customer":     .string(partyId),
                    "posting_date": postingDate,
                    "amount":       .double(net),
                    "voucher_type": .string("JournalEntry"),
                    "voucher_no":   .string(doc.id),
                    "is_reversal":  .bool(reversal),
                ]
                if let currency { fields["currency"] = currency }
                ledgerDocs.append(ledgerDoc(
                    id: "CT-\(doc.id)-\(row.rowIndex)\(reversal ? "-reversal" : "")",
                    docType: "CustTrans", company: doc.company, fields: fields
                ))
            case "Supplier":
                // Supplier sign convention is opposite (positive = we owe them).
                var fields: [String: FieldValue] = [
                    "trans_type":   .string("Adjustment"),
                    "supplier":     .string(partyId),
                    "posting_date": postingDate,
                    "amount":       .double(-net),
                    "voucher_type": .string("JournalEntry"),
                    "voucher_no":   .string(doc.id),
                    "is_reversal":  .bool(reversal),
                ]
                if let currency { fields["currency"] = currency }
                ledgerDocs.append(ledgerDoc(
                    id: "VT-\(doc.id)-\(row.rowIndex)\(reversal ? "-reversal" : "")",
                    docType: "VendTrans", company: doc.company, fields: fields
                ))
            default:
                break
            }
        }

        // Balanced-GL gate: a JE that does not balance must not post.
        guard abs(totalDebit - totalCredit) < 0.005 else {
            throw PostingError.unbalanced(debit: totalDebit, credit: totalCredit)
        }

        for ledger in ledgerDocs {
            try engine.writeDocument(ledger, action: reversal ? "reverse" : "post", in: uow)
        }

        try uow.recordPostingBatch(PostingBatch(
            id: batchId,
            sourceType: "JournalEntry",
            sourceId: doc.id,
            status: reversal ? .reversed : .posted,
            version: version,
            postedAt: Date(),
            reversalOfBatch: reversal ? PostingBatch.makeID(sourceId: doc.id, version: 1) : nil
        ))
    }

    private static func ledgerDoc(id: String, docType: String, company: String, fields: [String: FieldValue]) -> Document {
        Document(
            id: id, docType: docType, company: company, status: "",
            createdAt: Date(), updatedAt: Date(),
            syncVersion: 0, syncState: .local,
            fields: fields, children: [:]
        )
    }

    private static func asDouble(_ value: FieldValue?) -> Double? {
        switch value {
        case .double(let d): return d
        case .int(let i): return Double(i)
        case .string(let s): return Double(s)
        default: return nil
        }
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
