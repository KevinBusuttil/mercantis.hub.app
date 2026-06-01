import Foundation
import SwiftUI
import Combine

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
    static let posEnabledKey = "MercantisHub.posEnabled"

    @Published var showAdvanced: Bool {
        didSet { UserDefaults.standard.set(showAdvanced, forKey: Self.defaultsKey) }
    }

    /// Retail / POS opt-in. POS stays hidden until a retail business turns
    /// it on (stands in for the Retail/POS preset until Phase 8 ships
    /// presets). Defaults to off so non-retail users never see the till.
    @Published var posEnabled: Bool {
        didSet { UserDefaults.standard.set(posEnabled, forKey: Self.posEnabledKey) }
    }

    init() {
        self.showAdvanced = UserDefaults.standard.bool(forKey: Self.defaultsKey)
        self.posEnabled = UserDefaults.standard.bool(forKey: Self.posEnabledKey)
    }

    /// Whether an item at `visibility` should currently be shown.
    func isVisible(_ visibility: HubVisibility) -> Bool {
        visibility == .normal || showAdvanced
    }

    /// Whether a module should currently be shown, applying both the
    /// advanced gate and the POS feature flag.
    func isModuleVisible(_ module: HubModule) -> Bool {
        if module.requiresPOS && !posEnabled { return false }
        return isVisible(module.visibility)
    }
}
