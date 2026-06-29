import Foundation
import MercantisCore

/// Pure decision for an invoice's post-submit money status, split out so it can
/// be unit-tested without an engine. `nonisolated` (pure value work).
nonisolated enum InvoiceStatusPolicy {

    /// The post-submit "money" states this policy manages. Draft / Cancelled and
    /// any other state are left untouched.
    static let managedStates: Set<String> = ["Submitted", "Overdue", "Paid"]

    /// The status a submitted invoice should hold given its balance and due
    /// date, or `nil` when no change is warranted (already correct, or the
    /// invoice is in a state this policy doesn't manage).
    ///
    /// - Fully settled (`outstanding <= tolerance`) → `Paid`.
    /// - Still owing and past its due date → `Overdue`.
    /// - Still owing and not yet due → `Submitted`.
    static func resolved(
        currentStatus: String,
        outstanding: Double,
        dueDate: Date?,
        today: Date,
        tolerance: Double = 0.005
    ) -> String? {
        guard managedStates.contains(currentStatus) else { return nil }
        let target: String
        if outstanding <= tolerance {
            target = "Paid"
        } else if let dueDate, today > dueDate {
            target = "Overdue"
        } else {
            target = "Submitted"
        }
        return target == currentStatus ? nil : target
    }
}

/// Keeps Sales / Purchase Invoice statuses in step with their money: flips an
/// invoice to **Paid** the moment a payment clears its balance (and back to
/// Submitted / Overdue if that payment is later cancelled), and marks
/// still-unpaid invoices **Overdue** once their due date passes.
///
/// Two triggers:
///  1. Event-driven (immediate): subscribes to `DocumentSubmittedEvent` /
///     `DocumentCancelledEvent` and, on a Payment Entry, re-derives the status
///     of every invoice it references. The Payment posting has already updated
///     each invoice's `outstanding_amount` inside its transaction, so the
///     re-fetch here sees the new balance.
///  2. Time-driven (launch sweep): `sweepOverdue` scans submitted invoices and
///     marks the past-due, still-owing ones Overdue — exposed as a static so the
///     UI can run it once per launch (there is no background scheduler).
///
/// Statuses are written directly (the automatic system transition isn't a
/// user-driven workflow action, so it isn't recorded in workflow history). The
/// service writes only invoices and via `engine.save`, so there's no
/// re-entrancy with the submit/cancel events it listens to.
public nonisolated final class InvoiceStatusService: @unchecked Sendable {

    static let invoiceTypes: Set<String> = ["SalesInvoice", "PurchaseInvoice"]

    private let engine: DocumentEngine
    private let emitter: EventEmitter
    private var tokens: [SubscriptionToken] = []

    public init(engine: DocumentEngine, emitter: EventEmitter) {
        self.engine = engine
        self.emitter = emitter
        wire()
    }

    deinit { for token in tokens { token.cancel() } }

    private func wire() {
        tokens.append(emitter.subscribe(DocumentSubmittedEvent.self) { [weak self] event in
            self?.handle(document: event.document)
        })
        tokens.append(emitter.subscribe(DocumentCancelledEvent.self) { [weak self] event in
            self?.handle(document: event.document)
        })
    }

    private func handle(document: Document) {
        guard document.docType == "PaymentEntry" else { return }
        for (docType, invoiceId) in referencedInvoices(of: document) {
            do {
                try reconcile(docType: docType, invoiceId: invoiceId)
            } catch {
                print("InvoiceStatus: failed to reconcile \(docType) \(invoiceId): \(error)")
            }
        }
    }

    /// (invoiceDocType, invoiceId) pairs a Payment Entry settles, from its
    /// `references` child rows. Only invoice references are returned.
    private func referencedInvoices(of payment: Document) -> [(String, String)] {
        var result: [(String, String)] = []
        for ref in payment.children["references"] ?? [] {
            guard let type = nonEmptyString(ref.fields["reference_doctype"]),
                  Self.invoiceTypes.contains(type),
                  let id = nonEmptyString(ref.fields["reference_name"]) else { continue }
            result.append((type, id))
        }
        return result
    }

    /// Re-derive and persist one invoice's status from its current balance.
    private func reconcile(docType: String, invoiceId: String, today: Date = Date()) throws {
        guard var invoice = try engine.fetch(docType: docType, id: invoiceId) else { return }
        guard let newStatus = InvoiceStatusPolicy.resolved(
            currentStatus: invoice.status,
            outstanding: outstanding(of: invoice),
            dueDate: date(invoice.fields["due_date"]),
            today: today
        ) else { return }
        invoice.status = newStatus
        try engine.save(invoice)
    }

    /// Mark every submitted, still-owing, past-due invoice Overdue (and correct
    /// any that are no longer past due / now settled). Returns the number of
    /// invoices whose status changed. Safe to run repeatedly — unchanged
    /// invoices are skipped.
    @discardableResult
    public static func sweepOverdue(engine: DocumentEngine, today: Date = Date()) -> Int {
        var changed = 0
        for docType in invoiceTypes {
            let invoices = (try? engine.list(docType: docType, applyRowAccess: false)) ?? []
            for var invoice in invoices where invoice.docStatus == 1 {
                guard let newStatus = InvoiceStatusPolicy.resolved(
                    currentStatus: invoice.status,
                    outstanding: outstandingValue(of: invoice),
                    dueDate: dateValue(invoice.fields["due_date"]),
                    today: today
                ) else { continue }
                invoice.status = newStatus
                if (try? engine.save(invoice)) != nil { changed += 1 }
            }
        }
        return changed
    }

    // MARK: - Coercion

    private func outstanding(of invoice: Document) -> Double { Self.outstandingValue(of: invoice) }

    /// Outstanding balance, falling back to the grand total when the field was
    /// never stamped (mirrors the Payment posting's own fallback).
    private static func outstandingValue(of invoice: Document) -> Double {
        if let o = doubleValue(invoice.fields["outstanding_amount"]) { return o }
        return doubleValue(invoice.fields["grand_total"]) ?? 0
    }

    private func date(_ value: FieldValue?) -> Date? { Self.dateValue(value) }
    private static func dateValue(_ value: FieldValue?) -> Date? {
        switch value {
        case .date(let d), .dateTime(let d): return d
        default: return nil
        }
    }

    private static func doubleValue(_ value: FieldValue?) -> Double? {
        switch value {
        case .double(let d): return d
        case .int(let i):    return Double(i)
        default:             return nil
        }
    }

    private func nonEmptyString(_ value: FieldValue?) -> String? {
        guard case .string(let s) = value else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
