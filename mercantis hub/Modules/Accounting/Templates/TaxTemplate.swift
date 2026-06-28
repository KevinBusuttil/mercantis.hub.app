import Foundation

/// Phase 1 (Accounting Autopilot) — the tax-code template library.
///
/// A VAT/GST/sales-tax-registered owner should get the right tax codes on day
/// one, never hand-build them. Given a jurisdiction and whether the business is
/// tax-registered, this returns the starter set of `TaxCode` records to seed,
/// with exactly one marked default (wired onto the Business Profile so it
/// auto-applies to new invoices).

struct TaxCodeTemplate: Equatable {
    let id: String
    let name: String
    let type: String        // "VAT" / "SalesTax"
    let rate: Double
    let isDefault: Bool
}

enum HubTaxTemplateLibrary {

    /// The tax codes to seed for a jurisdiction. When not registered, a single
    /// 0% "No Tax" code is the default so invoices carry no tax until the owner
    /// registers.
    static func codes(for jurisdiction: Jurisdiction, registered: Bool) -> [TaxCodeTemplate] {
        guard registered, jurisdiction.taxStyle != .none else {
            return [TaxCodeTemplate(id: "NO-TAX", name: "No Tax", type: "VAT", rate: 0, isDefault: true)]
        }

        switch jurisdiction.id {
        case "MT":
            return vat([("VAT-STD", "Standard (18%)", 18, true),
                        ("VAT-RED-7", "Reduced (7%)", 7, false),
                        ("VAT-RED-5", "Reduced (5%)", 5, false),
                        ("VAT-ZERO", "Zero-rated (0%)", 0, false),
                        ("VAT-EXEMPT", "Exempt", 0, false)])
        case "GB":
            return vat([("VAT-STD", "Standard (20%)", 20, true),
                        ("VAT-RED-5", "Reduced (5%)", 5, false),
                        ("VAT-ZERO", "Zero-rated (0%)", 0, false),
                        ("VAT-EXEMPT", "Exempt", 0, false)])
        case "IE":
            return vat([("VAT-STD", "Standard (23%)", 23, true),
                        ("VAT-RED-13", "Reduced (13.5%)", 13.5, false),
                        ("VAT-RED-9", "Second Reduced (9%)", 9, false),
                        ("VAT-ZERO", "Zero-rated (0%)", 0, false),
                        ("VAT-EXEMPT", "Exempt", 0, false)])
        case "EU":
            return vat([("VAT-STD", "Standard (21%)", 21, true),
                        ("VAT-RED", "Reduced (10%)", 10, false),
                        ("VAT-ZERO", "Zero-rated (0%)", 0, false),
                        ("VAT-EXEMPT", "Exempt", 0, false),
                        ("VAT-RC", "Reverse Charge (0%)", 0, false)])
        case "US":
            return [TaxCodeTemplate(id: "SALES-TAX", name: "Sales Tax", type: "SalesTax", rate: 0, isDefault: true),
                    TaxCodeTemplate(id: "TAX-EXEMPT", name: "Tax Exempt", type: "SalesTax", rate: 0, isDefault: false)]
        case "CA":
            return [TaxCodeTemplate(id: "GST", name: "GST (5%)", type: "SalesTax", rate: 5, isDefault: true),
                    TaxCodeTemplate(id: "HST", name: "HST (13%)", type: "SalesTax", rate: 13, isDefault: false),
                    TaxCodeTemplate(id: "ZERO", name: "Zero-rated (0%)", type: "SalesTax", rate: 0, isDefault: false),
                    TaxCodeTemplate(id: "EXEMPT", name: "Exempt", type: "SalesTax", rate: 0, isDefault: false)]
        default: // INT — generic; owner sets the standard rate.
            return vat([("VAT-STD", "Standard", 0, true),
                        ("VAT-ZERO", "Zero-rated (0%)", 0, false),
                        ("VAT-EXEMPT", "Exempt", 0, false)])
        }
    }

    /// The id of the default code to wire onto `Company.default_tax_code`.
    static func defaultCodeId(for jurisdiction: Jurisdiction, registered: Bool) -> String? {
        codes(for: jurisdiction, registered: registered).first(where: \.isDefault)?.id
    }

    private static func vat(_ rows: [(String, String, Double, Bool)]) -> [TaxCodeTemplate] {
        rows.map { TaxCodeTemplate(id: $0.0, name: $0.1, type: "VAT", rate: $0.2, isDefault: $0.3) }
    }
}
