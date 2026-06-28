import Foundation

/// Phase 3 (Accounting Autopilot) — the rule for the **books-lock date**: once an
/// owner has filed a period (a VAT/GST return, or just "I've finished with
/// everything up to here"), they lock the books up to that date so nothing can
/// be posted into it by accident. Pure and tiny so both the posting guard
/// (`PostingCoordinator`) and the UI share one definition of "locked".
enum BooksLockPolicy {

    /// True when a posting dated `postingDate` is blocked by a lock set to
    /// `lockDate`. A posting on or before the lock date is blocked; a nil lock
    /// date means the books are open. Compared by calendar day so a same-day
    /// posting is treated as inside the locked period.
    static func isLocked(postingDate: Date, lockDate: Date?, calendar: Calendar = .current) -> Bool {
        guard let lockDate else { return false }
        return calendar.startOfDay(for: postingDate) <= calendar.startOfDay(for: lockDate)
    }
}
