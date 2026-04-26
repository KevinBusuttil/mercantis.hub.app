import MercantisCore       // replace `import Foundation`

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
            docTypes: [],          // populate as modules come online
            workflows: [],
            automationRules: [],
            reports: [],
            dashboards: [],
            permissions: [],
            localizations: [],
            extensionPoints: .empty
        )
    }
}
