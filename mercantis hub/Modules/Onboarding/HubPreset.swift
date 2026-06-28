import Foundation

/// Phase 8 / Phase 4 (Accounting Autopilot) — business-type presets. Each preset
/// turns on the optional modules a given business needs *and* tailors the
/// accounting, so a new user starts focused instead of facing every ERP module
/// at once. Presets flip capability flags (POS / Deliveries / Manufacturing) and
/// pick a sensible default income account; the core modules — Contacts, Sell,
/// Buy, Stock, Money, Setup — are always available.
enum HubPreset: String, CaseIterable, Identifiable, Sendable {
    case services
    case consultant
    case retailPOS
    case tradeDistribution
    case lightManufacturing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .services:          return "Services"
        case .consultant:        return "Consultant / Freelancer"
        case .retailPOS:         return "Retail / POS"
        case .tradeDistribution: return "Trade / Distribution"
        case .lightManufacturing: return "Light Manufacturing"
        }
    }

    var subtitle: String {
        switch self {
        case .services:
            return "Quotes, invoices, and payments. No stock-heavy extras."
        case .consultant:
            return "Bill your time and expenses. The simplest set-up of all."
        case .retailPOS:
            return "Sell over the counter — adds the point-of-sale till."
        case .tradeDistribution:
            return "Buy, stock, and deliver goods — adds delivery routes."
        case .lightManufacturing:
            return "Make and sell products — adds BOMs and work orders."
        }
    }

    var systemImage: String {
        switch self {
        case .services:          return "briefcase"
        case .consultant:        return "person.crop.square.filled.and.at.rectangle"
        case .retailPOS:         return "creditcard.and.123"
        case .tradeDistribution: return "truck.box"
        case .lightManufacturing: return "wrench.and.screwdriver"
        }
    }

    // MARK: - Capability mapping

    var enablesPOS: Bool { self == .retailPOS }
    var enablesDeliveries: Bool { self == .tradeDistribution }
    var enablesManufacturing: Bool { self == .lightManufacturing }

    // MARK: - Accounting tailoring (Phase 4)

    /// The ledger account new sales / invoices default their income to. A
    /// service or consulting business books to **Service Income**; a goods
    /// business books to **Sales**. Both ids exist in every seeded chart, so the
    /// posting anchors are unaffected.
    var defaultIncomeAccountId: String {
        switch self {
        case .services, .consultant:
            return "ServiceIncome"
        case .retailPOS, .tradeDistribution, .lightManufacturing:
            return "Sales"
        }
    }

    /// Whether this business holds stock. Service and consulting businesses do
    /// not, so inventory features are noise for them; goods businesses do.
    var tracksInventory: Bool {
        switch self {
        case .services, .consultant:
            return false
        case .retailPOS, .tradeDistribution, .lightManufacturing:
            return true
        }
    }
}
