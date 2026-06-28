import MercantisCore

public enum HubManifest: Sendable {
    public static let appID   = "app.mercantis.hub"
    public static let appName = "Mercantis Hub"
    public static let version = "0.1.0"

    // P0.3: each module's DocTypes are decorated with role-based PermissionRules
    // (HubPermissions) keyed by functional area, so Core's PermissionEngine has
    // real rules to enforce once operator roles are propagated (P0.2). System
    // Manager retains full access everywhere.
    public static let allDocTypes: [DocType] =
        HubPermissions.decorated(Setup.allDocTypes, scope: .setup)
        + HubPermissions.decorated(Tax.allDocTypes, scope: .accounting)
        + HubPermissions.decorated(CRM.allDocTypes, scope: .sales)
        + HubPermissions.decorated(Selling.allDocTypes, scope: .sales)
        + HubPermissions.decorated(Buying.allDocTypes, scope: .buying)
        + HubPermissions.decorated(Stock.allDocTypes, scope: .stock)
        + HubPermissions.decorated(Deliveries.allDocTypes, scope: .stock)
        + HubPermissions.decorated(Accounting.allDocTypes, scope: .accounting)
        + HubPermissions.decorated(Banking.allDocTypes, scope: .accounting)
        + HubPermissions.decorated(POS.allDocTypes, scope: .pos)
        + HubPermissions.decorated(Manufacturing.allDocTypes, scope: .stock)
        + HubPermissions.decorated(Capture.allDocTypes, scope: .setup)
        + HubPermissions.decorated(PrintingDocs.allDocTypes, scope: .setup)

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
            reports: HubReports.allReports,
            automationRules: [],
            dashboards: HubDashboards.allDashboards,
            localizations: []
        )
    }
}
