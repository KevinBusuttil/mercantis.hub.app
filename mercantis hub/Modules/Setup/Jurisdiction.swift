import Foundation

/// Phase 1 (Accounting Autopilot) — jurisdiction model + library.
///
/// The owner picks a country (and whether they're tax-registered and on a cash
/// or accrual basis); everything downstream — which chart-of-accounts template
/// and which tax codes are seeded, the suggested currency, the tax vocabulary —
/// derives from the chosen `Jurisdiction`.

enum HubAccountingBasis: String, CaseIterable, Identifiable, Sendable {
    case accrual = "Accrual"
    case cash    = "Cash"

    var id: String { rawValue }

    var label: String { rawValue }

    var blurb: String {
        switch self {
        case .accrual: return "Record income and costs when invoiced (most businesses)."
        case .cash:    return "Record income and costs when money actually moves."
        }
    }
}

struct Jurisdiction: Identifiable, Equatable, Sendable {
    let id: String              // "MT", "GB", "IE", "EU", "US", "CA", "INT", "NONE"
    let name: String            // "Malta"
    let currencyCode: String    // suggested default currency
    let taxStyle: HubTaxStyle
    let taxRegimeLabel: String  // "VAT" / "Sales Tax" / "GST / HST" / "None"
    let taxIdLabel: String      // "VAT Number" / "EIN / Sales Tax ID" / …
}

enum HubJurisdictionLibrary {

    static let all: [Jurisdiction] = [
        Jurisdiction(id: "INT", name: "International (generic)", currencyCode: "EUR",
                     taxStyle: .vat, taxRegimeLabel: "VAT / Tax", taxIdLabel: "Tax Number"),
        Jurisdiction(id: "MT", name: "Malta", currencyCode: "EUR",
                     taxStyle: .vat, taxRegimeLabel: "VAT", taxIdLabel: "VAT Number"),
        Jurisdiction(id: "EU", name: "European Union (generic VAT)", currencyCode: "EUR",
                     taxStyle: .vat, taxRegimeLabel: "VAT", taxIdLabel: "VAT Number"),
        Jurisdiction(id: "GB", name: "United Kingdom", currencyCode: "GBP",
                     taxStyle: .vat, taxRegimeLabel: "VAT", taxIdLabel: "VAT Number"),
        Jurisdiction(id: "IE", name: "Ireland", currencyCode: "EUR",
                     taxStyle: .vat, taxRegimeLabel: "VAT", taxIdLabel: "VAT Number"),
        Jurisdiction(id: "US", name: "United States", currencyCode: "USD",
                     taxStyle: .salesTax, taxRegimeLabel: "Sales Tax", taxIdLabel: "EIN / Sales Tax ID"),
        Jurisdiction(id: "CA", name: "Canada", currencyCode: "CAD",
                     taxStyle: .gstHst, taxRegimeLabel: "GST / HST", taxIdLabel: "GST / HST Number"),
        Jurisdiction(id: "NONE", name: "No tax / cash basis", currencyCode: "EUR",
                     taxStyle: .none, taxRegimeLabel: "None", taxIdLabel: "Tax Number"),
    ]

    static let generic: Jurisdiction = all[0]

    static func jurisdiction(id: String) -> Jurisdiction {
        all.first { $0.id == id } ?? generic
    }

    /// Best-effort match from a currency code, used to keep the legacy
    /// (currency-only) onboarding path producing a sensible jurisdiction.
    static func forCurrency(_ code: String) -> Jurisdiction {
        switch code.uppercased() {
        case "GBP": return jurisdiction(id: "GB")
        case "USD": return jurisdiction(id: "US")
        case "CAD": return jurisdiction(id: "CA")
        default:    return generic
        }
    }
}
