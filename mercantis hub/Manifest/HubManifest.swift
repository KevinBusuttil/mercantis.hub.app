import MercantisCore

public enum HubManifest: Sendable {
    public static let appID   = "app.mercantis.hub"
    public static let appName = "Mercantis Hub"
    public static let version = "0.1.0"

    public static let allDocTypes: [DocType] =
        Setup.allDocTypes        // tree masters and shared link targets first
        + CRM.allDocTypes        // Customer, Contact, Address, Lead + DynamicLink
        + Selling.allDocTypes    // Item + sales transactions
        + Buying.allDocTypes     // Supplier + purchase transactions
        + Stock.allDocTypes      // StockEntry + StockEntryDetail
        + Accounting.allDocTypes // Account + JournalEntry / PaymentEntry

    public static func docType(for id: String) -> DocType? {
        allDocTypes.first { $0.id == id }
    }

    public static func build() -> AppManifest {
        AppManifest(
            id: appID,
            name: appName,
            version: version,
            minimumCoreVersion: "0.1.0",
            description: "Mercantis Hub — first-party ERP application built on Mercantis Core.",
            doctypes: allDocTypes,
            workflows: HubWorkflows.allWorkflows,
            permissions: [],
            reports: [],
            automationRules: [],
            dashboards: [],
            localizations: []
        )
    }
}
