import Foundation
import MercantisCore

/// Pure expiry decision for a Quotation, split out for testing.
nonisolated enum QuotationExpiryPolicy {
    /// Whether a quotation should be marked Expired: it must be live
    /// (`Submitted` — not already Ordered / Lost / Expired / Cancelled) and
    /// carry a `valid_till` date that has passed.
    static func isExpired(currentStatus: String, validTill: Date?, today: Date) -> Bool {
        guard currentStatus == "Submitted", let validTill else { return false }
        return today > validTill
    }
}

/// Marks live Quotations Expired once their valid-till date passes. There is no
/// background scheduler, so the sweep is exposed as a static the UI runs once
/// per launch (alongside the invoice-overdue sweep). Mirrors
/// `InvoiceStatusService.sweepOverdue`: the status is written directly (an
/// automatic system transition, not a user-driven workflow action).
public nonisolated enum QuotationExpiryService {

    /// Mark every Submitted, past-valid-till Quotation as Expired. Returns the
    /// number whose status changed. Safe to run repeatedly.
    @discardableResult
    public static func sweepExpired(engine: DocumentEngine, today: Date = Date()) -> Int {
        let quotations = (try? engine.list(docType: "Quotation", applyRowAccess: false)) ?? []
        var changed = 0
        for var quote in quotations where quote.docStatus == 1 {
            guard QuotationExpiryPolicy.isExpired(
                currentStatus: quote.status,
                validTill: date(quote.fields["valid_till"]),
                today: today
            ) else { continue }
            quote.status = "Expired"
            if (try? engine.save(quote)) != nil { changed += 1 }
        }
        return changed
    }

    private static func date(_ value: FieldValue?) -> Date? {
        switch value {
        case .date(let d), .dateTime(let d): return d
        default: return nil
        }
    }
}
