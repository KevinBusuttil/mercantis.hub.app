import Foundation
import SwiftUI

/// How prominent a navigation item is for a typical small-business user.
///
/// `normal` is the everyday surface (customers, invoices, payments, stock
/// movements…). `advanced` covers the AX-style audit/accounting spine
/// (GL Entry, CustTrans, VendTrans, Settlement, Tax Transaction, Stock
/// Ledger) and the optional manufacturing module — important internally,
/// but noise for most users, so hidden until explicitly revealed.
enum HubVisibility: Int, Comparable, Sendable {
    case normal = 0
    case advanced = 1

    static func < (lhs: HubVisibility, rhs: HubVisibility) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Local, single-user preference toggling the advanced / accountant surface.
///
/// Stored in `UserDefaults` (no role system in this pass — Hub is an
/// offline-first single-user workspace), defaulting to *off* so the internal
/// ledgers and manufacturing stay out of the way until an accountant or power
/// user opts in. Mirrors the `HubIdentity` UserDefaults strategy.
final class HubVisibilitySettings: ObservableObject {
    static let defaultsKey = "MercantisHub.showAdvancedAccounting"

    @Published var showAdvanced: Bool {
        didSet { UserDefaults.standard.set(showAdvanced, forKey: Self.defaultsKey) }
    }

    init() {
        self.showAdvanced = UserDefaults.standard.bool(forKey: Self.defaultsKey)
    }

    /// Whether an item at `visibility` should currently be shown.
    func isVisible(_ visibility: HubVisibility) -> Bool {
        visibility == .normal || showAdvanced
    }
}
