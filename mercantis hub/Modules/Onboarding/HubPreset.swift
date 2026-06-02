import Foundation

/// Phase 8 — business-type presets. Each preset turns on the optional
/// modules a given business needs, so a new user starts focused instead of
/// facing every ERP module at once. Presets only flip capability flags
/// (POS / Deliveries / Manufacturing); the core modules — Contacts, Sell,
/// Buy, Stock, Money, Setup — are always available.
enum HubPreset: String, CaseIterable, Identifiable, Sendable {
    case services
    case tradeDistribution
    case retailPOS
    case lightManufacturing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .services:          return "Services"
        case .tradeDistribution: return "Trade / Distribution"
        case .retailPOS:         return "Retail / POS"
        case .lightManufacturing: return "Light Manufacturing"
        }
    }

    var subtitle: String {
        switch self {
        case .services:
            return "Quotes, invoices, and payments. No stock-heavy extras."
        case .tradeDistribution:
            return "Buy, stock, and deliver goods — adds delivery routes."
        case .retailPOS:
            return "Sell over the counter — adds the point-of-sale till."
        case .lightManufacturing:
            return "Make and sell products — adds BOMs and work orders."
        }
    }

    var systemImage: String {
        switch self {
        case .services:          return "briefcase"
        case .tradeDistribution: return "truck.box"
        case .retailPOS:         return "creditcard.and.123"
        case .lightManufacturing: return "wrench.and.screwdriver"
        }
    }

    // MARK: - Capability mapping

    var enablesPOS: Bool { self == .retailPOS }
    var enablesDeliveries: Bool { self == .tradeDistribution }
    var enablesManufacturing: Bool { self == .lightManufacturing }
}
