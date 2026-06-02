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
    static let deliveriesEnabledKey = "MercantisHub.deliveriesEnabled"
    static let manufacturingEnabledKey = "MercantisHub.manufacturingEnabled"
    static let onboardingDoneKey = "MercantisHub.onboardingComplete"
    static let presetKey = "MercantisHub.businessPreset"

    @Published var showAdvanced: Bool {
        didSet { UserDefaults.standard.set(showAdvanced, forKey: Self.defaultsKey) }
    }

    /// Retail / POS opt-in. POS stays hidden until a retail business turns
    /// it on (set by the Retail/POS preset, toggleable later).
    @Published var posEnabled: Bool {
        didSet { UserDefaults.standard.set(posEnabled, forKey: Self.posEnabledKey) }
    }

    /// Delivery routes & fulfilment opt-in (Trade/Distribution preset).
    @Published var deliveriesEnabled: Bool {
        didSet { UserDefaults.standard.set(deliveriesEnabled, forKey: Self.deliveriesEnabledKey) }
    }

    /// Light-manufacturing opt-in (BOMs / work orders).
    @Published var manufacturingEnabled: Bool {
        didSet { UserDefaults.standard.set(manufacturingEnabled, forKey: Self.manufacturingEnabledKey) }
    }

    /// Whether the first-run wizard has been completed (or skipped).
    @Published var onboardingComplete: Bool {
        didSet { UserDefaults.standard.set(onboardingComplete, forKey: Self.onboardingDoneKey) }
    }

    /// The business-type preset the user picked, if any.
    @Published var preset: HubPreset? {
        didSet { UserDefaults.standard.set(preset?.rawValue, forKey: Self.presetKey) }
    }

    init() {
        let defaults = UserDefaults.standard
        self.showAdvanced = defaults.bool(forKey: Self.defaultsKey)
        self.posEnabled = defaults.bool(forKey: Self.posEnabledKey)
        self.deliveriesEnabled = defaults.bool(forKey: Self.deliveriesEnabledKey)
        self.manufacturingEnabled = defaults.bool(forKey: Self.manufacturingEnabledKey)
        self.onboardingComplete = defaults.bool(forKey: Self.onboardingDoneKey)
        self.preset = defaults.string(forKey: Self.presetKey).flatMap(HubPreset.init(rawValue:))
    }

    /// Apply a business-type preset: record it and switch the optional
    /// modules on/off to match. The user can still toggle each later.
    func apply(_ preset: HubPreset) {
        self.preset = preset
        posEnabled = preset.enablesPOS
        deliveriesEnabled = preset.enablesDeliveries
        manufacturingEnabled = preset.enablesManufacturing
    }

    /// Whether an item at `visibility` should currently be shown.
    func isVisible(_ visibility: HubVisibility) -> Bool {
        visibility == .normal || showAdvanced
    }

    /// Whether a module should currently be shown, applying both the
    /// advanced gate and the preset-driven capability flags.
    func isModuleVisible(_ module: HubModule) -> Bool {
        if module.requiresPOS && !posEnabled { return false }
        if module.requiresDeliveries && !deliveriesEnabled { return false }
        if module.requiresManufacturing && !manufacturingEnabled { return false }
        return isVisible(module.visibility)
    }
}
