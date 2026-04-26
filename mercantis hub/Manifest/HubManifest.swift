import MercantisCore

public enum HubManifest: Sendable {
    public static let appID   = "app.mercantis.hub"
    public static let appName = "Mercantis Hub"
    public static let version = "0.1.0"

    public static func build() -> AppManifest {
        AppManifest(
            id: appID,
            name: appName,
            version: version,
            minimumCoreVersion: "0.1.0",
            description: "Mercantis Hub — first-party ERP application built on Mercantis Core.",
            doctypes: [],
            workflows: [],
            permissions: [],
            reports: [],
            automationRules: [],
            dashboards: [],
            localizations: []
            // extensionPoints defaults to .empty
            // iconAsset defaults to nil
        )
    }
}
